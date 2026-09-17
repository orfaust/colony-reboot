package logic

import "core:testing"
import c "../contracts"

// Headless task-6 scheduler regressions. No renderer, window or GPU resource is
// involved. The scheduler uses no random source, so no seed is required: identical
// inputs and tick sequences produce identical reservations (asserted by the replay
// test). Timers are advanced manually because task 7 owns rest/work progression.
//
// Fixture: three enabled buildings with continuous slots, in slot-table order
// workshop worker, kitchen worker, office supervisor:
//   0 CU   control_unit, no slots
//   1 W1   workshop, position {10,0},  worker
//   2 K1   kitchen,  position {-10,0}, worker
//   3 O1   office,   position {0,10},  supervisor
// With `single_slot` the kitchen and office expose no slot, leaving one slot.

schedule_worker_roles: [1]Subject_Role = {.worker}
schedule_supervisor_roles: [1]Subject_Role = {.supervisor}

Schedule_Test :: struct {
	definitions: [4]Building_Type,
	initial: [4]Building_Instance,
	worker_only: [1]Building_Subject_Role,
	supervisor_only: [1]Building_Subject_Role,
	human_role_definitions: [2]Subject_Role_Definition,
	robot_role_definitions: [1]Subject_Role_Definition,
	types: [2]Subject_Type,
	game: State,
	fleet: Transport_State,
}

schedule_test_init :: proc(r: ^Schedule_Test, single_slot: bool = false) {
	r.worker_only = {{role_id=.worker,quantity=1,staffing_mode=.continuous}}
	r.supervisor_only = {{role_id=.supervisor,quantity=1,staffing_mode=.continuous}}
	r.human_role_definitions = {{role_id=.worker},{role_id=.supervisor}}
	r.robot_role_definitions = {{role_id=.worker}}
	r.types = {
		{id="human",roles=r.human_role_definitions[:],work_time=12,rest_time=12,extra_work_time=4,
			min_work_health=0.4,min_colony_health=0.1,
			health_rates={work_gain_per_hour=0.002,rest_gain_per_hour=0.01,extra_work_loss_per_hour=0.025,
				max_inactivity_loss_per_hour=0.012,inactivity_max_time=72,station_recovery_per_hour=0.04}},
		{id="robot",roles=r.robot_role_definitions[:],work_time=20,rest_time=4,extra_work_time=8,
			min_work_health=0.4,min_colony_health=0.1,
			health_rates={work_gain_per_hour=0.0015,rest_gain_per_hour=0.02,extra_work_loss_per_hour=0.015,
				max_inactivity_loss_per_hour=0.006,inactivity_max_time=120,station_recovery_per_hour=0.06}},
	}
	r.definitions = {
		{id="control_unit",always_on=true},
		{id="workshop",subject_roles=r.worker_only[:]},
		{id="kitchen",subject_roles=r.worker_only[:]},
		{id="office",subject_roles=r.supervisor_only[:]},
	}
	r.initial = {
		{id="CU",building_id="control_unit",position={-50,0},health=1,enable_at_start=true},
		{id="W1",building_id="workshop",position={10,0},health=1,enable_at_start=true},
		{id="K1",building_id="kitchen",position={-10,0},health=1,enable_at_start=true},
		{id="O1",building_id="office",position={0,10},health=1,enable_at_start=true},
	}
	if single_slot {
		r.definitions[2].subject_roles = nil
		r.definitions[3].subject_roles = nil
	}
	r.game = new_session(r.initial[:],r.definitions[:],context.allocator)
	r.fleet = new_transports({},{},nil,r.initial[:],nil,context.allocator,r.definitions[:],r.types[:])
}

schedule_test_destroy :: proc(r: ^Schedule_Test) {
	destroy_transports(&r.fleet,context.allocator)
	destroy(&r.game,context.allocator)
}

// Adds one individual. `subject_id` selects the type's roles unless a test overrides
// them afterwards.
schedule_person :: proc(r: ^Schedule_Test, subject_id: string, position: c.Vector2, phase: c.Work_Phase = .Idle, health: f32 = 1, rest_hours: f64 = 0, work_hours: f64 = 0, activity: Subject_Activity = .Inside) -> int {
	index := add_runtime_subject(&r.fleet,{subject_id=subject_id,activity=activity,position=position,target=position,
		phase=phase,health=health,rest_hours=rest_hours,work_hours=work_hours})
	assert(index >= 0)
	return index
}

