package logic

import "core:testing"
import c "../contracts"

// Headless staffing-slot regressions (roadmap task 4). No renderer, window or GPU
// resource is involved, and no test depends on wall-clock time or a random seed.
//
// Fixture: a farm with one continuous supervisor slot, two continuous worker slots
// and two on-demand repairer slots; a plant with one continuous worker slot; a
// workshop with no roles; and the always-on control unit. No station stock or ships
// are needed because staffing reads only Runtime_Subject state.

// Read-only per-test fixtures. The test runner executes tests on separate threads;
// these arrays are never written after initialization.
staffing_test_roles: [3]Subject_Role = {.worker,.supervisor,.repairer}
staffing_test_supervisors: [1]Subject_Role = {.supervisor}

Staffing_Test :: struct {
	definitions: [4]Building_Type,
	initial: [4]Building_Instance,
	role_definitions: [3]Subject_Role_Definition,
	human: [1]Subject_Type,
	game: State,
	fleet: Transport_State,
}

staffing_test_init :: proc(r: ^Staffing_Test, subjects: []Subject_Instance = nil) {
	r.role_definitions = {{role_id=.worker},{role_id=.supervisor},{role_id=.repairer}}
	r.human = {{id="human",roles=r.role_definitions[:],work_time=12,rest_time=12,extra_work_time=4,
		min_work_health=0.4,min_colony_health=0.1,
		health_rates={work_gain_per_hour=0.002,rest_gain_per_hour=0.01,extra_work_loss_per_hour=0.025,
			max_inactivity_loss_per_hour=0.012,inactivity_max_time=72,station_recovery_per_hour=0.04}}}
	r.definitions = {
		{id="control_unit"},
		{id="farm",residents={type="human",capacity=8},subject_roles={
			{role_id=.supervisor,quantity=1,staffing_mode=.continuous},
			{role_id=.worker,quantity=2,staffing_mode=.continuous},
			{role_id=.repairer,quantity=2,staffing_mode=.on_demand},
		}},
		{id="plant",subject_roles={{role_id=.worker,quantity=1,staffing_mode=.continuous}}},
		{id="workshop"},
	}
	r.initial = {
		{id="CU",building_id="control_unit",health=1},
		{id="F1",building_id="farm",health=1,enable_at_start=true,residents_amount=f32(0)},
		{id="P1",building_id="plant",health=1,enable_at_start=true},
		{id="W1",building_id="workshop",health=1,enable_at_start=true},
	}
	r.game = new_session(r.initial[:],r.definitions[:],context.allocator)
	r.fleet = new_transports({},{},nil,r.initial[:],subjects,context.allocator,r.definitions[:],r.human[:])
}

staffing_test_destroy :: proc(r: ^Staffing_Test) {
	destroy_transports(&r.fleet,context.allocator)
	destroy(&r.game,context.allocator)
}

// Adds one live individual at a named building. The caller chooses activity and
// phase; the person is placed on the building's position when one is named.
staffing_test_person :: proc(r: ^Staffing_Test, roles: []Subject_Role, activity: Subject_Activity, building_id: string, health: f32 = 1) -> int {
	position, target: c.Vector2
	for building in r.initial {
		if building.id == building_id { position = building.position; target = building.position; break }
	}
	index := add_runtime_subject(&r.fleet,{subject_id="human",residence=building_id,roles=roles,activity=activity,
		position=position,target=target,destination=building_id,health=health})
	assert(index >= 0)
	return index
}

// Records a physical claim directly, as the future physical-handoff step will.
// derive_staffing validates it independently.
staffing_test_claim :: proc(r: ^Staffing_Test, index: int, target: c.Shift_Assignment) {
	subject := &r.fleet.subjects[index]
	subject.assignment = target
	subject.phase = .Working
}

