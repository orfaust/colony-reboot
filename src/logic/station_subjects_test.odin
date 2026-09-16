package logic

import "core:math"
import "core:testing"

@(test)
station_subject_rates_keep_whole_stock_and_reset :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r)
    defer transport_test_destroy(&r)
    capacities := [?]Station_Subject{{subject_id="human",capacity=12.5}}
    r.fleet.station.subjects = capacities[:]
    transport_test_stock(&r,0)
    r.fleet.stock[0].units_per_hour = 0.5
    for i in 0..<120 {
        transport_test_ticks(&r,1)
        testing.expect(t,f64(r.fleet.stock[0].units) == math.floor(f64(r.fleet.stock[0].units)))
        if i < 119 { testing.expect(t,r.fleet.stock[0].units == 0) }
    }
    testing.expect(t,r.fleet.stock[0].units == 1)
    r.fleet.stock[0].units_per_hour = 120
    transport_test_ticks(&r,60)
    testing.expect(t,r.fleet.stock[0].units == 12 && r.fleet.stock_fraction[0] == 0)
    transport_test_stock(&r,11)
    r.fleet.stock[0].units_per_hour = 0.5
    transport_test_ticks(&r,60)
    testing.expect(t,r.fleet.stock[0].units == 11)
    reset_transports(&r.fleet,r.instance,r.initial[:],nil)
    testing.expect(t,r.fleet.stock_fraction[0] == 0 && r.fleet.stock[0].units == 10)
    r.fleet.stock[0].units_per_hour = -0.5
    transport_test_ticks(&r,120)
    testing.expect(t,r.fleet.stock[0].units == 9)
    r.fleet.stock[0].units_per_hour = -6000
    transport_test_ticks(&r,10)
    testing.expect(t,r.fleet.stock[0].units == 0 && r.fleet.stock_fraction[0] == 0)
    testing.expect(t,r.stock[0].units == 10 && r.stock[0].units_per_hour == 0)
}

@(test)
station_growth_reserves_capacity_for_cancelled_cargo :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r)
    defer transport_test_destroy(&r)
    capacities := [?]Station_Subject{{subject_id="human",capacity=10}}
    r.fleet.station.subjects = capacities[:]
    r.fleet.stock[0].units_per_hour = 600
    transport_test_activate(&r)
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.stock[0].units == 5)
    transport_test_activate(&r)
    transport_test_ticks(&r,15)
    testing.expect(t,r.fleet.stock[0].units == 10 && r.fleet.available[0].units == 2)
}

@(test)
replenishment_dispatches_and_successful_ship_is_reusable :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,1,0)
    defer transport_test_destroy(&r)
    capacities := [?]Station_Subject{{subject_id="human",capacity=10}}
    r.fleet.station.subjects = capacities[:]
    transport_test_stock(&r,0)
    r.fleet.stock[0].units_per_hour = 60
    r.fleet.available[0].units = 1
    r.game.buildings[1].position.x = 20
    transport_test_activate(&r)
    testing.expect(t,r.fleet.count == 0)
    transport_test_ticks(&r,1)
    testing.expect(t,r.fleet.count == 1 && r.fleet.missions[0].units == 1 && r.fleet.stock[0].units == 0)
    transport_test_ticks(&r,60)
    testing.expect(t,r.fleet.missions[0].phase == .Taking_Off && r.fleet.missions[0].arrived)
    index := r.fleet.missions[0].manifest[0]
    id := r.fleet.subjects[index].id
    first, found := subject_snapshot(&r.fleet,id)
    testing.expect(t,found && first.activity == .Waiting)
    transport_test_ticks(&r,60)
    testing.expect(t,r.fleet.missions[0].phase == .Completed && r.fleet.count == 2)
    testing.expect(t,r.fleet.missions[1].units == 4 && r.fleet.occupants[1] == 1)
    later, _ := subject_snapshot(&r.fleet,id)
    testing.expect(t,later.activity == .Moving && later.position.x > first.position.x)
    // Completed ship missions must not freeze pedestrians or duplicate residents.
    transport_test_ticks(&r,600)
    arrived, _ := subject_snapshot(&r.fleet,id)
    testing.expect(t,arrived.activity == .Inside && r.fleet.occupants[1] == 5)
}

@(test)
walking_individual_commands_and_identity :: proc(t: ^testing.T) {
    r: Transport_Test
    transport_test_init(&r,1,0)
    defer transport_test_destroy(&r)
    r.game.buildings[1].position = {20,0}
    r.game.buildings[3].position = {0,20}
    transport_test_activate(&r)
    ids := [2]int{r.fleet.missions[0].manifest[0],r.fleet.missions[0].manifest[1]}
    first_id := r.fleet.subjects[ids[0]].id
    second_id := r.fleet.subjects[ids[1]].id
    testing.expect(t,first_id != second_id)
    testing.expect(t,move_subject(&r.fleet,&r.game,{first_id,"H2"}) == .Unavailable)
    transport_test_ticks(&r,90)
    first, _ := subject_snapshot(&r.fleet,first_id)
    second, _ := subject_snapshot(&r.fleet,second_id)
    testing.expect(t,first.activity == .Moving && second.activity == .Moving && first.position.x > second.position.x)
    testing.expect(t,move_subject(&r.fleet,&r.game,{first_id,"missing"}) == .Unknown_Destination)
    testing.expect(t,move_subject(&r.fleet,&r.game,{first_id,"H2"}) == .Applied)
    transport_test_ticks(&r,1)
    moved, _ := subject_snapshot(&r.fleet,first_id)
    unchanged, _ := subject_snapshot(&r.fleet,second_id)
    testing.expect(t,moved.destination == "H2" && moved.position.y > first.position.y)
    testing.expect(t,unchanged.destination == "H" && unchanged.position.y == 0)
    testing.expect(t,r.fleet.occupants[1] == 5)
}
