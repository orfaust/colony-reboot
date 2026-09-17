package logic

import "core:testing"
import c "../contracts"

// Headless task-9 emergency-ship regressions: emergency-only selection, batching,
// two-class landing priority and exact manifest accounting. No renderer, window or
// GPU resource is involved and no test depends on wall-clock time or a random source.
//
// Fixture (building index in brackets):
//   [0] CU  control_unit
//   [1] H   home,             position {4,0}
//   [2] LP  landing_platform, position {0,0}
//   [3] LP2 landing_platform, position {0,4}
//   [4] H2  home2 (6 human places), starts disabled, for ordinary missions
// Ship catalog (stable order): [0] emergency_human, [1] emergency_robot,
// [2] emergency_both, [3] cargo (ordinary transport). Every station ship starts at
// zero units; tests grant the units they need.

emergency_worker_roles: [1]Subject_Role_Definition = {{role_id=.worker}}

Emergency_Test :: struct {
	definitions: [5]Building_Type,
	initial: [5]Building_Instance,
	types: [2]Subject_Type,
	human_cap: [1]Ship_Subject,
	robot_cap: [1]Ship_Subject,
	both_cap: [2]Ship_Subject,
	cargo_cap: [1]Ship_Subject,
	ships: [4]Ship,
	station_ships: [4]Station_Ship,
	station_defs: [2]Station_Subject,
	stock: [2]Station_Subject_Stock,
	instance: Station_Instance,
	game: State,
	fleet: Transport_State,
}

emergency_test_init :: proc(r: ^Emergency_Test, human_stock: f32 = 0, robot_stock: f32 = 0) {
	r.types = {
		{id="human",roles=emergency_worker_roles[:],work_time=12,rest_time=12,extra_work_time=4,
			min_work_health=0.4,min_colony_health=0.1,
			health_rates={work_gain_per_hour=0.002,rest_gain_per_hour=0.01,extra_work_loss_per_hour=0.025,
				max_inactivity_loss_per_hour=0.012,inactivity_max_time=72,station_recovery_per_hour=0.04}},
		{id="robot",roles=emergency_worker_roles[:],work_time=20,rest_time=4,extra_work_time=8,
			min_work_health=0.4,min_colony_health=0.1,
			health_rates={work_gain_per_hour=0.0015,rest_gain_per_hour=0.02,extra_work_loss_per_hour=0.015,
				max_inactivity_loss_per_hour=0.006,inactivity_max_time=120,station_recovery_per_hour=0.06}},
	}
	r.human_cap = {{subject_id="human",capacity=3}}
	r.robot_cap = {{subject_id="robot",capacity=2}}
	r.both_cap = {{subject_id="human",capacity=4},{subject_id="robot",capacity=4}}
	r.cargo_cap = {{subject_id="human",capacity=3}}
	r.ships = {
		{id="emergency_human",type="emergency",max_speed=1000,max_speed_hours=0,units_per_hour=3,subjects=r.human_cap[:]},
		{id="emergency_robot",type="emergency",max_speed=1000,max_speed_hours=0,units_per_hour=3,subjects=r.robot_cap[:]},
		{id="emergency_both",type="emergency",max_speed=1000,max_speed_hours=0,units_per_hour=4,subjects=r.both_cap[:]},
		{id="cargo",type="transport",max_speed=1000,max_speed_hours=0,units_per_hour=1,subjects=r.cargo_cap[:]},
	}
	r.station_ships = {{ship_id="emergency_human"},{ship_id="emergency_robot"},{ship_id="emergency_both"},{ship_id="cargo"}}
	r.station_defs = {{subject_id="human",capacity=32},{subject_id="robot",capacity=32}}
	r.stock = {{subject_id="human",units=human_stock,units_per_hour=0},{subject_id="robot",units=robot_stock,units_per_hour=0}}
	r.instance = {distance=100,subjects=r.stock[:]}
	r.definitions = {
		{id="control_unit",always_on=true},
		{id="home",residents={type="human",capacity=0}},
		{id="landing_platform"},
		{id="landing_platform"},
		{id="home2",residents={type="human",capacity=6}},
	}
	r.initial = {
		{id="CU",building_id="control_unit",position={-50,0},health=1,enable_at_start=true},
		{id="H",building_id="home",position={4,0},health=1,enable_at_start=true},
		{id="LP",building_id="landing_platform",position={0,0},health=1,enable_at_start=true},
		{id="LP2",building_id="landing_platform",position={0,4},health=1,enable_at_start=true},
		{id="H2",building_id="home2",position={12,0},health=1,enable_at_start=false},
	}
	r.game = new_session(r.initial[:],r.definitions[:],context.allocator)
	r.fleet = new_transports({ships=r.station_ships[:],subjects=r.station_defs[:]},r.instance,r.ships[:],r.initial[:],nil,context.allocator,r.definitions[:],r.types[:])
}

