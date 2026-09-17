package main

import "core:mem"
import "core:strings"
import "core:testing"
import "../config"
import "../logic"
import "../localization"

@(test)
evacuation_cards_show_actual_boarding_and_correct_trip_direction :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"),mem.dynamic_arena_allocator(&arena))
    testing.expect(t,ok)
    fleet := logic.Transport_State{count=1,station={name="Orbital"}}
    fleet.missions[0] = {evacuation=true,phase=.Outbound,destination="H",units=3,distance=100,travelled=20,handling_rate=2}
    cards := transport_cards(&fleet,config.Catalog{},text.entries,{16,64,300,176},0)
    testing.expect(t,cards[0].passengers == 0 && strings.contains(cards[0].lines[1],"Orbital"))
    testing.expect(t,cards[0].lines[2] == "80 km remaining")
    fleet.missions[0].phase = .Unloading
    fleet.missions[0].loaded = 1
    cards = transport_cards(&fleet,config.Catalog{},text.entries,{16,64,300,176},0)
    testing.expect(t,cards[0].passengers == 1 && strings.contains(cards[0].lines[4],text.entries["transport_loading"]))
    testing.expect(t,strings.contains(cards[0].lines[4],text.entries["transport_eta_unknown"]))
    fleet.missions[0].phase = .Returning
    fleet.missions[0].arrived = true
    cards = transport_cards(&fleet,config.Catalog{},text.entries,{16,64,300,176},0)
    testing.expect(t,cards[0].lines[2] == "20 km remaining" && cards[0].passengers == 1)
}
