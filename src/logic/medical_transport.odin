package logic

import "core:math"

// Emergency medical transport (roadmap task 9): dispatch, batching, re-targeting
// and the two-class landing priority. Medical missions carry identified patients
// (never anonymous stock) and use only `emergency` ships.
//
// Landing priority
// ----------------
// There are two classes: medical (emergency) and ordinary. Priority is
// non-preemptive: a ship already descending, unloading or taking off keeps the
// platform. Among ships holding for a platform, every medical mission is admitted
// before any ordinary mission, and FIFO by arrival ticket is preserved within each
// class. A held mission that cannot use a platform never blocks another (the
// existing inactive-pad rule). Medical missions are re-targeted to another active
// platform when their pickup pad disappears, and cancelled cleanly only when no
// platform is active anywhere, releasing their seats and ship.
//
// Selection and batching
// ----------------------
// For a ready patient type the ship is the first compatible available emergency ship
// in stable catalog order. Every patient type of one ship/leg is batched up to that
// ship's capacity and the mission launches with whatever is ready: an executable
// mission is never delayed merely to fill the ship. Each mission carries one subject
// type because per-type capacity, handling and manifests are per-type.
//
// Ownership and lifetime
// ----------------------
// Manifests are session-owned and freed with the mission; patient flags live on the
// runtime subject. All procedures are headless and allocation-free except creating a
// mission manifest, exactly like ordinary dispatch.

// One landing class ordering rule. Emergency (medical) missions outrank every
// ordinary mission; within one class the lower arrival ticket lands first.
@(private)
transport_lands_ahead :: proc(other, mission: Transport) -> bool {
	if other.medical != mission.medical { return other.medical }
	return other.landing_ticket < mission.landing_ticket
}

// True when the named building exists, is a landing platform and is active.
@(private)
landing_platform_active :: proc(game: ^State, platform_id: string) -> bool {
	if platform_id == "" { return false }
	for building, i in game.buildings {
		if building.id != platform_id { continue }
		return building.building_id == "landing_platform" && game.active[i]
	}
	return false
}

// Whole shipped medical capacity of one emergency ship for one subject type.
// Non-emergency ships carry no medical patients.
@(private)
emergency_capacity :: proc(ship: Ship, subject_id: string) -> f32 {
	if ship.type != Ship_Type_Emergency { return 0 }
	for entry in ship.subjects {
		if entry.subject_id == subject_id { return f32(math.floor(f64(max(f32(0),entry.capacity)))) }
	}
	return 0
}

// A patient ready to be batched: requested, not already holding an emergency seat,
// assigned to this platform and physically colony-side.
@(private)
medical_ready_patient :: proc(subject: ^Runtime_Subject, subject_id, platform_id: string) -> bool {
	if subject.medical != .Pending_Evacuation || subject.medical_reserved { return false }
	if subject.subject_id != subject_id || subject.evacuation_platform != platform_id { return false }
	return medical_subject_in_colony(subject)
}

// First catalog ship with an available emergency unit that can carry the subject
// type, in stable catalog order. Returns the ship value and the available-ships
// index to decrement on dispatch. Reused by the return direction of task 10.
@(private)
first_available_emergency :: proc(state: ^Transport_State, subject_id: string) -> (Ship, int, bool) {
	for ship in state.ships {
		if ship.max_speed <= 0 || ship.units_per_hour <= 0 { continue }
		if emergency_capacity(ship,subject_id) < 1 { continue }
		for &available, i in state.available {
			if available.ship_id == ship.id && available.units > 0 { return ship, i, true }
		}
	}
	return {}, 0, false
}