@(test)
continuous_slots_materialize_deterministically_and_are_reset_safe :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	// 3 farm slots (1 supervisor + 2 workers) + 1 plant worker; zero quantities and
	// on-demand entries never materialize an automatic slot.
	testing.expect(t,staffing_slot_count(&r.game) == 4)
	expected := [?]c.Staffing_Slot_Snapshot{
		{building_id="F1",role_id=.supervisor,slot_index=0},
		{building_id="F1",role_id=.worker,slot_index=0},
		{building_id="F1",role_id=.worker,slot_index=1},
		{building_id="P1",role_id=.worker,slot_index=0},
	}
	for want, i in expected {
		testing.expectf(t,staffing_slot_snapshot(&r.game,i) == want,"slot %d order",i)
	}
	testing.expect(t,building_required_slots(&r.game,1) == 3)
	testing.expect(t,building_required_slots(&r.game,2) == 1)
	testing.expect(t,building_required_slots(&r.game,3) == 0)
	// On-demand roles and unknown slot indices never resolve to a materialized slot.
	_, repairer := staffing_slot_lookup(&r.game,{building_id="F1",role_id=.repairer,slot_index=0})
	_, past_end := staffing_slot_lookup(&r.game,{building_id="F1",role_id=.worker,slot_index=2})
	_, unknown_building := staffing_slot_lookup(&r.game,{building_id="XX",role_id=.worker,slot_index=0})
	testing.expect(t,!repairer && !past_end && !unknown_building)
	testing.expect(t,staffing_coverage(&r.game,1,.repairer) == c.Staffing_Coverage{role_id=.repairer})
	testing.expect(t,building_staffed(&r.game,3) && !building_staffed(&r.game,1) && !building_staffed(&r.game,2))
	// Reset clears derived claims and rebuilds the identical table without touching
	// the level template.
	derive_staffing(&r.game,&r.fleet)
	reset(&r.game,r.initial[:])
	reset_transports(&r.fleet,{},r.initial[:],nil)
	testing.expect(t,staffing_slot_count(&r.game) == 4 && !building_staffed(&r.game,1))
	for want, i in expected { testing.expect(t,staffing_slot_snapshot(&r.game,i) == want) }
	amount, has_amount := r.initial[1].residents_amount.?
	testing.expect(t,has_amount && amount == 0)
}

@(test)
initial_assignments_start_on_shift_in_level_order :: proc(t: ^testing.T) {
	subjects := [?]Subject_Instance{
		{id="S1",subject_id="human",residence="F1",health=1,initial_assignment={building_id="F1",role_id=.worker},roles=staffing_test_roles[:],speed=1},
		{id="S2",subject_id="human",residence="F1",health=1,initial_assignment={building_id="F1",role_id=.worker},roles=staffing_test_roles[:],speed=1},
		{id="S3",subject_id="human",residence="F1",health=1,initial_assignment={building_id="F1",role_id=.supervisor},roles=staffing_test_roles[:],speed=1},
		{id="S4",subject_id="human",residence="F1",health=1,initial_assignment={building_id="P1",role_id=.worker},roles=staffing_test_roles[:],speed=1},
	}
	r: Staffing_Test
	staffing_test_init(&r,subjects[:])
	defer staffing_test_destroy(&r)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,len(r.fleet.subjects) == 4)
	testing.expect(t,building_staffed(&r.game,1) && building_staffed(&r.game,2) && building_staffed(&r.game,3))
	// Level order fills consecutive slots of one building role.
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == r.fleet.subjects[2].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == r.fleet.subjects[0].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).occupant == r.fleet.subjects[1].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,3).occupant == r.fleet.subjects[3].id)
	// An initial shift starts physically at the workplace with clean timers.
	for subject in r.fleet.subjects {
		testing.expect(t,subject.activity == .Inside && subject.phase == .Working && subject.work_hours == 0)
		testing.expect(t,subject.occupation != "")
	}
	for subject in r.fleet.subjects[:3] {
		testing.expect(t,subject.destination == "F1" && subject.position == r.initial[1].position)
	}
	testing.expect(t,r.fleet.subjects[3].destination == "P1" && r.fleet.subjects[3].position == r.initial[2].position)
	coverage := staffing_coverage(&r.game,1,.worker)
	testing.expect(t,coverage.required_slots == 2 && coverage.covered_slots == 2 && coverage.reserved_slots == 0)
}

