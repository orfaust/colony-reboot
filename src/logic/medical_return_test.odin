package logic

import "core:testing"
import c "../contracts"

// Headless task-10 regressions: station recovery, return requests, emergency return
// batching, landing wait, death exclusion and identity preservation across the round
// trip. Reuses the Emergency_Test fixture and helpers from medical_transport_test.odin
// (same package). No renderer, window or GPU resource is involved.

// Adds an identified hospital patient at the station, outside stock and not in any
// station capacity.
emergency_hospitalize :: proc(r: ^Emergency_Test, subject_id, home: string, health: f32) -> int {
	index := add_runtime_subject(&r.fleet,{subject_id=subject_id,health=health,activity=.Station})
	assert(index >= 0)
	subject := &r.fleet.subjects[index]
	subject.medical = .Hospitalized
	subject.medical_home = home
	return index
}

emergency_test_return_mission :: proc(r: ^Emergency_Test) -> int {
	for mission, i in r.fleet.missions[:r.fleet.count] {
		if mission.medical && !mission.evacuation { return i }
	}
	return -1
}

emergency_test_event_count :: proc(r: ^Emergency_Test, kind: c.Sim_Event_Kind) -> int {
	count := 0
	for event in pending_events(&r.game.events) { if event.kind == kind { count += 1 } }
	return count
}

@(test)
station_recovery_crosses_min_work_health_once :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	below := emergency_hospitalize(&r,"human","H",0.39)
	at := emergency_hospitalize(&r,"human","H",0.4)
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[at].medical == .Returning,"threshold equality requests a return")
	testing.expect(t,r.fleet.subjects[below].medical == .Hospitalized,"below the threshold stays hospitalized")
	// Recovery is automatic and brings a patient over the boundary.
	for _ in 0..<30 {
		step_subject_health(&r.fleet)
		step_medical(&r.game,&r.fleet)
	}
	testing.expect(t,r.fleet.subjects[below].medical == .Returning,"recovery reaches min_work_health")
	emergency_test_conserved(t,&r)
}

@(test)
station_recovery_is_automatic_and_consumes_no_stock :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r,5)
	defer emergency_test_destroy(&r)
	patient := emergency_hospitalize(&r,"human","H",0.2)
	before := r.fleet.subjects[patient].health
	for _ in 0..<60 {
		step_subject_health(&r.fleet)
		if r.fleet.subjects[patient].health >= 0.2+f32(0.04) { break }
	}
	testing.expect(t,r.fleet.subjects[patient].health > before,"health recovers at the configured rate")
	testing.expect(t,r.fleet.stock[0].units == 5,"recovery consumes no station stock")
	emergency_test_conserved(t,&r)
}

@(test)
return_batching_fills_capacity_and_splits_the_remainder :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 2
	for _ in 0..<5 { emergency_hospitalize(&r,"human","H",0.6) }
	step_medical(&r.game,&r.fleet)
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 2,"two emergency return legs")
	first, second := &r.fleet.missions[0], &r.fleet.missions[1]
	testing.expect(t,first.medical && !first.evacuation && first.phase == .Loading)
	testing.expect(t,first.units == 3 && second.units == 2)
	for i in first.manifest { testing.expect(t,i != second.manifest[0] && i != second.manifest[1]) }
	testing.expect(t,r.fleet.available[0].units == 0)
	emergency_test_conserved(t,&r)
}

@(test)
return_requires_a_compatible_emergency_ship :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[1].units = 1 // Robot-only emergency ship.
	human := emergency_hospitalize(&r,"human","H",0.6)
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[human].medical == .Returning)
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 0,"no compatible emergency ship")
	testing.expect(t,!r.fleet.subjects[human].medical_reserved)
	// An ordinary transport is never used either.
	r.fleet.available[3].units = 2
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 0)
	// A compatible emergency ship retries successfully.
	r.fleet.available[0].units = 1
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].subject_id == "human" && r.fleet.missions[0].units == 1)
	emergency_test_conserved(t,&r)
}

@(test)
return_mission_waits_for_an_occupied_platform_then_lands :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	emergency_hospitalize(&r,"human","H",0.6)
	step_medical(&r.game,&r.fleet)
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	busy := emergency_test_busy_mission(&r)
	return_index := emergency_test_return_mission(&r)
	testing.expect(t,return_index >= 0)
	r.game.active[3] = false // Only LP remains, and the busy mission holds it.
	emergency_test_tick(&r,90) // Load, fly and hold behind the occupied pad.
	testing.expect(t,r.fleet.missions[return_index].phase == .Waiting_Landing)
	testing.expect(t,r.fleet.missions[busy].phase == .Unloading)
	r.fleet.missions[busy].phase = .Completed
	step_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.missions[return_index].phase == .Landing,"the return leg lands once the pad frees")
	emergency_test_conserved(t,&r)
}

