package main

import "../logic"
import c "../contracts"

// Task-13 headless gameplay integration smoke.
//
// A deterministic multi-day colony is built from the shipped tuning values (human
// 12h work / 12h rest / 4h overtime; robot 20h / 4h / 8h; shipped health, need and
// station-recovery rates) and stepped through exactly the fixed-tick order used by
// `run_level` in main.odin. No window, GPU, asset or random source is involved.
//
// The scenario exercises: continuous shift rotation with an on-time handoff, a late
// replacement that forces overtime and leaves the generator unstaffed (staffing-based
// power suspension while enabled), simultaneous need shortages, a medical evacuation
// that boards and flies to the station, automatic station recovery, an emergency
// return and discharge at the original residence, and a second patient that dies
// while waiting to board. A focused episode at the end verifies the non-preemptive
// two-class landing priority (medical before ordinary).
//
// Observed values are balance outcomes of this run, not final tuning.

GAMEPLAY_SMOKE_HOURS :: 72
// Fixed arrays sized above the scenario population so per-subject phase/claim tracking
// stays allocation-free. Subject IDs start at 1 and never exceed the live count.
SMOKE_TRACK :: 32

Gameplay_Smoke_Report :: struct {
	hours: int,
	ticks: int,
	population_start: int,
	population_end: int,
	deaths: int,
	population_conserved: bool,
	shift_handoffs: int,
	overtime_entries: int,
	staffing_lost: int,
	staffing_restored: int,
	generator_unstaffed_hours: f64,
	power_gated_ticks: int,
	min_available_kw: f64,
	power_shed: int,
	simultaneous_shortage_ticks: int,
	shortage_health_start: f32,
	shortage_health_min: f32,
	medical_evacuations: int,
	medical_returns: int,
	patient_hospitalized: bool,
	patient_returned_home: bool,
	death_while_waiting: bool,
	priority_medical_landed_first: bool,
}

smoke_building_index :: proc(game: ^logic.State, id: string) -> int {
	for building, i in game.buildings { if building.id == id { return i } }
	return -1
}

smoke_subject_index :: proc(fleet: ^logic.Transport_State, source_id: string) -> int {
	for &subject, i in fleet.subjects {
		if subject.source_id == source_id && subject.activity != .Removed { return i }
	}
	return -1
}

smoke_live_population :: proc(fleet: ^logic.Transport_State) -> int {
	count := 0
	for &subject in fleet.subjects { if subject.activity != .Removed { count += 1 } }
	return count
}

