package logic

import "core:testing"
import c "../contracts"

// Headless task-8 medical regressions: threshold crossing, one-time requests,
// release/replacement, platform movement, permanent death removal and population
// conservation. No renderer, window or GPU resource is involved and no test depends
// on wall-clock time or a random source.
//
// Fixture (building index in brackets):
//   [0] CU  control_unit
//   [1] H   home,               position {4,0},  active
//   [2] LP  landing_platform,   position {0,0},  active
//   [3] W1  workshop,           position {8,0},  one continuous worker slot
//   [4] H2  home2,              position {12,0}, 4 resident slots, starts disabled
// A creative shuttle and a station let the tests exercise transport manifest
// accounting; `stock_units` seeds station stock.

medical_roles: [1]Subject_Role_Definition = {{role_id=.worker}}

Medical_Test :: struct {
	definitions: [5]Building_Type,
	initial: [5]Building_Instance,
	types: [1]Subject_Type,
	passengers: [1]Ship_Subject,
	ships: [1]Ship,
	station_ships: [1]Station_Ship,
	station_defs: [1]Station_Subject,
	stock: [1]Station_Subject_Stock,
	instance: Station_Instance,
	game: State,
	fleet: Transport_State,
}

medical_test_init :: proc(r: ^Medical_Test, stock_units: f32 = 0) {
	r.types = {{id="human",roles=medical_roles[:],work_time=12,rest_time=12,extra_work_time=4,
		min_work_health=0.4,min_colony_health=0.1,
		health_rates={work_gain_per_hour=0.002,rest_gain_per_hour=0.01,extra_work_loss_per_hour=0.025,
			max_inactivity_loss_per_hour=0.012,inactivity_max_time=72,station_recovery_per_hour=0.04}}}
	r.definitions = {
		{id="control_unit",always_on=true},
		{id="home",residents={type="human",capacity=0}},
		{id="landing_platform"},
		{id="workshop",subject_roles={{role_id=.worker,quantity=1,staffing_mode=.continuous}}},
		{id="home2",residents={type="human",capacity=4}},
	}
	r.initial = {
		{id="CU",building_id="control_unit",position={-50,0},health=1,enable_at_start=true},
		{id="H",building_id="home",position={4,0},health=1,enable_at_start=true},
		{id="LP",building_id="landing_platform",position={0,0},health=1,enable_at_start=true},
		{id="W1",building_id="workshop",position={8,0},health=1,enable_at_start=true},
		{id="H2",building_id="home2",position={12,0},health=1,enable_at_start=false},
	}
	r.passengers = {{subject_id="human",capacity=8}}
	r.ships = {{id="shuttle",type="transport",max_speed=3600,max_speed_hours=1,units_per_hour=4,subjects=r.passengers[:]}}
	r.station_ships = {{ship_id="shuttle",units=1}}
	r.station_defs = {{subject_id="human",capacity=16}}
	r.stock = {{subject_id="human",units=stock_units,units_per_hour=0}}
	r.instance = {distance=100,subjects=r.stock[:]}
	r.game = new_session(r.initial[:],r.definitions[:],context.allocator)
	r.fleet = new_transports({ships=r.station_ships[:],subjects=r.station_defs[:]},r.instance,r.ships[:],r.initial[:],nil,context.allocator,r.definitions[:],r.types[:])
}

medical_test_destroy :: proc(r: ^Medical_Test) {
	destroy_transports(&r.fleet,context.allocator)
	destroy(&r.game,context.allocator)
}

// Adds one colony resident and keeps the authoritative occupant count in step, so
// population conservation is meaningful.
medical_person :: proc(r: ^Medical_Test, residence: string, position: c.Vector2, health: f32 = 1, activity: Subject_Activity = .Inside, phase: c.Work_Phase = .Idle) -> int {
	index := add_runtime_subject(&r.fleet,{subject_id="human",residence=residence,destination=residence,
		position=position,target=position,health=health,activity=activity,phase=phase})
	assert(index >= 0)
	if activity == .Inside || activity == .Moving || activity == .Waiting {
		for &building, i in r.game.buildings {
			if building.id != residence { continue }
			r.fleet.occupants[i] += 1
			building.residents_amount = r.fleet.occupants[i]
			break
		}
	}
	return index
}

