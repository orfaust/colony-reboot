package logic

import "core:testing"

Evacuation_Test :: struct {
    base: Transport_Test,
    capacity: [1]Station_Subject,
}
evacuation_test_init :: proc(e: ^Evacuation_Test) {
    r := &e.base
    transport_test_init(r,1,1)
    e.capacity = {{subject_id="human",capacity=13}}
    r.fleet.station.subjects = e.capacity[:]
    r.initial[1].enable_at_start = true
    r.initial[1].residents_amount = f32(3)
    r.initial[1].position = {4,0}
    r.passengers[0].capacity = 2
    r.ships[0].units_per_hour = 2
    r.game.timing[1] = {warmup_hours=1,cooldown_hours=1}
    reset(&r.game,r.initial[:])
    reset_transports(&r.fleet,r.instance,r.initial[:],nil)
}
evacuation_test_conserved :: proc(t: ^testing.T, r: ^Transport_Test) {
    station, residents, alive := 0,0,0
    for subject in r.fleet.subjects {
        if subject.activity != .Removed { alive += 1 }
        if subject.activity == .Station { station += 1 }
        if subject.residence == "H" && (subject.activity == .Inside || subject.activity == .Moving || subject.activity == .Waiting) { residents += 1 }
    }
    testing.expect(t,alive == 13 && len(r.fleet.subjects) == 13)
    testing.expect(t,f32(station) == r.fleet.stock[0].units && f32(residents) == r.fleet.occupants[1])
    busy := 0
    for mission in r.fleet.missions[:r.fleet.count] {
        if mission.phase == .Landing || mission.phase == .Unloading || mission.phase == .Taking_Off { busy += 1 }
    }
    testing.expect(t,busy <= 1)
}

@(test)
evacuation_cooldown_request_is_idempotent_and_reversible :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    defer transport_test_destroy(r)
    transport_test_activate(r)
    testing.expect(t,r.fleet.evacuation_pending[1] && !r.fleet.evacuation_started[1])
    transport_test_ticks(r,30)
    for _ in 0..<4 { dispatch_transports(&r.fleet,&r.game,r.definitions[:]) }
    testing.expect(t,r.fleet.count == 0 && r.fleet.occupants[1] == 3)
    for subject in r.fleet.subjects[:3] { testing.expect(t,subject.activity == .Inside && subject.position == r.initial[1].position) }
    // Keep immigration out of this cancellation test: the house is already full.
    r.definitions[1].residents = {type="human",capacity=3}
    transport_test_activate(r)
    testing.expect(t,!r.fleet.evacuation_pending[1] && r.fleet.count == 0)
    for subject in r.fleet.subjects[:3] { testing.expect(t,!subject.evacuating && subject.residence == "H") }
    transport_test_ticks(r,60)
    evacuation_test_conserved(t,r)
    testing.expect(t,r.fleet.count == 0)
}

@(test)
evacuation_without_ship_waits_at_platform_then_returns_same_people :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    defer transport_test_destroy(r)
    ids := [3]Runtime_Subject{r.fleet.subjects[0],r.fleet.subjects[1],r.fleet.subjects[2]}
    r.fleet.available[0].units = 0
    transport_test_activate(r)
    transport_test_ticks(r,59)
    testing.expect(t,!r.fleet.evacuation_started[1] && r.fleet.subjects[0].activity == .Inside)
    transport_test_ticks(r,1)
    testing.expect(t,r.fleet.evacuation_started[1] && r.fleet.subjects[0].activity == .Moving && r.fleet.count == 0)
    testing.expect(t,move_subject(&r.fleet,&r.game,{id=ids[0].id,destination="H"}) == .Unavailable)
    transport_test_ticks(r,150)
    for subject in r.fleet.subjects[:3] { testing.expect(t,subject.activity == .Inside && subject.destination == "LP" && subject.residence == "H") }
    testing.expect(t,r.fleet.occupants[1] == 3)
    r.fleet.available[0].units = 1
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
    testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].evacuation && r.fleet.missions[0].units == 2 && r.fleet.missions[0].loaded == 0)
    for _ in 0..<700 { transport_test_ticks(r,1); evacuation_test_conserved(t,r) }
    testing.expect(t,r.fleet.count == 2 && r.fleet.stock[0].units == 13 && r.fleet.occupants[1] == 0 && r.fleet.available[0].units == 1)
    for original in ids {
        subject, found := subject_snapshot(&r.fleet,original.id)
        testing.expect(t,found && subject.activity == .Station && subject.residence == "" && !subject.evacuating)
    }
}