// Runs the scenario and reports the observed outcomes. `ok` is the conjunction of the
// integration invariants the scenario must demonstrate.
run_gameplay_smoke :: proc() -> (report: Gameplay_Smoke_Report, ok: bool) {
	// ---- Shipped-tuning catalog fixture (no JSON, no renderer) ----
	human_roles := [?]logic.Subject_Role_Definition{{role_id=.worker},{role_id=.supervisor}}
	human_needs := [?]logic.Subject_Need{
		{resource_id="water",amount_per_hour=0.5,shortage_alert_time=6,shortage_max_time=72,satisfied_health_gain_per_hour=0.001,max_shortage_health_loss_per_hour=0.025},
		{resource_id="meals",amount_per_hour=0.2,shortage_alert_time=24,shortage_max_time=400,satisfied_health_gain_per_hour=0.002,max_shortage_health_loss_per_hour=0.012},
	}
	robot_roles := [?]logic.Subject_Role_Definition{{role_id=.worker},{role_id=.repairer}}
	robot_needs := [?]logic.Subject_Need{
		{resource_id="batteries",amount_per_hour=0.3,shortage_alert_time=8,shortage_max_time=72,satisfied_health_gain_per_hour=0.0015,max_shortage_health_loss_per_hour=0.020},
	}
	subject_types := [?]logic.Subject_Type{
		{id="human",name_key="subject_human_name",width=1,height=1,work_time=12,rest_time=12,extra_work_time=4,
			min_work_health=0.4,min_colony_health=0.1,
			health_rates={work_gain_per_hour=0.002,rest_gain_per_hour=0.01,extra_work_loss_per_hour=0.025,max_inactivity_loss_per_hour=0.012,inactivity_max_time=72,station_recovery_per_hour=0.04},
			roles=human_roles[:],needs=human_needs[:]},
		{id="robot",name_key="subject_robot_name",width=1,height=1,work_time=20,rest_time=4,extra_work_time=8,
			min_work_health=0.4,min_colony_health=0.1,
			health_rates={work_gain_per_hour=0.0015,rest_gain_per_hour=0.02,extra_work_loss_per_hour=0.015,max_inactivity_loss_per_hour=0.006,inactivity_max_time=120,station_recovery_per_hour=0.06},
			roles=robot_roles[:],needs=robot_needs[:]},
	}
	generator_roles := [?]logic.Building_Subject_Role{{role_id=.worker,quantity=1,staffing_mode=.continuous}}
	workshop_roles := [?]logic.Building_Subject_Role{{role_id=.worker,quantity=1,staffing_mode=.continuous}}
	// Homes stock the needs of the subjects they host; the shelter is deliberately
	// left empty so one resident can show a real, stock-driven shortage episode.
	human_home_storage := [?]logic.Storage{{resource_id="water",capacity=10000},{resource_id="meals",capacity=10000}}
	robot_home_storage := [?]logic.Storage{{resource_id="batteries",capacity=10000}}
	shelter_storage := [?]logic.Storage{{resource_id="water",capacity=100},{resource_id="meals",capacity=100}}
	human_home_stored := [?]logic.Stored_Resource{{resource_id="water",amount=10000},{resource_id="meals",amount=10000}}
	robot_home_stored := [?]logic.Stored_Resource{{resource_id="batteries",amount=10000}}
	shelter_stored := [?]logic.Stored_Resource{{resource_id="water",amount=0},{resource_id="meals",amount=0}}
	definitions := [?]logic.Building_Type{
		{id="control_unit",always_on=true},
		{id="solar",power_output_kw=20},
		{id="generator",power_output_kw=30,subject_roles=generator_roles[:]},
		{id="workshop",power_need_kw=5,subject_roles=workshop_roles[:]},
		{id="human_home",residents={type="human",capacity=8},storage=human_home_storage[:]},
		{id="robot_home",residents={type="robot",capacity=3},storage=robot_home_storage[:]},
		{id="shelter",storage=shelter_storage[:]},
		{id="landing_platform"},
	}
	initial := [?]logic.Building_Instance{
		{id="CU",building_id="control_unit",position={100,100},health=1,enable_at_start=true},
		{id="SP",building_id="solar",position={90,100},health=1,enable_at_start=true},
		{id="GEN",building_id="generator",position={30,0},health=1,enable_at_start=true},
		{id="WS",building_id="workshop",position={0,8},health=1,enable_at_start=true},
		{id="HH",building_id="human_home",position={0,0},health=1,enable_at_start=true,residents_amount=f32(5),stored=human_home_stored[:]},
		{id="RH",building_id="robot_home",position={0,10},health=1,enable_at_start=true,residents_amount=f32(2),stored=robot_home_stored[:]},
		{id="SH",building_id="shelter",position={-6,0},health=1,enable_at_start=true,stored=shelter_stored[:]},
		{id="LP",building_id="landing_platform",position={2,0},health=1,enable_at_start=true},
	}
	subjects := [?]logic.Subject_Instance{
		{id="H1",subject_id="human",residence="HH",health=1,speed=1,initial_assignment={building_id="GEN",role_id=.worker}},
		{id="H2",subject_id="human",residence="HH",health=1,speed=1},
		{id="H3",subject_id="human",residence="HH",health=1,speed=1},
		{id="H4",subject_id="human",residence="HH",health=1,speed=1},
		{id="H5",subject_id="human",residence="HH",health=1,speed=1},
		{id="R1",subject_id="robot",residence="RH",health=1,speed=1,initial_assignment={building_id="WS",role_id=.worker}},
		{id="R2",subject_id="robot",residence="RH",health=1,speed=1},
	}
	emergency_subjects := [?]logic.Ship_Subject{{subject_id="human",capacity=12},{subject_id="robot",capacity=6}}
	ships := [?]logic.Ship{{id="emergency",type=logic.Ship_Type_Emergency,max_speed=2000,max_speed_hours=1,units_per_hour=4,subjects=emergency_subjects[:]}}
	station_ships := [?]logic.Station_Ship{{ship_id="emergency",units=1}}
	station := logic.Space_Station{ships=station_ships[:]}
	instance := logic.Station_Instance{distance=5000}

	game := logic.new_session(initial[:],definitions[:],context.allocator)
	defer logic.destroy(&game,context.allocator)
	fleet := logic.new_transports(station,instance,ships[:],initial[:],subjects[:],context.allocator,definitions[:],subject_types[:])
	defer logic.destroy_transports(&fleet,context.allocator)
	logic.derive_staffing(&game,&fleet)
	logic.schedule_staffing(&game,&fleet)

	generator := smoke_building_index(&game,"GEN")
	assert(generator >= 0)
	report.hours = GAMEPLAY_SMOKE_HOURS
	report.ticks = GAMEPLAY_SMOKE_HOURS*logic.TICKS_PER_HOUR
	report.population_start = smoke_live_population(&fleet)
	report.min_available_kw = 1e9
	report.shortage_health_min = 1

	previous_phases: [SMOKE_TRACK]c.Work_Phase
	previous_occupants: [SMOKE_TRACK]c.Subject_ID
	unstaffed_ticks := 0
	for tick in 0..<report.ticks {
		hour := tick/logic.TICKS_PER_HOUR
		// Scripted input (documented in docs/gameplay-smoke.md). The shortage episode
		// now uses real per-building stock instead of the retired manual fulfillment
		// placeholder: H5 waits in the empty shelter, so the hourly fulfillment step
		// keeps both of its needs in shortage until the store is resupplied.
		if tick == 0 {
			if index := smoke_subject_index(&fleet,"H5"); index >= 0 {
				subject := &fleet.subjects[index]
				// Clear its roles so the scheduler cannot move it to a stocked workplace
				// mid-episode; it stays inside the unstocked shelter.
				subject.roles = nil
				subject.activity = .Inside
				subject.destination = "SH"
				for building in initial { if building.id == "SH" { subject.position = building.position; subject.target = building.position } }
				subject.needs[0].fulfillment = 0
				subject.needs[1].fulfillment = 0
				report.shortage_health_start = subject.health
			}
		}
		if hour == 30 {
			if index := smoke_subject_index(&fleet,"H3"); index >= 0 { fleet.subjects[index].health = 0.05 }
		}
		if hour == 36 {
			// The deferred logistics phase would resupply the shelter; doing it by hand
			// ends the stock-driven shortage at the next hour boundary.
			for building, i in game.buildings {
				if building.id != "SH" { continue }
				for j in game.stock_first[i]..<game.stock_first[i+1] { game.stock[j].amount = game.stock[j].capacity }
			}
		}
		if hour == 40 {
			if index := smoke_subject_index(&fleet,"H4"); index >= 0 { fleet.subjects[index].health = 0.05 }
		}
		if hour == 42 {
			if index := smoke_subject_index(&fleet,"H4"); index >= 0 {
				if fleet.subjects[index].medical == .Pending_Evacuation {
					report.death_while_waiting = true
					fleet.subjects[index].needs[0].fulfillment = 0
					fleet.subjects[index].needs[1].fulfillment = 0
					fleet.subjects[index].health = 0
				}
			}
		}
		for &subject in fleet.subjects {
			if int(subject.id) < SMOKE_TRACK { previous_phases[int(subject.id)] = subject.phase }
		}

		// Exact fixed-tick order used by the application loop. The smoke drives its own
		// tick counter, matching the logical index the application reconstructs from the
		// frame-batched clock.
		logic.step(&game)
		logic.derive_staffing(&game,&fleet)
		logic.step_production(&game,i64(tick)+1)
		logic.step_need_fulfillment(&game,&fleet,i64(tick)+1)
		logic.step_subject_health(&fleet)
		logic.step_medical(&game,&fleet)
		logic.step_shifts(&game,&fleet)
		logic.step_transports(&fleet,&game,definitions[:])
		logic.commit_shift_handoffs(&game,&fleet)
		logic.derive_staffing(&game,&fleet)
		logic.step_load_shedding(&game)
		logic.schedule_staffing(&game,&fleet)

		// Observed integration outcomes.
		for &subject in fleet.subjects {
			if subject.activity == .Removed { continue }
			if int(subject.id) < SMOKE_TRACK && subject.phase == .Extra_Working && previous_phases[int(subject.id)] != .Extra_Working {
				report.overtime_entries += 1
			}
			shortages := 0
			for i in 0..<subject.need_count { if subject.needs[i].shortage_hours > 0 { shortages += 1 } }
			if shortages >= 2 { report.simultaneous_shortage_ticks += 1 }
		}
		for i in 0..<min(logic.staffing_slot_count(&game),SMOKE_TRACK) {
			occupant := logic.staffing_slot_snapshot(&game,i).occupant
			if occupant != 0 && previous_occupants[i] != 0 && occupant != previous_occupants[i] { report.shift_handoffs += 1 }
			previous_occupants[i] = occupant
		}
		if game.active[generator] && !logic.building_staffed(&game,generator) { unstaffed_ticks += 1 }
		if logic.building_output_gated(&game,generator) { report.power_gated_ticks += 1 }
		if available := logic.balance(&game).available_kw; available < report.min_available_kw { report.min_available_kw = available }
		if index := smoke_subject_index(&fleet,"H3"); index >= 0 {
			if fleet.subjects[index].medical == .Hospitalized { report.patient_hospitalized = true }
			if report.patient_hospitalized && fleet.subjects[index].medical == .None && fleet.subjects[index].activity == .Inside { report.patient_returned_home = true }
		}
		if index := smoke_subject_index(&fleet,"H5"); index >= 0 {
			if fleet.subjects[index].health < report.shortage_health_min { report.shortage_health_min = fleet.subjects[index].health }
		}

		for event in logic.pending_events(&game.events) {
			switch event.kind {
			case .Staffing_Lost: report.staffing_lost += 1
			case .Staffing_Restored: report.staffing_restored += 1
			case .Power_Shed: report.power_shed += 1
			case .Medical_Evacuation: report.medical_evacuations += 1
			case .Medical_Return: report.medical_returns += 1
			case .Subject_Died: report.deaths += 1
			case .Production_Blocked, .Production_Resumed:
				// This scenario defines no building recipes; the production step is
				// exercised by the dedicated headless tests.
			}
		}
		logic.clear_events(&game.events)
	}

	report.population_end = smoke_live_population(&fleet)
	report.generator_unstaffed_hours = f64(unstaffed_ticks)/f64(logic.TICKS_PER_HOUR)
	report.population_conserved = report.population_start-report.deaths == report.population_end
	report.priority_medical_landed_first = gameplay_smoke_priority_landing()

	ok = report.population_conserved &&
		report.shift_handoffs >= 1 &&
		report.overtime_entries >= 1 &&
		report.staffing_lost >= 1 && report.staffing_restored >= 1 &&
		report.power_gated_ticks > 0 && report.generator_unstaffed_hours > 0 &&
		report.simultaneous_shortage_ticks > 0 &&
		report.shortage_health_min < report.shortage_health_start &&
		report.medical_evacuations >= 1 && report.medical_returns >= 1 &&
		report.patient_hospitalized && report.patient_returned_home &&
		report.death_while_waiting && report.deaths >= 1 &&
		report.priority_medical_landed_first
	return
}