// Claims one batched manifest and launches an empty emergency leg to the colony
// platform. The manifest owns the individuals until station discharge.
@(private)
start_medical_mission :: proc(state: ^Transport_State, ship: Ship, available_index: int, subject_id, platform_id: string, units: int) {
	manifest := make([]int,units,state.allocator)
	n := 0
	for &subject, index in state.subjects {
		if !medical_ready_patient(&subject,subject_id,platform_id) { continue }
		subject.medical_reserved = true
		manifest[n] = index
		n += 1
		if n == units { break }
	}
	assert(n == units) // The caller counted exactly this many ready patients.
	route := max(f64(0),f64(state.distance)-LANDING_RANGE_KM)
	mission := Transport{medical=true,evacuation=true,ship_id=ship.id,subject_id=subject_id,
		destination=platform_id,pickup_platform_id=platform_id,manifest=manifest,units=f32(units),
		distance=f64(state.distance),leg_distance=route,max_speed=f64(ship.max_speed),
		max_speed_hours=f64(ship.max_speed_hours),handling_rate=f64(ship.units_per_hour),
		handling_hours=handling_duration(f32(units),f64(ship.units_per_hour)),
		duration=travel_duration(route,f64(ship.max_speed),f64(ship.max_speed_hours))}
	set_transport_phase(&mission,.Outbound,mission.duration)
	append_mission(state,mission)
	state.available[available_index].units -= 1
}

// Batches ready compatible patients onto emergency ships, one platform in building
// order and one subject type per mission. A mission launches as soon as the first
// compatible ship and at least one ready patient exist, so it is never delayed to
// fill the ship. Nothing is dispatched when no compatible emergency ship is
// available; the patients stay pending and retry next tick.
dispatch_medical_evacuations :: proc(state: ^Transport_State, game: ^State) {
	for building, i in game.buildings {
		if building.building_id != "landing_platform" || !game.active[i] { continue }
		for state.count < TRANSPORT_LIMIT {
			created := false
			// Stable subject-type order; the ship is chosen in stable catalog order.
			for definition in state.subject_types {
				ready := 0
				for &subject in state.subjects {
					if medical_ready_patient(&subject,definition.id,building.id) { ready += 1 }
				}
				if ready == 0 { continue }
				ship, available_index, found := first_available_emergency(state,definition.id)
				if !found { continue }
				units := min(ready,int(emergency_capacity(ship,definition.id)))
				if units < 1 { continue }
				start_medical_mission(state,ship,available_index,definition.id,building.id,units)
				created = true
				break
			}
			if !created { break }
		}
	}
}

// Keeps held medical missions consistent with the active platforms: re-target a
// mission (and its still-walking patients) to another active platform when its
// pickup pad disappears, and cancel a stationary held mission cleanly when no
// platform is active anywhere. Cancellation releases the patient seats and returns
// the ship; a boarded mission is never cancelled because it already owns the
// individuals and must complete its return.
@(private)
reconcile_medical_missions :: proc(state: ^Transport_State, game: ^State) {
	for &mission in state.missions[:state.count] {
		if !mission.medical || mission.loaded > 0 { continue }
		if mission.phase != .Outbound && mission.phase != .Waiting_Landing { continue }
		if landing_platform_active(game,mission.pickup_platform_id) { continue }
		replaced := false
		for building, i in game.buildings {
			if building.building_id != "landing_platform" || !game.active[i] { continue }
			mission.pickup_platform_id = building.id
			mission.platform_id = ""
			for index in mission.manifest {
				subject := &state.subjects[index]
				if subject.medical != .Pending_Evacuation { continue }
				subject.evacuation_platform = building.id
				subject.destination = building.id
				subject.target = building.position
				subject.activity = .Waiting
				subject.wait_hours = 0
			}
			replaced = true
			break
		}
		if replaced { continue }
		if mission.phase == .Waiting_Landing {
			for index in mission.manifest {
				subject := &state.subjects[index]
				if subject.medical == .Pending_Evacuation { subject.medical_reserved = false }
			}
			withdraw_transport(state,&mission)
		}
	}
}

// A recovered patient waiting at the station for a return leg.
@(private)
medical_return_patient :: proc(subject: ^Runtime_Subject, subject_id: string) -> bool {
	return subject.medical == .Returning && !subject.medical_reserved && subject.activity == .Station && subject.subject_id == subject_id
}