@(test)
duplicate_coverage_is_impossible_with_stable_id_priority :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	first := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	second := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	lower_id := r.fleet.subjects[first].id
	higher_id := r.fleet.subjects[second].id
	testing.expect(t,lower_id < higher_id)
	// Put the newer (higher) ID first so resolution cannot rely on array order.
	r.fleet.subjects[first], r.fleet.subjects[second] = r.fleet.subjects[second], r.fleet.subjects[first]
	target := c.Shift_Assignment{building_id="F1",role_id=.worker,slot_index=0}
	for index in 0..<2 { staffing_test_claim(&r,index,target) }
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == lower_id)
	winner := &r.fleet.subjects[second] // The lower ID moved to the later array position.
	loser := &r.fleet.subjects[first]
	testing.expect(t,winner.id == lower_id && loser.id == higher_id)
	assigned, has_assignment := winner.assignment.?
	testing.expect(t,has_assignment && assigned == target)
	testing.expect(t,loser.assignment == nil && loser.phase == .Resting)
	// Re-deriving is stable: the released claim cannot be resurrected.
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == lower_id)
	testing.expect(t,r.fleet.subjects[first].assignment == nil)
}

@(test)
duplicate_reservations_follow_the_same_stable_id_priority :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	first := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	second := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	lower_id := r.fleet.subjects[first].id
	higher_id := r.fleet.subjects[second].id
	// Newer ID first: the lower stable ID must still win the single reservation.
	r.fleet.subjects[first], r.fleet.subjects[second] = r.fleet.subjects[second], r.fleet.subjects[first]
	testing.expect(t,r.fleet.subjects[0].id == higher_id && r.fleet.subjects[1].id == lower_id)
	target := c.Shift_Assignment{building_id="F1",role_id=.worker,slot_index=0}
	for &subject in r.fleet.subjects {
		subject.phase = .Idle
		subject.reservation = target
	}
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).reserved == lower_id)
	testing.expect(t,r.fleet.subjects[0].reservation == nil && r.fleet.subjects[0].phase == .Idle)
	reserved, has_reservation := r.fleet.subjects[1].reservation.?
	testing.expect(t,has_reservation && reserved == target && r.fleet.subjects[1].phase == .Reserved)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == 0,"a reservation never covers a slot")
	// A second derivation keeps the winner and does not double-book.
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).reserved == lower_id)
}

@(test)
only_physically_arrived_eligible_subjects_cover_slots :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	index := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	subject := &r.fleet.subjects[index]
	target := c.Shift_Assignment{building_id="F1",role_id=.worker,slot_index=1}
	staffing_test_claim(&r,index,target)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).occupant == subject.id)

	// Not arrived yet: walking towards the building is not coverage.
	subject.destination = "P1"
	subject.activity = .Moving
	subject.phase = .Working
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).occupant == 0 && subject.assignment == nil)

	// Station stock and inbound subjects are never candidates.
	for activity in ([?]Subject_Activity{.Station,.Onboard}) {
		subject.activity = activity
		subject.destination = ""
		staffing_test_claim(&r,index,target)
		derive_staffing(&r.game,&r.fleet)
		testing.expectf(t,subject.assignment == nil && staffing_slot_snapshot(&r.game,2).occupant == 0,"activity %v",activity)
	}

	// Health, medical state, evacuation, role and phase eligibility.
	subject.activity = .Inside
	subject.destination = "F1"
	cases := [?]struct {
		health: f32,
		medical: c.Medical_Status,
		evacuating: bool,
		roles: []Subject_Role,
		phase: c.Work_Phase,
		expected: bool,
	}{
		{health=0.2,roles=staffing_test_roles[:],phase=.Working},                          // below min_work_health
		{health=1,medical=.Pending_Evacuation,roles=staffing_test_roles[:],phase=.Working}, // medical state
		{health=1,evacuating=true,roles=staffing_test_roles[:],phase=.Working},             // evacuation owns the person
		{health=1,roles=staffing_test_supervisors[:],phase=.Working},                   // role not supported
		{health=1,roles=staffing_test_roles[:],phase=.Resting},                             // not on shift
		{health=1,roles=staffing_test_roles[:],phase=.Extra_Working,expected=true},         // overtime still covers
	}
	for c_case, i in cases {
		subject.health = c_case.health
		subject.medical = c_case.medical
		subject.evacuating = c_case.evacuating
		subject.roles = c_case.roles
		staffing_test_claim(&r,index,target)
		subject.phase = c_case.phase
		derive_staffing(&r.game,&r.fleet)
		if c_case.expected {
			testing.expectf(t,staffing_slot_snapshot(&r.game,2).occupant == subject.id,"case %d",i)
		} else {
			testing.expectf(t,subject.assignment == nil && staffing_slot_snapshot(&r.game,2).occupant == 0,"case %d",i)
		}
	}

	// Disablement releases the claim without changing the requested state.
	subject.roles = staffing_test_roles[:]
	subject.phase = .Working
	subject.health = 1
	staffing_test_claim(&r,index,target)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).occupant == subject.id)
	toggle(&r.game,{id="F1"})
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).occupant == 0 && subject.assignment == nil)
	testing.expect(t,!r.game.active[1])
}

