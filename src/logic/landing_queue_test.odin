package logic

import "core:testing"

@(test)
landing_queue_fifo_holds_cargo_and_resumes_after_takeoff :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,0,0)
    defer transport_test_destroy(&r)
    r.passengers[0].capacity = 1
    r.definitions[1].residents = {type="human",capacity=3}
    r.fleet.available[0].units = 3
    r.game.active[2] = false
    transport_test_activate(&r)
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.count == 3)
    for mission in r.fleet.missions[:3] {
        testing.expect(t,mission.phase == .Waiting_Landing && mission.loaded == 1 && mission.delivered == 0)
        testing.expect(t,mission.platform_id == "" && transport_eta(mission) == -1)
    }
    // Deliberately reverse storage order: admission must use arrival tickets.
    r.fleet.missions[0],r.fleet.missions[2] = r.fleet.missions[2],r.fleet.missions[0]
    r.game.active[2] = true
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[2].phase == .Landing)
    testing.expect(t,r.fleet.missions[0].phase == .Waiting_Landing && r.fleet.missions[1].phase == .Waiting_Landing)
    testing.expect(t,r.fleet.missions[0].holding_platform_id == "LP" && r.fleet.missions[0].platform_id == "")
    last_ticket: u64
    for _ in 0..<400 {
        transport_test_ticks(&r,1)
        busy := 0
        for mission in r.fleet.missions[:3] {
            if mission.phase == .Landing || mission.phase == .Unloading || mission.phase == .Taking_Off {
                busy += 1
                testing.expect(t,mission.landing_ticket >= last_ticket)
                last_ticket = mission.landing_ticket
            }
            if mission.phase == .Waiting_Landing {
                testing.expect(t,mission.delivered == 0 && transport_cargo(mission) == 1 && mission.speed == 0)
                testing.expect(t,mission.travelled == 0 && mission.platform_id == "")
            }
        }
        testing.expect(t,busy <= 1)
    }
    testing.expect(t,last_ticket == 3 && r.fleet.occupants[1] >= 3)
}

@(test)
landing_queue_withdrawal_does_not_block_followers :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,0,0)
    defer transport_test_destroy(&r)
    r.game.active[2] = false
    transport_test_activate(&r)
    transport_test_activate(&r,"H2")
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[0].landing_ticket < r.fleet.missions[1].landing_ticket)
    transport_test_activate(&r) // Withdraw the oldest request while holding.
    r.game.active[2] = true
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[1].phase == .Landing && r.fleet.missions[1].platform_id == "LP")
    testing.expect(t,r.fleet.missions[0].delivered == 0)
    reset_transports(&r.fleet,r.instance,r.initial[:],nil)
    testing.expect(t,r.fleet.next_landing_ticket == 0 && r.fleet.count == 0)
}