// Focused priority-landing episode: one busy pad plus an ordinary and a medical
// mission waiting with an earlier ordinary ticket. The medical mission must be
// admitted to the pad first once the pad frees (non-preemptive two-class priority).
gameplay_smoke_priority_landing :: proc() -> bool {
	definitions := [?]logic.Building_Type{{id="landing_platform"}}
	initial := [?]logic.Building_Instance{{id="LP",building_id="landing_platform",health=1,enable_at_start=true}}
	game := logic.new_session(initial[:],definitions[:],context.allocator)
	defer logic.destroy(&game,context.allocator)
	fleet := logic.new_transports({}, {distance=10}, nil, initial[:], nil, context.allocator, definitions[:])
	defer logic.destroy_transports(&fleet,context.allocator)
	fleet.count = 3
	fleet.missions[0] = {phase=.Unloading,platform_id="LP",handling_rate=1,handling_hours=8,phase_duration=8,phase_elapsed=0}
	fleet.missions[1] = {phase=.Waiting_Landing,landing_ticket=1,ship_id="ordinary"}
	fleet.missions[2] = {phase=.Waiting_Landing,landing_ticket=2,ship_id="emergency",medical=true,evacuation=true,pickup_platform_id="LP"}
	for _ in 0..<12*logic.TICKS_PER_HOUR {
		logic.step_transports(&fleet,&game,definitions[:])
		if fleet.missions[2].phase == .Landing && fleet.missions[1].phase == .Waiting_Landing { return true }
		if fleet.missions[1].phase == .Landing { return false }
	}
	return false
}