// Full application-order tick: health, medical, lifecycle, movement, handoff,
// coverage, scheduling. Mirrors the frame loop in src/app/main.odin.
medical_tick :: proc(r: ^Medical_Test, ticks: int = 1) {
	for _ in 0..<ticks {
		step(&r.game)
		step_subject_health(&r.fleet)
		step_medical(&r.game,&r.fleet)
		step_shifts(&r.game,&r.fleet)
		step_transports(&r.fleet,&r.game,r.definitions[:])
		commit_shift_handoffs(&r.game,&r.fleet)
		derive_staffing(&r.game,&r.fleet)
		schedule_staffing(&r.game,&r.fleet)
	}
}

// Population conservation: every live individual is counted exactly once as station
// stock, in-flight passenger or colony resident, and mission manifests stay
// internally consistent.
medical_test_conserved :: proc(t: ^testing.T, r: ^Medical_Test) {
	alive, station, passengers, residents, patients := 0, 0, 0, 0, 0
	for subject in r.fleet.subjects {
		if subject.activity == .Removed { continue }
		alive += 1
		// Hospitalized patients are identified individuals, not station stock.
		if subject.medical == .Hospitalized { patients += 1; continue }
		switch subject.activity {
		case .Station: station += 1
		case .Reserved, .Onboard: passengers += 1
		case .Inside, .Moving, .Waiting: residents += 1
		case .Removed:
		}
	}
	stock_sum, occupant_sum: f32
	for stock in r.fleet.stock { stock_sum += stock.units }
	for occupant in r.fleet.occupants { occupant_sum += occupant }
	testing.expectf(t,f32(alive) == stock_sum+occupant_sum+f32(passengers)+f32(patients),
		"alive %d != stock %.0f + residents %.0f + passengers %d + patients %d",alive,stock_sum,occupant_sum,passengers,patients)
	testing.expect(t,f32(station) == stock_sum)
	testing.expect(t,f32(residents) == occupant_sum)
	for mission in r.fleet.missions[:r.fleet.count] {
		testing.expect(t,mission.loaded <= f32(len(mission.manifest)))
		testing.expect(t,mission.delivered+mission.returned <= mission.loaded)
	}
}

medical_event_count :: proc(r: ^Medical_Test, kind: c.Sim_Event_Kind) -> int {
	count := 0
	for event in pending_events(&r.game.events) { if event.kind == kind { count += 1 } }
	return count
}

@(test)
medical_threshold_equality_requests_once_and_repeated_ticks_are_idempotent :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	above := medical_person(&r,"H",{4,0},0.11)
	at := medical_person(&r,"H",{4,0},0.1)
	at_id := r.fleet.subjects[at].id
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[above].medical == .None,"health above the threshold is not a crossing")
	testing.expect(t,r.fleet.subjects[at].medical == .Pending_Evacuation,"threshold equality requests evacuation")
	events := pending_events(&r.game.events)
	testing.expect(t,len(events) == 1 && events[0].kind == .Medical_Evacuation && events[0].subject_id == at_id)
	// Repeated ticks never duplicate the request or the event.
	medical_tick(&r,120)
	testing.expect(t,r.fleet.subjects[at].medical == .Pending_Evacuation)
	testing.expect(t,medical_event_count(&r,.Medical_Evacuation) == 1)
	medical_test_conserved(t,&r)
}

@(test)
medical_releases_slot_and_reservation_and_triggers_replacement :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	worker := medical_person(&r,"H",{8,0},0.5,.Inside,.Working)
	worker_id := r.fleet.subjects[worker].id
	r.fleet.subjects[worker].assignment = c.Shift_Assignment{building_id="W1",role_id=.worker,slot_index=0}
	r.fleet.subjects[worker].destination = "W1"
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == worker_id)
	relief := medical_person(&r,"H",{4,0},1)
	r.fleet.subjects[worker].health = 0.09
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[worker].medical == .Pending_Evacuation)
	testing.expect(t,r.fleet.subjects[worker].assignment == nil && r.fleet.subjects[worker].reservation == nil)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == 0,"the sick worker no longer covers the slot")
	_, reserved := r.fleet.subjects[relief].reservation.?
	testing.expect(t,reserved,"the scheduler immediately requests a replacement")
	medical_test_conserved(t,&r)
}

