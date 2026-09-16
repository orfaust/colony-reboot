package logic

import "core:testing"

@(test)
evacuation_shares_fifo_with_immigration_and_waits_for_busy_ships :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    defer transport_test_destroy(r)
    transport_test_activate(r) // Request evacuation, still cooling.
    transport_test_activate(r,"H2") // Both ships are already assigned to immigration.
    testing.expect(t,r.fleet.count == 2 && r.fleet.available[0].units == 0)
    mixed_wait := false
    for _ in 0..<1200 {
        transport_test_ticks(r,1)
        evacuation_test_conserved(t,r)
        ordinary_on_pad := false
        evacuation_waiting := false
        for mission in r.fleet.missions[:r.fleet.count] {
            if !mission.evacuation && (mission.phase == .Landing || mission.phase == .Unloading || mission.phase == .Taking_Off) { ordinary_on_pad = true }
            if mission.evacuation && mission.phase == .Waiting_Landing { evacuation_waiting = true }
        }
        if ordinary_on_pad && evacuation_waiting { mixed_wait = true }
    }
    testing.expect(t,mixed_wait && r.fleet.occupants[1] == 0 && r.fleet.occupants[3] == 5)
    testing.expect(t,r.fleet.stock[0].units == 8 && r.fleet.available[0].units == 2)
    testing.expect(t,!r.fleet.evacuation_pending[1])
}

@(test)
evacuation_log_limit_keeps_pending_people_and_ship_availability :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    defer transport_test_destroy(r)
    r.fleet.count = TRANSPORT_LIMIT
    for &mission in r.fleet.missions { mission.phase = .Completed }
    transport_test_activate(r)
    transport_test_ticks(r,240)
    testing.expect(t,r.fleet.evacuation_pending[1] && r.fleet.occupants[1] == 3)
    testing.expect(t,r.fleet.count == TRANSPORT_LIMIT && r.fleet.available[0].units == 2 && r.fleet.stock[0].units == 10)
    for subject in r.fleet.subjects[:3] { testing.expect(t,!subject.evacuation_reserved && subject.destination == "LP") }
    evacuation_test_conserved(t,r)
}
