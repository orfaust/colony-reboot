package logic

import "core:testing"

// Fixture arrays live in the test's frame, never a returned helper's stack.
Transport_Test :: struct {
    definitions: [4]Building_Type,
    initial: [4]Building_Instance,
    passengers: [1]Ship_Subject,
    ships: [1]Ship,
    units: [1]Station_Ship,
    stock: [1]Station_Subject_Stock,
    instance: Station_Instance,
    game: State,
    fleet: Transport_State,
}
transport_test_init :: proc(r: ^Transport_Test, distance: f32 = 3601, handling: f32 = 0.25) {
    r.definitions = {{id="control_unit"},{id="home",residents={type="human",capacity=5},min_operative_health=0.5},{id="landing_platform"},{id="second_home",residents={type="human",capacity=5}}}
    r.initial = {{id="CU",building_id="control_unit",health=1},{id="H",building_id="home",health=1,residents_amount=f32(0)},{id="LP",building_id="landing_platform",health=1,enable_at_start=true},{id="H2",building_id="second_home",health=1}}
    r.passengers = {{subject_id="human",capacity=5}}
    r.ships = {{id="shuttle",type="transport",max_speed=3600,max_speed_hours=1,units_per_hour=handling > 0 ? 5/handling : 1e12,subjects=r.passengers[:]}}
    r.units = {{ship_id="shuttle",units=2}}
    r.stock = {{subject_id="human",units=10}}
    r.instance = {distance=distance,subjects=r.stock[:]}
    r.game = new_session(r.initial[:],r.definitions[:],context.allocator)
    r.fleet = new_transports({ships=r.units[:]},r.instance,r.ships[:],r.initial[:],nil,context.allocator,r.definitions[:])
}
transport_test_stock :: proc(r: ^Transport_Test, units: int) {
    for &subject in r.fleet.subjects { if subject.activity == .Station { subject.activity = .Removed } }
    r.fleet.stock[0].units = f32(units)
    for _ in 0..<units { add_runtime_subject(&r.fleet,{subject_id="human",activity=.Station}) }
}
transport_test_destroy :: proc(r: ^Transport_Test) {
    destroy_transports(&r.fleet,context.allocator)
    destroy(&r.game,context.allocator)
}
transport_test_activate :: proc(r: ^Transport_Test, id: string = "H") {
    toggle(&r.game,{id=id})
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
}
transport_test_ticks :: proc(r: ^Transport_Test, ticks: int) {
    for _ in 0..<ticks { step(&r.game); step_transports(&r.fleet,&r.game,r.definitions[:]) }
}

@(test)
transport_loading_landing_unloading_and_reset :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r)
    defer transport_test_destroy(&r)
    r.game.buildings[1].health = 0.2
    testing.expect(t,toggle(&r.game,{id="H"}) == .Insufficient_Health)
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
    testing.expect(t,r.fleet.count == 0)
    r.game.buildings[1].health = 1
    transport_test_activate(&r)
    testing.expect(t,r.fleet.count == 1 && r.fleet.reserved[1] == 5 && r.fleet.stock[0].units == 5)
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
    testing.expect(t,r.fleet.count == 1)
    transport_test_ticks(&r,14)
    testing.expect(t,r.fleet.missions[0].phase == .Loading && r.fleet.missions[0].travelled == 0)
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[0].phase == .Outbound)
    transport_test_ticks(&r,120)
    mission := transport_snapshot(&r.fleet,0)
    testing.expect(t,mission.phase == .Landing && mission.platform_id == "LP" && abs(mission.distance-mission.travelled-1) < 1e-8)
    testing.expect(t,r.fleet.occupants[1] == 0)
    transport_test_ticks(&r,60)
    testing.expect(t,r.fleet.missions[0].phase == .Unloading && r.fleet.missions[0].landing_progress == 1)
    transport_test_ticks(&r,15)
    testing.expect(t,r.fleet.missions[0].phase == .Taking_Off && r.fleet.missions[0].delivered == 5)
    transport_test_ticks(&r,180)
    testing.expect(t,r.fleet.missions[0].phase == .Completed && r.fleet.available[0].units == 2 && r.fleet.stock[0].units == 5)
    amount, _ := r.game.buildings[1].residents_amount.?
    testing.expect(t,amount == 5 && r.fleet.reserved[1] == 0 && r.fleet.occupants[1] == 5)
    testing.expect(t,r.stock[0].units == 10 && r.units[0].units == 2)
    reset(&r.game,r.initial[:])
    reset_transports(&r.fleet,r.instance,r.initial[:],nil)
    testing.expect(t,r.fleet.count == 0 && r.fleet.stock[0].units == 10 && r.fleet.available[0].units == 2)
}