@(test)
medical_walks_to_platform_and_queues_multiple_patients :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	first := medical_person(&r,"H",{4,0},0.1)
	second := medical_person(&r,"H",{4,0},0.05)
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[first].destination == "LP" && r.fleet.subjects[second].destination == "LP")
	testing.expect(t,r.fleet.subjects[first].evacuation_platform == "LP" && r.fleet.subjects[second].evacuation_platform == "LP")
	testing.expect(t,r.fleet.subjects[second].wait_hours > 0,"the second patient queues behind the first")
	testing.expect(t,r.fleet.subjects[first].wait_hours == 0)
	medical_tick(&r,240)
	for index in ([?]int{first,second}) {
		subject := &r.fleet.subjects[index]
		testing.expect(t,subject.activity == .Inside,"patient reached the platform")
		testing.expect(t,subject.position == r.initial[2].position)
		testing.expect(t,subject.destination == "LP" && subject.evacuation_platform == "LP")
	}
	medical_test_conserved(t,&r)
}

@(test)
medical_without_active_platform_waits_then_moves :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	r.game.active[2] = false
	patient := medical_person(&r,"H",{4,0},0.1)
	medical_tick(&r,30)
	testing.expect(t,r.fleet.subjects[patient].medical == .Pending_Evacuation)
	testing.expect(t,r.fleet.subjects[patient].evacuation_platform == "","no platform anchor while none is active")
	testing.expect(t,r.fleet.subjects[patient].activity == .Inside && r.fleet.subjects[patient].destination == "H")
	testing.expect(t,medical_event_count(&r,.Medical_Evacuation) == 1)
	r.game.active[2] = true
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[patient].evacuation_platform == "LP" && r.fleet.subjects[patient].destination == "LP")
	medical_tick(&r,240)
	testing.expect(t,r.fleet.subjects[patient].activity == .Inside && r.fleet.subjects[patient].position == r.initial[2].position)
	medical_test_conserved(t,&r)
}

@(test)
medical_death_before_pickup_removes_and_conserves_population :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	patient := medical_person(&r,"H",{4,0},0.1)
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[patient].medical == .Pending_Evacuation)
	r.fleet.subjects[patient].health = 0
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[patient].activity == .Removed)
	testing.expect(t,r.fleet.occupants[1] == 0)
	events := pending_events(&r.game.events)
	testing.expect(t,len(events) == 2 && events[0].kind == .Medical_Evacuation && events[1].kind == .Subject_Died)
	testing.expect(t,medical_event_count(&r,.Subject_Died) == 1)
	medical_test_conserved(t,&r)
}

@(test)
medical_death_while_walking_to_platform :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	patient := medical_person(&r,"H",{4,0},0.1)
	medical_tick(&r,30)
	testing.expect(t,r.fleet.subjects[patient].activity == .Moving,"the patient is in transit")
	r.fleet.subjects[patient].health = 0
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[patient].activity == .Removed)
	testing.expect(t,r.fleet.occupants[1] == 0)
	testing.expect(t,medical_event_count(&r,.Subject_Died) == 1)
	medical_test_conserved(t,&r)
}

@(test)
medical_death_while_reserved_on_transport_manifest :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r,4)
	defer medical_test_destroy(&r)
	toggle(&r.game,{id="H2"})
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	approve_transport(&r.fleet,r.fleet.missions[0].id)
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].phase == .Loading)
	testing.expect(t,r.fleet.missions[0].units == 4 && len(r.fleet.missions[0].manifest) == 4)
	testing.expect(t,r.fleet.missions[0].requested == 4 && r.fleet.reserved[4] == 4)
	dead := r.fleet.missions[0].manifest[0]
	dead_id := r.fleet.subjects[dead].id
	testing.expect(t,r.fleet.subjects[dead].activity == .Reserved)
	r.fleet.subjects[dead].health = 0
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[dead].activity == .Removed)
	mission := &r.fleet.missions[0]
	testing.expect(t,mission.units == 3 && len(mission.manifest) == 3,"manifest shrinks exactly once")
	testing.expect(t,mission.loaded == 0 && mission.requested == 3)
	testing.expect(t,r.fleet.reserved[4] == 3 && r.fleet.stock[0].units == 0)
	testing.expect(t,medical_event_count(&r,.Subject_Died) == 1)
	medical_test_conserved(t,&r)
	// The surviving three complete the trip; the dead person never arrives twice.
	medical_tick(&r,600)
	testing.expect(t,r.fleet.occupants[4] == 3)
	testing.expect(t,r.fleet.stock[0].units == 0)
	for subject in r.fleet.subjects { if subject.id == dead_id { testing.expect(t,subject.activity == .Removed) } }
	medical_test_conserved(t,&r)
}