@(test)
reservation_and_occupant_are_independent_and_exclusive :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	worker := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	relief := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	r.fleet.subjects[relief].phase = .Idle
	staffing_test_claim(&r,worker,{building_id="F1",role_id=.worker,slot_index=0})
	derive_staffing(&r.game,&r.fleet)
	// A replacement is reserved for the slot the incumbent still covers: the handoff
	// is scheduled ahead of time and does not disturb current coverage.
	target := c.Shift_Assignment{building_id="F1",role_id=.worker,slot_index=0}
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,relief,target))
	testing.expect(t,r.fleet.subjects[relief].phase == .Reserved)
	coverage := staffing_coverage(&r.game,1,.worker)
	testing.expect(t,coverage.required_slots == 2 && coverage.covered_slots == 1 && coverage.reserved_slots == 1)
	testing.expect(t,!building_staffed(&r.game,1))
	occupied := staffing_slot_snapshot(&r.game,1)
	testing.expect(t,occupied.occupant == r.fleet.subjects[worker].id)
	testing.expect(t,occupied.reserved == r.fleet.subjects[relief].id)
	// Exclusive claims: a second reservation for one slot fails, the incumbent cannot
	// reserve while working, and an already reserved subject cannot claim another slot.
	other := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	r.fleet.subjects[other].phase = .Idle
	testing.expect(t,!reserve_staffing_slot(&r.game,&r.fleet,other,target))
	testing.expect(t,r.fleet.subjects[other].reservation == nil)
	testing.expect(t,!reserve_staffing_slot(&r.game,&r.fleet,worker,{building_id="F1",role_id=.worker,slot_index=1}))
	testing.expect(t,!reserve_staffing_slot(&r.game,&r.fleet,relief,{building_id="F1",role_id=.worker,slot_index=1}))
	// Re-reserving the same target is idempotent.
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,relief,target))
	// A reservation never changes the requested enabled state.
	testing.expect(t,snapshot(&r.game,1).active && r.game.active[1])
	// The physical handoff releases the incumbent and commits the replacement; the
	// scheduler performs both in one tick, so no uncovered tick is observable.
	release_subject_staffing(&r.game,&r.fleet,worker)
	testing.expect(t,assign_staffing_slot(&r.game,&r.fleet,relief,target))
	testing.expect(t,r.fleet.subjects[relief].reservation == nil && r.fleet.subjects[relief].phase == .Working)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == r.fleet.subjects[relief].id)
	coverage = staffing_coverage(&r.game,1,.worker)
	testing.expect(t,coverage.covered_slots == 1 && coverage.reserved_slots == 0 && !building_staffed(&r.game,1))
}