@(test)
transport_profiles_use_ship_ramp_hours :: proc(t: ^testing.T) {
    testing.expect(t,travel_duration(3600,3600,1) == 2)
    testing.expect(t,travel_duration(7200,3600,1) == 3)
    testing.expect(t,travel_duration(900,3600,1) == 1)
    testing.expect(t,travel_duration(7200,3600,2) == 4)
    testing.expect(t,travel_duration(7200,3600,0) == 2)
    for hours in ([?]f64{0,0.25,1,2}) {
        for distance in ([?]f64{0,900,3600,7200}) {
            mission := Transport{leg_distance=distance,max_speed=3600,max_speed_hours=hours,duration=travel_duration(distance,3600,hours)}
            previous: f64
            for tick in 0..<601 {
                mission.elapsed = f64(tick)/60
                position, speed := transport_position(mission)
                testing.expect(t,position >= previous-1e-8 && position <= distance+1e-8)
                testing.expect(t,speed >= 0 && speed <= 3600)
                previous = position
            }
            testing.expect(t,previous == distance)
        }
    }
    mission := Transport{leg_distance=7200,max_speed=3600,max_speed_hours=2,duration=4,elapsed=1}
    distance, speed := transport_position(mission)
    testing.expect(t,distance == 900 && speed == 1800)
    mission.elapsed = 3
    distance, speed = transport_position(mission)
    testing.expect(t,distance == 6300 && speed == 1800)
}

@(test)
transport_cancellation_during_loading_is_exactly_once :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r)
    defer transport_test_destroy(&r)
    transport_test_activate(&r)
    transport_test_activate(&r,"H2")
    testing.expect(t,r.fleet.count == 2 && r.fleet.stock[0].units == 0)
    transport_test_activate(&r) // Toggle H off; H2's request is unaffected.
    testing.expect(t,r.fleet.reserved[1] == 0 && r.fleet.reserved[3] == 5)
    testing.expect(t,r.fleet.missions[0].phase == .Return_Unloading && r.fleet.missions[0].requested == 0)
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
    transport_test_ticks(&r,15)
    testing.expect(t,r.fleet.missions[0].phase == .Cancelled && r.fleet.stock[0].units == 5 && r.fleet.available[0].units == 1)
    transport_test_ticks(&r,10)
    testing.expect(t,r.fleet.stock[0].units == 5 && r.fleet.available[0].units == 1)
    transport_test_activate(&r)
    testing.expect(t,r.fleet.count == 3 && r.fleet.stock[0].units == 0 && r.fleet.reserved[1] == 5)
}

@(test)
transport_cancellation_brakes_and_returns_cargo :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,3601,0)
    defer transport_test_destroy(&r)
    transport_test_activate(&r)
    transport_test_ticks(&r,60)
    before := transport_snapshot(&r.fleet,0)
    testing.expect(t,abs(before.speed-3600) < 1e-6 && abs(before.travelled-1800) < 1e-6)
    transport_test_activate(&r)
    testing.expect(t,r.fleet.missions[0].phase == .Braking && r.fleet.missions[0].travelled == before.travelled)
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[0].speed < before.speed && r.fleet.missions[0].speed > 0)
    transport_test_ticks(&r,240)
    testing.expect(t,r.fleet.missions[0].phase == .Cancelled && r.fleet.missions[0].travelled == 0)
    testing.expect(t,r.fleet.stock[0].units == 10 && r.fleet.available[0].units == 2 && r.fleet.occupants[1] == 0)
}