emergency_test_destroy :: proc(r: ^Emergency_Test) {
	destroy_transports(&r.fleet,context.allocator)
	destroy(&r.game,context.allocator)
}

emergency_person :: proc(r: ^Emergency_Test, subject_id, residence: string, position: c.Vector2, health: f32 = 1, activity: Subject_Activity = .Inside, phase: c.Work_Phase = .Idle) -> int {
	index := add_runtime_subject(&r.fleet,{subject_id=subject_id,residence=residence,destination=residence,
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

// A requested patient already physically standing on a landing platform.
emergency_patient_at :: proc(r: ^Emergency_Test, subject_id, platform_id: string, residence: string = "H") -> int {
	platform_position: c.Vector2
	for building in r.initial { if building.id == platform_id { platform_position = building.position; break } }
	index := emergency_person(r,subject_id,residence,platform_position,0.05,.Inside)
	subject := &r.fleet.subjects[index]
	subject.medical = .Pending_Evacuation
	subject.evacuation_platform = platform_id
	subject.destination = platform_id
	subject.target = platform_position
	subject.position = platform_position
	return index
}

// Full application-order tick including the medical and transport steps.
emergency_test_tick :: proc(r: ^Emergency_Test, ticks: int = 1) {
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

// Directly built held mission for deterministic landing-order tests.
emergency_test_waiting_mission :: proc(r: ^Emergency_Test, medical: bool, ticket: u64, platform: string) -> int {
	index := r.fleet.count
	r.fleet.missions[index] = Transport{medical=medical,evacuation=medical,pickup_platform_id=platform,landing_ticket=ticket,phase=.Waiting_Landing}
	r.fleet.count += 1
	return index
}

// A ship parked on LP that keeps the pad busy non-preemptively.
emergency_test_busy_mission :: proc(r: ^Emergency_Test) -> int {
	index := r.fleet.count
	r.fleet.missions[index] = Transport{phase=.Unloading,platform_id="LP",phase_duration=100,phase_elapsed=0}
	r.fleet.count += 1
	return index
}

emergency_test_conserved :: proc(t: ^testing.T, r: ^Emergency_Test) {
	alive, station, passengers, residents, patients := 0, 0, 0, 0, 0
	for subject in r.fleet.subjects {
		if subject.activity == .Removed { continue }
		alive += 1
		// Hospitalized and station-held returning patients are identified individuals,
		// not station stock; patients in transit count as passengers below.
		if subject.medical != .None && subject.activity == .Station { patients += 1; continue }
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

@(test)
emergency_dispatch_launches_a_partial_batch_without_waiting_to_fill :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	emergency_patient_at(&r,"human","LP")
	emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1)
	mission := &r.fleet.missions[0]
	testing.expect(t,mission.medical && mission.evacuation,"medical emergency mission")
	testing.expect(t,mission.ship_id == "emergency_human","first compatible emergency ship in catalog order")
	testing.expect(t,mission.units == 2 && len(mission.manifest) == 2,"partial batch launches with two of three seats")
	testing.expect(t,r.fleet.available[0].units == 0)
	for &subject in r.fleet.subjects {
		if subject.medical != .None { testing.expect(t,subject.medical_reserved) }
	}
	emergency_test_conserved(t,&r)
}

@(test)
emergency_dispatch_fills_full_batches_and_splits_the_remainder :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 2
	for _ in 0..<5 { emergency_patient_at(&r,"human","LP") }
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 2,"two emergency legs for five seats")
	first, second := &r.fleet.missions[0], &r.fleet.missions[1]
	testing.expect(t,first.units == 3 && len(first.manifest) == 3)
	testing.expect(t,second.units == 2 && len(second.manifest) == 2)
	// The two manifests partition the five patients exactly once.
	for i in first.manifest { testing.expect(t,i != second.manifest[0] && i != second.manifest[1]) }
	testing.expect(t,r.fleet.available[0].units == 0)
	emergency_test_conserved(t,&r)
}

@(test)
emergency_dispatch_selects_the_first_compatible_ship_in_stable_catalog_order :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	r.fleet.available[1].units = 1
	r.fleet.available[2].units = 1
	human := emergency_patient_at(&r,"human","LP")
	robot := emergency_patient_at(&r,"robot","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 2)
	testing.expect(t,r.fleet.missions[0].ship_id == "emergency_human" && r.fleet.missions[0].subject_id == "human")
	testing.expect(t,r.fleet.missions[1].ship_id == "emergency_robot" && r.fleet.missions[1].subject_id == "robot")
	testing.expect(t,r.fleet.missions[0].manifest[0] == human && r.fleet.missions[1].manifest[0] == robot)
	emergency_test_conserved(t,&r)
}

@(test)
emergency_dispatch_uses_a_ship_compatible_with_both_types :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[2].units = 2
	for _ in 0..<3 { emergency_patient_at(&r,"robot","LP") }
	emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 2,"one human leg and one robot leg on the dual ship")
	human_index, robot_index := -1, -1
	for mission, i in r.fleet.missions[:r.fleet.count] {
		if mission.subject_id == "human" { human_index = i }
		if mission.subject_id == "robot" { robot_index = i }
	}
	testing.expect(t,human_index >= 0 && robot_index >= 0)
	testing.expect(t,r.fleet.missions[human_index].ship_id == "emergency_both" && r.fleet.missions[human_index].units == 1)
	testing.expect(t,r.fleet.missions[robot_index].ship_id == "emergency_both" && r.fleet.missions[robot_index].units == 3)
	testing.expect(t,r.fleet.available[2].units == 0)
	emergency_test_conserved(t,&r)
}