@(test)
reservations_require_colony_residents_and_enabled_buildings :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	target := c.Shift_Assignment{building_id="F1",role_id=.worker,slot_index=0}
	station := staffing_test_person(&r,staffing_test_roles[:],.Station,"")
	onboard := staffing_test_person(&r,staffing_test_roles[:],.Onboard,"")
	boarding := staffing_test_person(&r,staffing_test_roles[:],.Reserved,"")
	testing.expect(t,!reserve_staffing_slot(&r.game,&r.fleet,station,target))
	testing.expect(t,!reserve_staffing_slot(&r.game,&r.fleet,onboard,target))
	testing.expect(t,!reserve_staffing_slot(&r.game,&r.fleet,boarding,target))
	for index in ([?]int{station,onboard,boarding}) {
		testing.expect(t,r.fleet.subjects[index].reservation == nil && r.fleet.subjects[index].phase == .Idle)
	}
	// A disabled building has no slots to fill.
	toggle(&r.game,{id="F1"})
	resident := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	testing.expect(t,!reserve_staffing_slot(&r.game,&r.fleet,resident,target))
	toggle(&r.game,{id="F1"})
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,resident,target))
	testing.expect(t,staffing_slot_snapshot(&r.game,1).reserved == r.fleet.subjects[resident].id)
	// Disablement cancels an existing reservation immediately and releases the person.
	toggle(&r.game,{id="F1"})
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[resident].reservation == nil && r.fleet.subjects[resident].phase == .Idle)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).reserved == 0)
	// Health invalidation cancels it too, including while still resting.
	toggle(&r.game,{id="F1"})
	r.fleet.subjects[resident].phase = .Resting
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,resident,target))
	r.fleet.subjects[resident].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[resident].reservation == nil && r.fleet.subjects[resident].phase == .Resting)
	// Role incompatibility releases a stale reservation on the next derivation.
	r.fleet.subjects[resident].health = 1
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,resident,target))
	r.fleet.subjects[resident].roles = nil
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[resident].reservation == nil)
}

@(test)
released_work_starts_rest_and_released_reservation_returns_idle :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	worker := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	staffing_test_claim(&r,worker,{building_id="F1",role_id=.worker,slot_index=0})
	derive_staffing(&r.game,&r.fleet)
	subject := &r.fleet.subjects[worker]
	testing.expect(t,subject.assignment != nil && subject.work_hours == 0)
	// Health below the work floor releases the assignment in place and starts rest.
	subject.health = 0.1
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,subject.assignment == nil && subject.occupation == "" && subject.phase == .Resting)
	testing.expect(t,subject.work_hours == 0 && subject.rest_hours == 0)
	testing.expect(t,subject.position == r.initial[1].position,"rest starts at the current location")
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == 0 && !building_staffed(&r.game,1))
	// A released reservation returns a rest-complete subject to inactivity.
	reserved := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	r.fleet.subjects[reserved].phase = .Idle
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,reserved,{building_id="F1",role_id=.worker,slot_index=1}))
	release_subject_staffing(&r.game,&r.fleet,reserved)
	testing.expect(t,r.fleet.subjects[reserved].reservation == nil && r.fleet.subjects[reserved].phase == .Idle)
	// A still-resting subject keeps resting when its reservation is cancelled.
	resting := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	r.fleet.subjects[resting].phase = .Resting
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,resting,{building_id="F1",role_id=.worker,slot_index=1}))
	release_subject_staffing(&r.game,&r.fleet,resting)
	testing.expect(t,r.fleet.subjects[resting].phase == .Resting && r.fleet.subjects[resting].reservation == nil)
	// The public release clears a physical claim and the derived coverage together.
	subject.health = 1
	subject.destination = "P1"
	subject.position = r.initial[2].position
	subject.target = subject.position
	staffing_test_claim(&r,worker,{building_id="P1",role_id=.worker,slot_index=0})
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,building_staffed(&r.game,2))
	release_subject_staffing(&r.game,&r.fleet,worker)
	testing.expect(t,r.fleet.subjects[worker].assignment == nil && r.fleet.subjects[worker].phase == .Resting)
	testing.expect(t,!building_staffed(&r.game,2) && staffing_slot_snapshot(&r.game,3).occupant == 0)
}