@(test)
dead_return_patients_are_excluded_and_removed :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	dead := emergency_hospitalize(&r,"human","H",0.6)
	alive := emergency_hospitalize(&r,"human","H",0.6)
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[dead].medical == .Returning && r.fleet.subjects[alive].medical == .Returning)
	// The patient dies before any return leg is dispatched.
	r.fleet.subjects[dead].health = 0
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[dead].activity == .Removed)
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].units == 1 && r.fleet.missions[0].manifest[0] == alive)
	testing.expect(t,r.fleet.stock[0].units == 0,"a hospitalized death never decrements station stock")
	testing.expect(t,emergency_test_event_count(&r,.Subject_Died) == 1)
	emergency_test_conserved(t,&r)
}

@(test)
dead_patient_onboard_a_return_leg_keeps_manifests_exact :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	first := emergency_hospitalize(&r,"human","H",0.6)
	second := emergency_hospitalize(&r,"human","H",0.6)
	step_medical(&r.game,&r.fleet)
	dispatch_transports(&r.fleet,&r.game,r.definitions[:])
	testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].units == 2)
	// Load both patients so they are aboard when one dies.
	for _ in 0..<200 {
		emergency_test_tick(&r,1)
		if r.fleet.missions[0].loaded == 2 { break }
	}
	testing.expect(t,r.fleet.missions[0].loaded == 2 && r.fleet.missions[0].phase != .Completed)
	r.fleet.subjects[first].health = 0
	step_medical(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[first].activity == .Removed)
	testing.expect(t,r.fleet.missions[0].units == 1 && r.fleet.missions[0].loaded == 1 && len(r.fleet.missions[0].manifest) == 1)
	emergency_test_tick(&r,600)
	testing.expect(t,r.fleet.missions[0].phase == .Completed)
	testing.expect(t,r.fleet.subjects[second].medical == .None && r.fleet.subjects[second].residence == "H")
	emergency_test_conserved(t,&r)
}

@(test)
patients_preserve_identity_and_return_home_rested_and_unassigned :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	patient := emergency_patient_at(&r,"human","LP","H")
	id := r.fleet.subjects[patient].id
	// Outbound evacuation to the station.
	emergency_test_tick(&r,600)
	testing.expect(t,r.fleet.subjects[patient].medical == .Hospitalized && r.fleet.subjects[patient].activity == .Station)
	testing.expect(t,r.fleet.subjects[patient].id == id)
	testing.expect(t,r.fleet.occupants[1] == 0)
	// Recover and wait for the landing-platform discharge.
	r.fleet.subjects[patient].health = 0.35
	for _ in 0..<2000 {
		emergency_test_tick(&r,1)
		if r.fleet.subjects[patient].medical == .None && r.fleet.subjects[patient].activity != .Station { break }
	}
	subject := &r.fleet.subjects[patient]
	testing.expect(t,subject.medical == .None,"the patient left the medical lifecycle")
	testing.expect(t,subject.id == id,"stable identity across the round trip")
	testing.expect(t,subject.residence == "H" && subject.destination == "H")
	testing.expect(t,subject.activity == .Inside || subject.activity == .Waiting || subject.activity == .Moving)
	testing.expect(t,subject.assignment == nil && subject.reservation == nil && subject.occupation == "","returned unassigned")
	testing.expect(t,subject.rest_hours == 12,"returned fully rested")
	testing.expect(t,r.fleet.occupants[1] == 1,"counted once at the original residence")
	testing.expect(t,r.fleet.stock[0].units == 0,"never merged into station stock")
	testing.expect(t,emergency_test_event_count(&r,.Medical_Return) == 1)
	emergency_test_conserved(t,&r)
	// The returned patient is immediately eligible for any role it supports.
	definition, found := find_subject_type(&r.fleet,"human")
	testing.expect(t,found && staffing_subject_eligible(&r.fleet.subjects[patient],definition,.worker),
		"the returned patient is eligible for a supported role")
}

@(test)
multiple_patients_recover_and_return_in_one_leg :: proc(t: ^testing.T) {
	r: Emergency_Test
	emergency_test_init(&r)
	defer emergency_test_destroy(&r)
	r.fleet.available[0].units = 1
	first := emergency_hospitalize(&r,"human","H",0.39)
	second := emergency_hospitalize(&r,"human","H",0.39)
	emergency_test_tick(&r,20) // Both recover over the boundary together.
	testing.expect(t,r.fleet.subjects[first].medical == .Returning && r.fleet.subjects[second].medical == .Returning)
	return_index := emergency_test_return_mission(&r)
	testing.expect(t,return_index >= 0 && r.fleet.missions[return_index].units == 2)
	emergency_test_tick(&r,600)
	testing.expect(t,r.fleet.subjects[first].medical == .None && r.fleet.subjects[second].medical == .None)
	testing.expect(t,r.fleet.occupants[1] == 2)
	testing.expect(t,emergency_test_event_count(&r,.Medical_Return) == 2)
	emergency_test_conserved(t,&r)
}