// Places a physically arrived incumbent on a slot. The caller derives before the
// scheduler sees it.
schedule_claim :: proc(r: ^Schedule_Test, index: int, building_id: string, role: Subject_Role, slot_index: int = 0) {
	subject := &r.fleet.subjects[index]
	target := c.Shift_Assignment{building_id=building_id,role_id=role,slot_index=slot_index}
	subject.assignment = target
	subject.phase = .Working
	subject.destination = building_id
	for building in r.initial {
		if building.id == building_id { subject.position = building.position; subject.target = building.position; break }
	}
}

// One scheduler tick: reconciliation first (cancelling stale claims), then the
// scheduler, matching the application's fixed-tick order.
schedule_test_tick :: proc(r: ^Schedule_Test, ticks: int = 1) {
	for _ in 0..<ticks {
		derive_staffing(&r.game,&r.fleet)
		schedule_staffing(&r.game,&r.fleet)
	}
}

// Advances the rest/work timers task 7 will own, then runs a scheduler tick.
schedule_test_advance :: proc(r: ^Schedule_Test, ticks: int) {
	for _ in 0..<ticks {
		for &subject in r.fleet.subjects {
			switch subject.phase {
			case .Resting: subject.rest_hours += TICK_HOURS
			case .Working: subject.work_hours += TICK_HOURS
			case .Idle, .Reserved, .Moving_To_Work, .Extra_Working:
			}
		}
		schedule_test_tick(r)
	}
}

@(test)
open_slots_fill_deterministically_and_exclusively :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r)
	defer schedule_test_destroy(&r)
	workshop := schedule_person(&r,"human",{10,0})
	kitchen_a := schedule_person(&r,"human",{-10,0})
	kitchen_b := schedule_person(&r,"human",{-10,0})
	far := schedule_person(&r,"human",{0,100})
	r.fleet.subjects[far].roles = schedule_worker_roles[:]
	schedule_test_tick(&r)
	// Slot order is building/slot-index order; each slot takes its best candidate and
	// a reserved subject is never considered again in the same pass.
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[workshop].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).reserved == r.fleet.subjects[kitchen_a].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).reserved == r.fleet.subjects[kitchen_b].id)
	testing.expect(t,r.fleet.subjects[far].reservation == nil)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == 0,"a reservation never covers a slot")
	// Rest-complete candidates wait health-neutrally in the reserved phase.
	for index in ([?]int{workshop,kitchen_a,kitchen_b}) {
		testing.expect(t,r.fleet.subjects[index].phase == .Reserved)
		_, has := r.fleet.subjects[index].reservation.?
		testing.expect(t,has)
	}
	testing.expect(t,r.fleet.subjects[far].phase == .Idle)
	// Re-running is idempotent.
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[workshop].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).reserved == r.fleet.subjects[kitchen_a].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).reserved == r.fleet.subjects[kitchen_b].id)
}

@(test)
ordering_prefers_soonest_forecast_arrival :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	far := schedule_person(&r,"human",{30,0})
	near := schedule_person(&r,"human",{10,0})
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[near].id)
	testing.expect(t,r.fleet.subjects[far].reservation == nil)
}

@(test)
ordering_prefers_longest_availability :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	schedule_person(&r,"human",{10,0})
	robot := schedule_person(&r,"robot",{10,0})
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[robot].id,
		"equal arrival: the longer nominal shift wins")
}

@(test)
ordering_prefers_distance_then_stable_id :: proc(t: ^testing.T) {
	// Same forecast arrival and availability: the nearer candidate wins.
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	resting := schedule_person(&r,"human",{10,0},.Resting,1,11) // Arrival 1 h, distance 0.
	schedule_person(&r,"human",{12,0})                         // Arrival 1 h, distance 2.
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[resting].id)
	schedule_test_destroy(&r)

	// Identical candidates resolve to the lower stable ID.
	schedule_test_init(&r,true)
	first := schedule_person(&r,"human",{10,0})
	second := schedule_person(&r,"human",{10,0})
	testing.expect(t,r.fleet.subjects[first].id < r.fleet.subjects[second].id)
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[first].id)
}