// Claims one return manifest and starts station loading on a compatible emergency
// ship. The ship then flies to the colony and discharges the patients to their
// original homes.
@(private)
start_medical_return :: proc(state: ^Transport_State, ship: Ship, available_index: int, subject_id: string, units: int) {
	manifest := make([]int,units,state.allocator)
	n := 0
	for &subject, index in state.subjects {
		if !medical_return_patient(&subject,subject_id) { continue }
		subject.medical_reserved = true
		manifest[n] = index
		n += 1
		if n == units { break }
	}
	assert(n == units)
	route := max(f64(0),f64(state.distance)-LANDING_RANGE_KM)
	mission := Transport{medical=true,evacuation=false,ship_id=ship.id,subject_id=subject_id,
		manifest=manifest,units=f32(units),distance=f64(state.distance),leg_distance=route,
		max_speed=f64(ship.max_speed),max_speed_hours=f64(ship.max_speed_hours),
		handling_rate=f64(ship.units_per_hour),handling_hours=handling_duration(f32(units),f64(ship.units_per_hour)),
		duration=travel_duration(route,f64(ship.max_speed),f64(ship.max_speed_hours))}
	set_transport_phase(&mission,.Loading,mission.handling_hours)
	append_mission(state,mission)
	state.available[available_index].units -= 1
}

// Batches recovered patients onto emergency ships, one subject type per leg. A leg
// launches with whatever is ready and never waits to fill; with no compatible ship
// the patients stay `.Returning` and retry next tick.
@(private)
dispatch_medical_returns :: proc(state: ^Transport_State) {
	for state.count < TRANSPORT_LIMIT {
		created := false
		for definition in state.subject_types {
			ready := 0
			for &subject in state.subjects { if medical_return_patient(&subject,definition.id) { ready += 1 } }
			if ready == 0 { continue }
			ship, available_index, found := first_available_emergency(state,definition.id)
			if !found { continue }
			units := min(ready,int(emergency_capacity(ship,definition.id)))
			if units < 1 { continue }
			start_medical_return(state,ship,available_index,definition.id,units)
			created = true
			break
		}
		if !created { break }
	}
}

// Discharges returned patients into the colony at their original residence. Each
// person keeps their stable ID, becomes unassigned and fully rested, and is eligible
// for any supported role. Discharge increments residence occupancy directly and
// never touches ordinary cargo reservations or station stock. If no residence can be
// resolved the remaining patients stay aboard and return to the station.
@(private)
deliver_medical_patients :: proc(state: ^Transport_State, game: ^State, mission: ^Transport, total: f32) {
	if total <= mission.delivered { return }
	for i in int(mission.delivered)..<int(total) {
		subject := &state.subjects[mission.manifest[i]]
		home := subject.medical_home
		home_index := -1
		for building, bi in game.buildings {
			if building.id != home { continue }
			home_index = bi
			home = building.id
			break
		}
		if home_index < 0 {
			// No resolvable residence: leave the rest aboard; they return to the station.
			break
		}
		mission.destination = home
		disembark_subject(state,game,mission.manifest[i],mission)
		subject = &state.subjects[mission.manifest[i]]
		state.occupants[home_index] += 1
		game.buildings[home_index].residents_amount = state.occupants[home_index]
		subject.medical = .None
		subject.medical_reserved = false
		subject.medical_home = ""
		subject.evacuating = false
		subject.evacuation_reserved = false
		subject.evacuation_platform = ""
		subject.assignment = nil
		subject.reservation = nil
		subject.occupation = ""
		subject.phase = .Idle
		subject.work_hours = 0
		subject.idle_hours = 0
		if definition, found := find_subject_type(state,subject.subject_id); found { subject.rest_hours = f64(definition.rest_time) }
		push_event(&game.events,.Medical_Return,subject_id=subject.id)
		mission.delivered = f32(i+1)
	}
}