@(test)
assign_requires_physical_arrival_and_eligibility :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	away := staffing_test_person(&r,staffing_test_roles[:],.Inside,"P1")
	target := c.Shift_Assignment{building_id="F1",role_id=.worker,slot_index=0}
	testing.expect(t,!assign_staffing_slot(&r.game,&r.fleet,away,target))
	testing.expect(t,r.fleet.subjects[away].assignment == nil && staffing_slot_snapshot(&r.game,1).occupant == 0)
	// Walking, station and onboard subjects cannot be assigned physically.
	for activity in ([?]Subject_Activity{.Moving,.Station,.Onboard}) {
		r.fleet.subjects[away].activity = activity
		testing.expectf(t,!assign_staffing_slot(&r.game,&r.fleet,away,target),"activity %v",activity)
	}
	// Arriving at the building with an eligible role commits the slot.
	r.fleet.subjects[away].activity = .Inside
	r.fleet.subjects[away].destination = "F1"
	r.fleet.subjects[away].position = r.initial[1].position
	r.fleet.subjects[away].target = r.fleet.subjects[away].position
	testing.expect(t,assign_staffing_slot(&r.game,&r.fleet,away,target))
	testing.expect(t,r.fleet.subjects[away].assignment != nil && r.fleet.subjects[away].phase == .Working)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == r.fleet.subjects[away].id)
	// An unhealthy subject cannot take or keep a physical slot.
	r.fleet.subjects[away].health = 0.2
	testing.expect(t,!assign_staffing_slot(&r.game,&r.fleet,away,target))
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == 0)
	// The slot's role must be one the subject supports and must exist.
	r.fleet.subjects[away].health = 1
	testing.expect(t,!assign_staffing_slot(&r.game,&r.fleet,away,{building_id="F1",role_id=.repairer,slot_index=0}))
	testing.expect(t,!assign_staffing_slot(&r.game,&r.fleet,away,{building_id="F1",role_id=.worker,slot_index=5}))
}

@(test)
staffing_derivation_never_changes_requested_activity :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	worker := staffing_test_person(&r,staffing_test_roles[:],.Inside,"P1")
	staffing_test_claim(&r,worker,{building_id="P1",role_id=.worker,slot_index=0})
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,snapshot(&r.game,2).active && building_staffed(&r.game,2))
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	testing.expect(t,!snapshot(&r.game,2).active)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,!snapshot(&r.game,2).active && !building_staffed(&r.game,2))
	testing.expect(t,r.fleet.subjects[worker].assignment == nil && r.fleet.subjects[worker].phase == .Resting)
	// Re-enabling does not rebuild staffing by itself: the scheduler refills slots.
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,snapshot(&r.game,2).active && !building_staffed(&r.game,2))
	testing.expect(t,r.fleet.subjects[worker].assignment == nil)
}

@(test)
reset_and_reload_leave_no_stale_staffing_claims :: proc(t: ^testing.T) {
	subjects := [?]Subject_Instance{
		{id="S1",subject_id="human",residence="F1",health=1,initial_assignment={building_id="F1",role_id=.worker},roles=staffing_test_roles[:],speed=1},
		{id="S2",subject_id="human",residence="F1",health=1,initial_assignment={building_id="P1",role_id=.worker},roles=staffing_test_roles[:],speed=1},
	}
	r: Staffing_Test
	staffing_test_init(&r,subjects[:])
	defer staffing_test_destroy(&r)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,building_staffed(&r.game,2))
	// Reset clears derived claims before the subjects are rebuilt; nothing from the
	// previous session can survive into the new one.
	reset(&r.game,r.initial[:])
	testing.expect(t,staffing_slot_count(&r.game) == 4)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == 0 && staffing_slot_snapshot(&r.game,3).occupant == 0)
	testing.expect(t,!building_staffed(&r.game,2))
	reset_transports(&r.fleet,{},r.initial[:],subjects[:])
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,len(r.fleet.subjects) == 2)
	for subject in r.fleet.subjects { testing.expect(t,subject.assignment != nil && subject.phase == .Working) }
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == r.fleet.subjects[0].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,3).occupant == r.fleet.subjects[1].id)
	testing.expect(t,building_staffed(&r.game,2))
	// A second identical reset rebuilds exactly the same slots and coverage.
	reset(&r.game,r.initial[:])
	reset_transports(&r.fleet,{},r.initial[:],subjects[:])
	derive_staffing(&r.game,&r.fleet)
	for want, i in ([?]c.Staffing_Slot_Snapshot{
		{building_id="F1",role_id=.supervisor,slot_index=0},
		{building_id="F1",role_id=.worker,slot_index=0},
		{building_id="F1",role_id=.worker,slot_index=1},
		{building_id="P1",role_id=.worker,slot_index=0},
	}) {
		slot := staffing_slot_snapshot(&r.game,i)
		testing.expect(t,slot.building_id == want.building_id && slot.role_id == want.role_id && slot.slot_index == want.slot_index)
	}
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == r.fleet.subjects[0].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,3).occupant == r.fleet.subjects[1].id)
	coverage := staffing_coverage(&r.game,1,.worker)
	testing.expect(t,coverage.covered_slots == 1 && coverage.required_slots == 2 && coverage.reserved_slots == 0)
}