@(test)
eligibility_filters_role_health_medical_evacuation_and_arrivals :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	wrong_role := schedule_person(&r,"human",{10,0})
	r.fleet.subjects[wrong_role].roles = schedule_supervisor_roles[:]
	unhealthy := schedule_person(&r,"human",{10,0},.Idle,0.2)
	medical := schedule_person(&r,"human",{10,0})
	r.fleet.subjects[medical].medical = .Pending_Evacuation
	evacuating := schedule_person(&r,"human",{10,0})
	r.fleet.subjects[evacuating].evacuating = true
	station := schedule_person(&r,"human",{10,0},.Idle,1,0,0,.Station)
	onboard := schedule_person(&r,"human",{10,0},.Idle,1,0,0,.Onboard)
	boarding := schedule_person(&r,"human",{10,0},.Idle,1,0,0,.Reserved)
	valid := schedule_person(&r,"human",{30,0})
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[valid].id)
	for index in ([?]int{wrong_role,unhealthy,medical,evacuating,station,onboard,boarding}) {
		testing.expectf(t,r.fleet.subjects[index].reservation == nil,"subject %d must stay unassigned",index)
	}
}

@(test)
station_and_inbound_subjects_are_never_candidates :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	// Every rejected individual sits exactly on the workshop and would otherwise be
	// the earliest arrival.
	station := schedule_person(&r,"human",{10,0},.Idle,1,0,0,.Station)
	onboard := schedule_person(&r,"human",{10,0},.Idle,1,0,0,.Onboard)
	boarding := schedule_person(&r,"human",{10,0},.Idle,1,0,0,.Reserved)
	colony := schedule_person(&r,"human",{30,0})
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[colony].id)
	for index in ([?]int{station,onboard,boarding}) {
		testing.expect(t,r.fleet.subjects[index].reservation == nil)
	}
}

@(test)
replacement_is_reserved_in_the_final_part_of_rest :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].work_hours = 10 // Remaining work_time: 2 h.
	too_early := schedule_person(&r,"human",{10,0},.Resting,1,0) // Arrival 12 h.
	resting := schedule_person(&r,"human",{10,0},.Resting,1,10)  // Arrival 2 h.
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == r.fleet.subjects[incumbent].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[resting].id)
	testing.expect(t,r.fleet.subjects[too_early].reservation == nil,"a late forecast is not reserved early")
	// The reservation coexists with rest: recovery continues normally.
	testing.expect(t,r.fleet.subjects[resting].phase == .Resting && r.fleet.subjects[resting].rest_hours == 10)
}

@(test)
replacement_request_waits_until_the_forecast_matches :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].work_hours = 10                  // Remaining 2 h.
	resting := schedule_person(&r,"human",{10,0},.Resting,1,11) // Rest left 1 h, travel 0.
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0,"too early is not reserved")
	// 118 ticks later the candidate is ready but the remaining shift is still longer
	// than the forecast by more than one tick.
	schedule_test_advance(&r,118)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0)
	// The next tick brings the forecast within the just-in-time window.
	schedule_test_advance(&r,1)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[resting].id)
}

@(test)
overtime_requests_the_earliest_candidate_immediately :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].work_hours = 9             // Remaining 3 h.
	late := schedule_person(&r,"human",{10,0},.Resting,1,7) // Arrival 5 h.
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0,"a late candidate is not reserved while on time")
	r.fleet.subjects[incumbent].phase = .Extra_Working
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[late].id)
	// The same fallback applies before the phase transition when work_time is already
	// exhausted, so a scheduler pass can never wait past the deadline.
	release_subject_staffing(&r.game,&r.fleet,late)
	r.fleet.subjects[incumbent].phase = .Working
	r.fleet.subjects[incumbent].work_hours = 12
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[late].id)
}

@(test)
invalid_reservation_is_cancelled_and_replaced_in_the_same_tick :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	first := schedule_person(&r,"human",{10,0})
	second := schedule_person(&r,"human",{10,0})
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[first].id)
	// Health invalidation: derive cancels and the scheduler replaces it immediately.
	r.fleet.subjects[first].health = 0.1
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[second].id)
	testing.expect(t,r.fleet.subjects[first].reservation == nil && r.fleet.subjects[first].phase == .Idle)
	// Disablement cancels the reservation and blocks new ones.
	testing.expect(t,toggle(&r.game,{id="W1"}) == .Applied)
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0 && r.fleet.subjects[second].reservation == nil)
	// Re-enabling lets the scheduler refill the slot.
	testing.expect(t,toggle(&r.game,{id="W1"}) == .Applied)
	r.fleet.subjects[first].health = 1
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[first].id)
	// Role incompatibility cancels a stale reservation and reschedules.
	r.fleet.subjects[first].roles = nil
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[second].id)
}

@(private)
schedule_replay_fixture :: proc(r: ^Schedule_Test) {
	schedule_test_init(r)
	schedule_person(r,"human",{10,0})
	schedule_person(r,"human",{10,0})
	schedule_test_tick(r)
}