@(test)
evacuation_fifo_waits_for_walkers_and_reserves_station_capacity :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    defer transport_test_destroy(r)
    transport_test_activate(r)
    transport_test_ticks(r,60)
    testing.expect(t,r.fleet.count == 2)
    r.fleet.stock[0].units_per_hour = 4
    transport_test_ticks(r,61)
    testing.expect(t,r.fleet.missions[0].phase == .Unloading && r.fleet.missions[0].loaded == 0)
    testing.expect(t,r.fleet.missions[1].phase == .Waiting_Landing && r.fleet.missions[1].loaded == 0)
    testing.expect(t,r.fleet.stock[0].units == 10 && r.fleet.occupants[1] == 3)
    first_completed, partial_board, partial_return := false,false,false
    for _ in 0..<600 {
        transport_test_ticks(r,1)
        evacuation_test_conserved(t,r)
        first := r.fleet.missions[0]
        if first.phase == .Unloading && first.loaded == 1 {
            partial_board = true
            testing.expect(t,r.fleet.occupants[1] == 2 && r.fleet.stock[0].units == 10)
        }
        if first.phase == .Return_Unloading && first.returned == 1 {
            partial_return = true
            testing.expect(t,r.fleet.stock[0].units == 11)
        }
        if first.phase == .Completed { first_completed = true }
    }
    testing.expect(t,partial_board && partial_return)
    testing.expect(t,first_completed && r.fleet.missions[1].phase == .Completed && r.fleet.stock[0].units == 13)
    testing.expect(t,r.fleet.available[0].units == 2 && !r.fleet.evacuation_pending[1])
}

@(test)
evacuation_missing_platform_and_full_station_do_not_delete_people :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    defer transport_test_destroy(r)
    e.capacity[0].capacity = 10
    r.game.active[2] = false
    transport_test_activate(r)
    transport_test_ticks(r,180)
    testing.expect(t,r.fleet.count == 0 && r.fleet.occupants[1] == 3)
    for subject in r.fleet.subjects[:3] { testing.expect(t,subject.destination == "H" && subject.evacuating) }
    r.game.active[2] = true
    transport_test_ticks(r,180)
    testing.expect(t,r.fleet.count == 0 && r.fleet.subjects[0].destination == "LP")
    e.capacity[0].capacity = 12
    transport_test_ticks(r,400)
    testing.expect(t,r.fleet.stock[0].units == 12 && r.fleet.occupants[1] == 1 && r.fleet.evacuation_pending[1])
    evacuation_test_conserved(t,r)
    e.capacity[0].capacity = 13
    transport_test_ticks(r,400)
    testing.expect(t,r.fleet.stock[0].units == 13 && r.fleet.occupants[1] == 0)
    evacuation_test_conserved(t,r)
}

@(test)
evacuation_committed_reactivation_and_reset_preserve_ownership :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    defer transport_test_destroy(r)
    transport_test_activate(r)
    transport_test_ticks(r,60)
    transport_test_activate(r)
    testing.expect(t,r.fleet.evacuation_pending[1] && r.fleet.evacuation_started[1] && r.fleet.count == 2)
    for mission in r.fleet.missions[:r.fleet.count] { testing.expect(t,mission.evacuation) }
    for _ in 0..<30 { dispatch_transports(&r.fleet,&r.game,r.definitions[:]) }
    testing.expect(t,r.fleet.count == 2)
    reset(&r.game,r.initial[:])
    reset_transports(&r.fleet,r.instance,r.initial[:],nil)
    testing.expect(t,r.fleet.count == 0 && r.fleet.next_landing_ticket == 0 && !r.fleet.evacuation_pending[1])
    testing.expect(t,r.fleet.last_active[1] && r.fleet.occupants[1] == 3 && r.fleet.stock[0].units == 10 && r.fleet.available[0].units == 2)
    for subject in r.fleet.subjects { testing.expect(t,!subject.evacuating && !subject.evacuation_reserved && subject.evacuation_platform == "") }
    evacuation_test_conserved(t,r)
}