@(test)
emergency_dispatch_leaves_incompatible_patients_pending :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1 // Human-only ship.
	emergency_patient_at(&r,"robot","LP")
	emergency_patient_at(&r,"robot","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 0,"no compatible emergency ship")
	testing.expect(t,r.fleet.available[0].units == 1,"the incompatible unit stays available")
	for &subject in r.fleet.subjects {
		if subject.medical != .None { testing.expect(t,!subject.medical_reserved) }
	}
	emergency_test_conserved(t,&r)
}

@(test)
emergency_dispatch_requires_an_available_unit :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	// The catalog contains compatible ships but no station unit is available.
	emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 0)
	for &subject in r.fleet.subjects {
		if subject.medical != .None { testing.expect(t,!subject.medical_reserved) }
	}
	emergency_test_conserved(t,&r)
}

@(test)
emergency_dispatch_respects_transport_limit_without_dropping_patients :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	r.fleet.count = TRANSPORT_LIMIT
	for &mission in r.fleet.missions { mission = {}; mission.phase = .Completed }
	emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == TRANSPORT_LIMIT,"the bounded mission log is full")
	testing.expect(t,r.fleet.available[0].units == 1)
	for &subject in r.fleet.subjects {
		if subject.medical != .None { testing.expect(t,!subject.medical_reserved) }
	}
	emergency_test_conserved(t,&r)
}

@(test)
emergency_missions_preserve_fifo_and_land_before_ordinary_waiters :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	// An ordinary waiter arrived first (lower ticket), then an emergency mission.
	ordinary := emergency_test_waiting_mission(&r,false,1,"")
	emergency := emergency_test_waiting_mission(&r,true,2,"LP")
	step_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.missions[emergency].phase == .Landing,"emergency outranks an earlier ordinary waiter")
	testing.expect(t,r.fleet.missions[ordinary].phase == .Waiting_Landing)
}

@(test)
emergency_missions_preserve_fifo_within_the_class :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	first := emergency_test_waiting_mission(&r,true,1,"LP")
	second := emergency_test_waiting_mission(&r,true,2,"LP")
	step_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.missions[first].phase == .Landing)
	testing.expect(t,r.fleet.missions[second].phase == .Waiting_Landing)
}

@(test)
occupied_platform_is_not_preempted_by_an_emergency_mission :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	busy := emergency_test_busy_mission(&r)
	emergency := emergency_test_waiting_mission(&r,true,1,"LP")
	step_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.missions[busy].phase == .Unloading,"the ship already using the pad finishes")
	testing.expect(t,r.fleet.missions[emergency].phase == .Waiting_Landing)
	r.fleet.missions[busy].phase = .Completed
	step_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.missions[emergency].phase == .Landing)
}

@(test)
emergency_landing_class_rule_is_two_classes_and_fifo :: proc(t: ^testing.T) {
	testing.expect(t,transport_lands_ahead(Transport{medical=true,landing_ticket=9},Transport{medical=false,landing_ticket=1}))
	testing.expect(t,!transport_lands_ahead(Transport{medical=false,landing_ticket=1},Transport{medical=true,landing_ticket=9}))
	testing.expect(t,transport_lands_ahead(Transport{landing_ticket=1},Transport{landing_ticket=2}))
	testing.expect(t,!transport_lands_ahead(Transport{landing_ticket=2},Transport{landing_ticket=1}))
}