@(test)
competing_buildings_share_candidates_and_replay_deterministically :: proc(t: ^testing.T) {
	a: Schedule_Test
	schedule_replay_fixture(&a)
	defer schedule_test_destroy(&a)
	// Two candidates fill the two worker slots; no subject holds two reservations.
	testing.expect(t,staffing_slot_snapshot(&a.game,0).reserved == a.fleet.subjects[0].id)
	testing.expect(t,staffing_slot_snapshot(&a.game,1).reserved == a.fleet.subjects[1].id)
	testing.expect(t,staffing_slot_snapshot(&a.game,2).reserved == 0)
	for subject in a.fleet.subjects {
		count := 0
		if subject.reservation != nil { count += 1 }
		if subject.assignment != nil { count += 1 }
		testing.expect(t,count <= 1)
	}
	// Identical fixture and tick sequence replay exactly, with no random source.
	b: Schedule_Test
	schedule_replay_fixture(&b)
	defer schedule_test_destroy(&b)
	for index in 0..<staffing_slot_count(&a.game) {
		testing.expect(t,staffing_slot_snapshot(&a.game,index) == staffing_slot_snapshot(&b.game,index))
	}
	testing.expect(t,a.game.scheduler == b.game.scheduler)
	for index in 0..<len(a.fleet.subjects) {
		testing.expect(t,a.fleet.subjects[index].id == b.fleet.subjects[index].id)
		testing.expect(t,a.fleet.subjects[index].reservation == b.fleet.subjects[index].reservation)
	}
}

@(test)
flexible_roles_fill_either_slot_but_worker_only_subjects_cannot_supervise :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r)
	defer schedule_test_destroy(&r)
	robot := schedule_person(&r,"robot",{10,0})
	human := schedule_person(&r,"human",{0,10})
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[robot].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).reserved == r.fleet.subjects[human].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).reserved == 0,"the worker-only robot cannot supervise")
}

@(test)
bounded_pass_defers_slots_and_rotates :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r)
	defer schedule_test_destroy(&r)
	candidate := schedule_person(&r,"human",{0,10})
	r.fleet.subjects[candidate].roles = schedule_supervisor_roles[:]
	// One slot per pass: the worker slots cannot use the supervisor and are skipped.
	schedule_staffing(&r.game,&r.fleet,slot_budget=1)
	testing.expect(t,r.game.scheduler.cursor == 1 && r.game.scheduler.deferred == 2)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).reserved == 0)
	schedule_staffing(&r.game,&r.fleet,slot_budget=1)
	testing.expect(t,r.game.scheduler.cursor == 2 && r.game.scheduler.deferred == 4)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).reserved == 0)
	schedule_staffing(&r.game,&r.fleet,slot_budget=1)
	testing.expect(t,r.game.scheduler.cursor == 0 && r.game.scheduler.deferred == 6)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).reserved == r.fleet.subjects[candidate].id)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0 && staffing_slot_snapshot(&r.game,1).reserved == 0)
}

@(test)
evaluation_bound_rotates_the_subject_scan :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	wrong := schedule_person(&r,"human",{10,0})
	r.fleet.subjects[wrong].roles = schedule_supervisor_roles[:]
	unhealthy := schedule_person(&r,"human",{10,0},.Idle,0.2)
	valid := schedule_person(&r,"human",{10,0})
	// One subject evaluation per pass: each pass advances the rotating scan cursor, so
	// later candidates are reached instead of being starved by the first one.
	schedule_staffing(&r.game,&r.fleet,slot_budget=1,evaluation_limit=1)
	testing.expect(t,r.game.scheduler.subject_cursor == 1)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0)
	schedule_staffing(&r.game,&r.fleet,slot_budget=1,evaluation_limit=1)
	testing.expect(t,r.game.scheduler.subject_cursor == 2)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0)
	schedule_staffing(&r.game,&r.fleet,slot_budget=1,evaluation_limit=1)
	testing.expect(t,r.game.scheduler.subject_cursor == 0)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[valid].id)
	testing.expect(t,r.fleet.subjects[wrong].reservation == nil && r.fleet.subjects[unhealthy].reservation == nil)
}

@(test)
no_candidate_keeps_slots_open_and_retries :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == 0)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == 0)
	late := schedule_person(&r,"human",{10,0})
	schedule_test_tick(&r)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).reserved == r.fleet.subjects[late].id)
}