@(test)
medical_death_while_onboard_transport_manifest :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r,4)
	defer medical_test_destroy(&r)
	toggle(&r.game,{id="H2"})
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	approve_transport(&r.fleet,r.fleet.missions[0].id)
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].units == 4)
	medical_tick(&r,60) // One loading hour at four units per hour.
	testing.expect(t,r.fleet.missions[0].phase == .Outbound && r.fleet.missions[0].loaded == 4)
	dead := r.fleet.missions[0].manifest[1]
	testing.expect(t,r.fleet.subjects[dead].activity == .Onboard)
	r.fleet.subjects[dead].health = 0
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[dead].activity == .Removed)
	mission := &r.fleet.missions[0]
	testing.expect(t,mission.units == 3 && mission.loaded == 3 && len(mission.manifest) == 3)
	testing.expect(t,mission.requested == 3 && r.fleet.reserved[4] == 3)
	testing.expect(t,medical_event_count(&r,.Subject_Died) == 1)
	medical_test_conserved(t,&r)
	medical_tick(&r,600)
	testing.expect(t,r.fleet.occupants[4] == 3 && r.fleet.stock[0].units == 0)
	medical_test_conserved(t,&r)
}

@(test)
medical_death_on_station_stock_reduces_population_once :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r,3)
	defer medical_test_destroy(&r)
	index := -1
	for &subject, i in r.fleet.subjects { if subject.activity == .Station { index = i; break } }
	testing.expect(t,index >= 0)
	r.fleet.subjects[index].health = 0
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[index].activity == .Removed)
	testing.expect(t,r.fleet.stock[0].units == 2)
	testing.expect(t,medical_event_count(&r,.Subject_Died) == 1)
	testing.expect(t,medical_event_count(&r,.Medical_Evacuation) == 0,"station stock never requests a colony evacuation")
	medical_test_conserved(t,&r)
}

@(test)
medical_takes_over_a_reserved_residence_evacuation_seat :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	evacuee := medical_person(&r,"H",{4,0},1)
	id := r.fleet.subjects[evacuee].id
	// Deactivate the residence and let its committed evacuation dispatch.
	toggle(&r.game,{id="H"})
	r.game.level[1] = 0
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.subjects[evacuee].evacuating && r.fleet.subjects[evacuee].evacuation_reserved)
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].evacuation && r.fleet.missions[0].units == 1)
	// The evacuee crosses the medical threshold: the medical path takes over and the
	// ordinary seat is released without losing the person.
	r.fleet.subjects[evacuee].health = 0.05
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[evacuee].medical == .Pending_Evacuation)
	testing.expect(t,!r.fleet.subjects[evacuee].evacuating && !r.fleet.subjects[evacuee].evacuation_reserved)
	testing.expect(t,r.fleet.missions[0].units == 0 && len(r.fleet.missions[0].manifest) == 0)
	testing.expect(t,r.fleet.occupants[1] == 1)
	testing.expect(t,medical_event_count(&r,.Medical_Evacuation) == 1)
	testing.expect(t,medical_event_count(&r,.Subject_Died) == 0)
	medical_test_conserved(t,&r)
}

@(test)
medical_death_is_removed_before_requests_in_tick_order :: proc(t: ^testing.T) {
	r: Medical_Test
	medical_test_init(&r)
	defer medical_test_destroy(&r)
	dying := medical_person(&r,"H",{4,0},0.05)
	dead := medical_person(&r,"H2",{12,0},0)
	medical_tick(&r,1)
	testing.expect(t,r.fleet.subjects[dead].activity == .Removed)
	testing.expect(t,r.fleet.subjects[dying].medical == .Pending_Evacuation)
	events := pending_events(&r.game.events)
	testing.expect(t,len(events) == 2)
	testing.expect(t,events[0].kind == .Subject_Died && events[0].subject_id == r.fleet.subjects[dead].id)
	testing.expect(t,events[1].kind == .Medical_Evacuation && events[1].subject_id == r.fleet.subjects[dying].id)
	testing.expect(t,r.fleet.occupants[4] == 0)
	medical_test_conserved(t,&r)
}
