package logic

import "core:testing"

@(test)
throughput_boarding_unloading_and_departure_gates :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,1)
    defer transport_test_destroy(&r)
    r.ships[0].units_per_hour = 2
    r.game.buildings[1].position = {20,0}
    transport_test_activate(&r)
    mission := &r.fleet.missions[0]
    id := r.fleet.subjects[mission.manifest[0]].id
    testing.expect(t,mission.phase_duration == 2.5 && transport_cargo(mission^) == 0)
    transport_test_ticks(&r,29)
    testing.expect(t,mission.phase == .Loading && mission.loaded == 0)
    transport_test_ticks(&r,1)
    subject, _ := subject_snapshot(&r.fleet,id)
    testing.expect(t,mission.loaded == 1 && transport_cargo(mission^) == 1 && subject.activity == .Onboard)
    transport_test_ticks(&r,119)
    testing.expect(t,mission.phase == .Loading && mission.loaded == 4 && mission.travelled == 0)
    transport_test_ticks(&r,1)
    testing.expect(t,mission.phase == .Landing && mission.loaded == 5)
    transport_test_ticks(&r,60)
    testing.expect(t,mission.phase == .Unloading && mission.delivered == 0)
    transport_test_ticks(&r,30)
    subject, _ = subject_snapshot(&r.fleet,id)
    testing.expect(t,mission.delivered == 1 && transport_cargo(mission^) == 4)
    testing.expect(t,subject.activity == .Waiting && subject.residence == "H")
    transport_test_ticks(&r,119)
    testing.expect(t,mission.phase == .Unloading && mission.delivered == 4)
    transport_test_ticks(&r,1)
    testing.expect(t,mission.phase == .Taking_Off && transport_cargo(mission^) == 0)
    transport_test_ticks(&r,60)
    testing.expect(t,mission.phase == .Completed && r.fleet.available[0].units == 2)
    subject, _ = subject_snapshot(&r.fleet,id)
    testing.expect(t,subject.id == id && subject.activity == .Moving)
}

@(test)
partial_loading_cancellation_returns_same_people_at_throughput :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r)
    defer transport_test_destroy(&r)
    r.ships[0].units_per_hour = 2
    transport_test_activate(&r)
    mission := &r.fleet.missions[0]
    first := r.fleet.subjects[mission.manifest[0]].id
    third := r.fleet.subjects[mission.manifest[2]].id
    transport_test_ticks(&r,60)
    testing.expect(t,mission.loaded == 2)
    transport_test_activate(&r)
    testing.expect(t,r.fleet.stock[0].units == 8 && transport_cargo(mission^) == 2)
    unboarded, _ := subject_snapshot(&r.fleet,third)
    testing.expect(t,unboarded.activity == .Station)
    transport_test_ticks(&r,30)
    returned, _ := subject_snapshot(&r.fleet,first)
    testing.expect(t,returned.activity == .Station && returned.id == first)
    testing.expect(t,mission.phase == .Return_Unloading && r.fleet.stock[0].units == 9 && transport_cargo(mission^) == 1)
    transport_test_ticks(&r,30)
    testing.expect(t,mission.phase == .Cancelled && r.fleet.stock[0].units == 10 && r.fleet.available[0].units == 2)
    testing.expect(t,len(r.fleet.subjects) == 10)
    // A zero throughput must not reserve subjects or launch a ship.
    r.ships[0].units_per_hour = 0
    transport_test_activate(&r)
    testing.expect(t,r.fleet.count == 1 && r.fleet.stock[0].units == 10)
}

@(test)
initial_subjects_and_resident_counts_become_individuals :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r)
    defer transport_test_destroy(&r)
    r.initial[1].position = {4,2}
    r.initial[1].residents_amount = f32(3)
    initial := [?]Subject_Instance{{id="named-person",subject_id="human",residence="H",speed=0.5}}
    reset_transports(&r.fleet,r.instance,r.initial[:],initial[:])
    testing.expect(t,len(r.fleet.subjects) == 13 && r.fleet.occupants[1] == 3)
    named := r.fleet.subjects[0]
    testing.expect(t,named.source_id == "named-person" && named.position == r.initial[1].position && named.speed == 0.5)
    for subject, i in r.fleet.subjects { for previous in r.fleet.subjects[:i] { testing.expect(t,subject.id != previous.id) } }
}
