package logic

import "core:testing"

@(test)
inactive_pickup_pad_does_not_block_other_pads :: proc(t: ^testing.T) {
    e: Evacuation_Test
    evacuation_test_init(&e)
    r := &e.base
    initial: [5]Building_Instance
    copy(initial[:4],r.initial[:])
    initial[4] = {id="LP2",building_id="landing_platform",position={0,4},health=1,enable_at_start=true}
    station := r.fleet.station
    transport_test_destroy(r)
    r.units[0].units = 3
    r.game = new_session(initial[:],r.definitions[:],context.allocator)
    r.game.timing[1].cooldown_hours = 1
    r.fleet = new_transports(station,r.instance,r.ships[:],initial[:],nil,context.allocator,r.definitions[:])
    defer transport_test_destroy(r)
    transport_test_activate(r)
    transport_test_ticks(r,60)
    testing.expect(t,r.fleet.count == 2 && r.fleet.missions[0].pickup_platform_id == "LP")
    r.game.active[2] = false
    transport_test_activate(r,"H2")
    transport_test_ticks(r,61)
    testing.expect(t,r.fleet.missions[0].phase == .Waiting_Landing && r.fleet.missions[1].phase == .Waiting_Landing)
    testing.expect(t,r.fleet.missions[2].phase == .Landing && r.fleet.missions[2].platform_id == "LP2")
    for subject in r.fleet.subjects[:3] { testing.expect(t,subject.evacuation_platform == "LP" && subject.residence == "H") }
    r.game.active[2] = true
    transport_test_ticks(r,1)
    testing.expect(t,r.fleet.missions[0].phase == .Landing && r.fleet.missions[0].platform_id == "LP")
    testing.expect(t,r.fleet.missions[1].phase == .Waiting_Landing)
}