@(test)
transport_partial_unload_cancellation_keeps_delivered_passengers :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,1,1)
    defer transport_test_destroy(&r)
    transport_test_activate(&r)
    transport_test_ticks(&r,150) // 1 h loading + 1 h landing + 0.5 h unloading.
    testing.expect(t,r.fleet.missions[0].phase == .Unloading && r.fleet.missions[0].delivered == 2)
    transport_test_activate(&r)
    testing.expect(t,r.fleet.missions[0].phase == .Taking_Off && r.fleet.reserved[1] == 0)
    transport_test_ticks(&r,121)
    testing.expect(t,r.fleet.missions[0].phase == .Cancelled && r.fleet.stock[0].units == 8 && r.fleet.occupants[1] == 2)
    testing.expect(t,r.fleet.stock[0].units+r.fleet.occupants[1] == 10)
}

@(test)
transport_cancelled_descent_reverses_without_teleport :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,1,0)
    defer transport_test_destroy(&r)
    transport_test_activate(&r)
    transport_test_ticks(&r,30)
    before := transport_snapshot(&r.fleet,0)
    testing.expect(t,before.phase == .Landing && abs(before.landing_progress-0.5) < 1e-8)
    transport_test_activate(&r)
    testing.expect(t,r.fleet.missions[0].phase == .Taking_Off && r.fleet.missions[0].landing_progress == before.landing_progress)
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[0].landing_progress < before.landing_progress)
    transport_test_ticks(&r,30)
    testing.expect(t,r.fleet.missions[0].phase == .Cancelled && r.fleet.stock[0].units == 10 && r.fleet.occupants[1] == 0)
}

@(test)
transport_tick_carries_unused_time_across_phases :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,2,0)
    defer transport_test_destroy(&r)
    r.ships[0].max_speed = 120
    r.ships[0].max_speed_hours = 0
    r.ships[0].units_per_hour = 1e12
    transport_test_activate(&r)
    transport_test_ticks(&r,1)
    // Half the tick flies the 1 km cruise leg, half advances the descent.
    testing.expect(t,r.fleet.missions[0].phase == .Landing)
    testing.expect(t,abs(r.fleet.missions[0].landing_progress-f64(1)/120) < 1e-8)
}

@(test)
transport_waits_for_platform_and_serializes_landings :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,0,0)
    defer transport_test_destroy(&r)
    r.game.active[2] = false
    transport_test_activate(&r)
    transport_test_activate(&r,"H2")
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[0].phase == .Waiting_Landing && transport_eta(r.fleet.missions[0]) < 0)
    testing.expect(t,r.fleet.occupants[1] == 0)
    r.game.active[2] = true
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.missions[0].phase == .Landing && r.fleet.missions[1].phase == .Waiting_Landing)
    transport_test_ticks(&r,180)
    testing.expect(t,r.fleet.missions[0].arrived && r.fleet.missions[1].arrived)
}

@(test)
transport_suitability_pending_and_limit :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r)
    defer transport_test_destroy(&r)
    r.passengers[0].subject_id = "robot"
    transport_test_activate(&r)
    testing.expect(t,r.fleet.count == 0)
    r.passengers[0].subject_id = "human"
    r.ships[0].max_speed = 0
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
    testing.expect(t,r.fleet.count == 0)
    r.ships[0].max_speed = 10
    r.fleet.stock[0].units = 0.5
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
    testing.expect(t,r.fleet.count == 0)
    transport_test_stock(&r,200)
    r.fleet.available[0].units = 200
    r.passengers[0].capacity = 1
    r.definitions[1].residents.capacity = 500
    dispatch_transports(&r.fleet,&r.game,r.definitions[:])
    testing.expect(t,r.fleet.count == TRANSPORT_LIMIT && r.fleet.stock[0].units == 72 && r.fleet.available[0].units == 72)
}