@(test)
medical_patients_reach_the_station_as_identified_individuals :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	first := emergency_patient_at(&r,"human","LP")
	second := emergency_patient_at(&r,"human","LP")
	emergency_test_tick(&r,600)
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].phase == .Completed,"the emergency leg completes")
	testing.expect(t,r.fleet.missions[0].loaded == 2 && r.fleet.missions[0].returned == 2 && r.fleet.missions[0].delivered == 0)
	testing.expect(t,r.fleet.available[0].units == 1,"the ship is released after discharge")
	testing.expect(t,r.fleet.occupants[1] == 0,"boarding removed them from the colony residence")
	testing.expect(t,r.fleet.stock[0].units == 0,"patients are not anonymous station stock")
	for index in ([?]int{first,second}) {
		subject := &r.fleet.subjects[index]
		testing.expect(t,subject.activity == .Station && subject.medical == .Hospitalized)
		testing.expect(t,!subject.medical_reserved && subject.evacuation_platform == "" && subject.residence == "")
	}
	emergency_test_conserved(t,&r)
}

@(test)
medical_patient_death_onboard_an_emergency_mission_keeps_manifests_exact :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	emergency_patient_at(&r,"human","LP")
	emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].units == 2)
	// Stop the moment both patients have boarded so the death happens in flight.
	for _ in 0..<300 {
		emergency_test_tick(&r,1)
		if r.fleet.missions[0].loaded == 2 { break }
	}
	testing.expect(t,r.fleet.missions[0].loaded == 2 && r.fleet.missions[0].phase != .Completed)
	dead := r.fleet.missions[0].manifest[0]
	dead_id := r.fleet.subjects[dead].id
	r.fleet.subjects[dead].health = 0
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[dead].activity == .Removed)
	mission := &r.fleet.missions[0]
	testing.expect(t,mission.units == 1 && mission.loaded == 1 && len(mission.manifest) == 1)
	emergency_test_tick(&r,200)
	testing.expect(t,r.fleet.missions[0].phase == .Completed)
	survivor := r.fleet.missions[0].manifest[0]
	testing.expect(t,r.fleet.subjects[survivor].medical == .Hospitalized)
	for subject in r.fleet.subjects { if subject.id == dead_id { testing.expect(t,subject.activity == .Removed) } }
	emergency_test_conserved(t,&r)
}

@(test)
medical_death_while_reserved_on_an_emergency_mission_releases_the_seat :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	first := emergency_patient_at(&r,"human","LP")
	second := emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].units == 2 && r.fleet.missions[0].loaded == 0)
	testing.expect(t,r.fleet.subjects[second].medical_reserved)
	// The first patient dies while still holding a seat on the outbound leg.
	r.fleet.subjects[first].health = 0
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[first].activity == .Removed)
	mission := &r.fleet.missions[0]
	testing.expect(t,mission.units == 1 && len(mission.manifest) == 1 && mission.manifest[0] == second,"the dead seat is detached exactly once")
	testing.expect(t,r.fleet.occupants[1] == 1)
	testing.expect(t,r.fleet.subjects[second].medical_reserved)
	emergency_test_conserved(t,&r)
	emergency_test_tick(&r,600)
	testing.expect(t,r.fleet.missions[0].phase == .Completed)
	testing.expect(t,r.fleet.subjects[second].medical == .Hospitalized)
	testing.expect(t,r.fleet.occupants[1] == 0)
	emergency_test_conserved(t,&r)
}

@(test)
medical_mission_retargets_to_another_active_platform :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	patient := emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].pickup_platform_id == "LP")
	r.game.active[2] = false // LP goes away; LP2 stays active.
	emergency_test_tick(&r,8)
	testing.expect(t,r.fleet.missions[0].pickup_platform_id == "LP2","the held leg re-targets to an active pad")
	testing.expect(t,r.fleet.subjects[patient].evacuation_platform == "LP2" && r.fleet.subjects[patient].destination == "LP2")
	emergency_test_tick(&r,600)
	testing.expect(t,r.fleet.missions[0].phase == .Completed)
	testing.expect(t,r.fleet.subjects[patient].medical == .Hospitalized)
	testing.expect(t,r.fleet.available[0].units == 1)
	emergency_test_conserved(t,&r)
}

@(test)
medical_mission_cancels_cleanly_when_no_platform_remains :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	patient := emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].phase == .Outbound)
	r.game.active[2] = false
	r.game.active[3] = false
	emergency_test_tick(&r,20)
	testing.expect(t,r.fleet.missions[0].phase == .Cancelled,"a held leg with nowhere to land is cancelled")
	testing.expect(t,r.fleet.available[0].units == 1,"the ship is released")
	testing.expect(t,r.fleet.subjects[patient].medical == .Pending_Evacuation)
	testing.expect(t,!r.fleet.subjects[patient].medical_reserved,"the seat is released for a later retry")
	emergency_test_conserved(t,&r)
}

@(test)
emergency_dispatch_never_uses_ordinary_transport_ships :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[3].units = 2 // Only the ordinary cargo ship is available.
	emergency_patient_at(&r,"human","LP")
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 0,"ordinary transports never carry medical patients")
	testing.expect(t,r.fleet.available[3].units == 2)
	emergency_test_conserved(t,&r)
}