@(test)
stale_slot_values_and_removed_subjects_release_claims :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	index := staffing_test_person(&r,staffing_test_roles[:],.Inside,"F1")
	subject := &r.fleet.subjects[index]
	// On-demand roles, out-of-range slot indices and buildings without the role never
	// resolve to a materialized slot, for assignments and reservations alike.
	for target in ([?]c.Shift_Assignment{
		{building_id="F1",role_id=.repairer,slot_index=0},
		{building_id="F1",role_id=.worker,slot_index=2},
		{building_id="W1",role_id=.worker,slot_index=0},
	}) {
		subject.assignment = target
		subject.phase = .Working
		derive_staffing(&r.game,&r.fleet)
		testing.expectf(t,subject.assignment == nil && subject.phase == .Resting,"stale assignment %v",target)
		subject.phase = .Idle
		subject.reservation = target
		derive_staffing(&r.game,&r.fleet)
		testing.expectf(t,subject.reservation == nil,"stale reservation %v",target)
	}
	// A removed subject releases its claims and never counts as coverage.
	staffing_test_claim(&r,index,{building_id="F1",role_id=.worker,slot_index=0})
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == subject.id)
	subject.activity = .Removed
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == 0 && subject.assignment == nil)
	testing.expect(t,!building_staffed(&r.game,1))
}

@(test)
reservation_survives_incumbent_incapacity :: proc(t: ^testing.T) {
	r: Staffing_Test
	staffing_test_init(&r)
	defer staffing_test_destroy(&r)
	incumbent := staffing_test_person(&r,staffing_test_roles[:],.Inside,"P1")
	replacement := staffing_test_person(&r,staffing_test_roles[:],.Inside,"P1")
	r.fleet.subjects[replacement].phase = .Idle
	target := c.Shift_Assignment{building_id="P1",role_id=.worker,slot_index=0}
	staffing_test_claim(&r,incumbent,target)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,building_staffed(&r.game,2))
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,replacement,target))
	// The incumbent becomes ineligible: the slot loses coverage but the scheduled
	// replacement keeps its reservation and can still commit on arrival.
	r.fleet.subjects[incumbent].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	slot := staffing_slot_snapshot(&r.game,3)
	testing.expect(t,slot.occupant == 0 && slot.reserved == r.fleet.subjects[replacement].id)
	testing.expect(t,!building_staffed(&r.game,2))
	testing.expect(t,r.fleet.subjects[incumbent].phase == .Resting)
	testing.expect(t,assign_staffing_slot(&r.game,&r.fleet,replacement,target))
	testing.expect(t,building_staffed(&r.game,2))
	testing.expect(t,staffing_slot_snapshot(&r.game,3).occupant == r.fleet.subjects[replacement].id)
}

@(test)
continuous_slot_helpers_count_only_continuous_entries :: proc(t: ^testing.T) {
	definition := Building_Type{subject_roles={
		{role_id=.supervisor,quantity=1,staffing_mode=.continuous},
		{role_id=.worker,quantity=3,staffing_mode=.continuous},
		{role_id=.repairer,quantity=5,staffing_mode=.on_demand},
	}}
	testing.expect(t,continuous_role_quantity(definition,.supervisor) == 1)
	testing.expect(t,continuous_role_quantity(definition,.worker) == 3)
	testing.expect(t,continuous_role_quantity(definition,.repairer) == 0)
	testing.expect(t,continuous_role_quantity(definition,.supervisor) > 0)
	initial := [?]Building_Instance{{id="A",building_id="a"},{id="B",building_id="b"}}
	definitions := [?]Building_Type{{id="a",subject_roles=definition.subject_roles},{id="b"}}
	testing.expect(t,continuous_slot_count(initial[:],definitions[:]) == 4)
	testing.expect(t,continuous_slot_count(nil,definitions[:]) == 0)
	testing.expect(t,continuous_slot_count(initial[:],nil) == 0)
}
