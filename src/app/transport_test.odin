package main

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:testing"
import "../config"
import "../logic"
import "../localization"

@(test)
transport_manifest_presentation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"),allocator)
    testing.expect(t,ok)
    ships := [?]logic.Ship{{id="S",name="Shuttle",color={1,2,3}}}
    subjects := [?]logic.Subject_Type{{id="human",name_key="play",color={4,5,6}}}
    catalog := config.Catalog{ships=ships[:],subjects=subjects[:]}
    fleet := logic.Transport_State{count=1}
    fleet.missions[0] = {ship_id="S",subject_id="human",destination="H1",units=100,loaded=100,requested=100,phase=.Outbound,phase_duration=3,phase_elapsed=1,duration=3,elapsed=1,distance=7200,travelled=1800,speed=3600,max_speed=4800}
    cards := transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
    testing.expect(t,len(cards) == 1 && cards[0].ship_color == ships[0].color && cards[0].subject_color == subjects[0].color)
    testing.expect(t,strings.contains(cards[0].lines[1],"100") && strings.contains(cards[0].lines[1],"H1"))
    testing.expect(t,len(cards[0].lines) == 5)
    testing.expect(t,cards[0].lines[2] == "5400 km remaining")
    testing.expect(t,cards[0].lines[3] == "3600/4800 km/h")
    testing.expect(t,strings.contains(cards[0].lines[4],"ETA: 3 h"))
    for line in cards[0].lines { testing.expect(t,!strings.contains(line,"{")) }
    // Transport numbers round for display only, including sub-unit values.
    for sample in ([?]struct {value: f64, expected: string}{{12.2,"12"},{12.8,"13"},{0.00002,"0"},{0,"0"}}) {
        fleet.missions[0].phase = .Unloading
        fleet.missions[0].distance = sample.value
        fleet.missions[0].travelled = 0
        fleet.missions[0].speed = sample.value
        fleet.missions[0].max_speed = sample.value
        fleet.missions[0].phase_duration = sample.value
        fleet.missions[0].phase_elapsed = 0
        cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
        testing.expect(t,cards[0].lines[2] == fmt.tprintf("%s km remaining",sample.expected))
        testing.expect(t,cards[0].lines[3] == fmt.tprintf("%s/%s km/h",sample.expected,sample.expected))
        testing.expect(t,strings.contains(cards[0].lines[4],fmt.tprintf("ETA: %s h",sample.expected)))
        testing.expect(t,fleet.missions[0].speed == sample.value && fleet.missions[0].distance == sample.value)
        testing.expect(t,fleet.missions[0].phase_duration == sample.value)
    }
    fleet.missions[0].phase = .Loading
    fleet.missions[0].loaded = 2
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
    testing.expect(t,cards[0].passengers == 2 && strings.contains(cards[0].lines[1],"2"))
    fleet.missions[0].loaded = 100
    fleet.missions[0].delivered = 99
    fleet.missions[0].phase = .Unloading
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
    testing.expect(t,cards[0].passengers == 1)
    fleet.missions[0].phase = .Completed
    fleet.missions[0].requested = 0
    fleet.missions[0].delivered = 100
    fleet.missions[0].arrived = true
    fleet.missions[0].elapsed = 3
    fleet.missions[0].speed = 0
    fleet.missions[0].travelled = 0
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
    testing.expect(t,len(cards) == 0 && transport_box_count(&fleet) == 0)
    for phase in logic.Transport_Phase {
        fleet.missions[0].phase = phase
        cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
        expected := phase == .Completed || phase == .Cancelled || phase == .Return_Unloading ? 0 : 1
        testing.expect(t,len(cards) == expected && transport_box_count(&fleet) == expected)
        if len(cards) > 0 { for line in cards[0].lines { testing.expect(t,!strings.contains(line,"{")) } }
    }
    fleet.missions[0].phase = .Waiting_Landing
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
    testing.expect(t,strings.contains(cards[0].lines[4],text.entries["transport_eta_unknown"]))
    testing.expect(t,!strings.has_suffix(cards[0].lines[4]," h"))
    // An ordinary request carries a stable approval id and no misleading ETA.
    fleet.missions[0].phase = .Awaiting_Approval
    fleet.missions[0].id = 42
    fleet.missions[0].loaded = 0
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0)
    testing.expect(t,cards[0].approve_id == 42)
    testing.expect(t,cards[0].lines[4] == text.entries["transport_awaiting_approval"])
    testing.expect(t,!strings.contains(cards[0].lines[4],"ETA"))
    fleet.missions[0].id = 0
    fleet.missions[0].phase = .Waiting_Landing
    fleet.missions[0].loaded = 100
    // Finished history cannot occupy a visible slot; stale scroll clamps after removal.
    fleet.count = 4
    fleet.missions[1] = fleet.missions[0]
    fleet.missions[1].phase = .Completed
    fleet.missions[2] = fleet.missions[0]
    fleet.missions[2].ship_id = "S2"
    fleet.missions[2].phase = .Returning
    fleet.missions[3] = fleet.missions[0]
    fleet.missions[3].ship_id = "S3"
    fleet.missions[3].phase = .Cancelled
    all_cards := transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0,true)
    testing.expect(t,len(all_cards) == 2)
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},100)
    testing.expect(t,len(cards) == 1 && transport_box_count(&fleet) == 2)
    testing.expect(t,strings.contains(cards[0].lines[4],text.entries["transport_returning"]))
    fleet.missions[2].phase = .Return_Unloading
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},100)
    testing.expect(t,len(cards) == 1 && transport_box_count(&fleet) == 1)
    testing.expect(t,strings.contains(cards[0].lines[4],text.entries["transport_waiting_landing"]))
}

// One departure box per ship: concurrent missions of the same ship collapse, and a
// pending request always represents its ship so it stays approvable.
@(test)
transport_boxes_group_by_ship_with_pending_priority :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"),mem.dynamic_arena_allocator(&arena))
    testing.expect(t,ok)
    ships := [?]logic.Ship{{id="S",name="Shuttle"},{id="S2",name="Second"}}
    catalog := config.Catalog{ships=ships[:]}
    fleet := logic.Transport_State{count=3}
    fleet.missions[0] = {id=1,ship_id="S",phase=.Outbound,destination="H1",units=1,requested=1,loaded=1,distance=10}
    fleet.missions[1] = {id=2,ship_id="S",phase=.Awaiting_Approval,destination="H2",units=2,requested=2,distance=10}
    fleet.missions[2] = {id=3,ship_id="S2",phase=.Loading,destination="H3",units=1,requested=1,distance=10}
    testing.expect(t,transport_box_count(&fleet) == 2)
    cards := transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0,true)
    testing.expect(t,len(cards) == 2)
    // Ship S is represented by its pending request, so the rocket button is reachable.
    testing.expect(t,cards[0].approve_id == 2)
    testing.expect(t,cards[1].approve_id == 0)
    testing.expect(t,strings.contains(cards[1].lines[1],"H3"))
    // Once approved, the earliest mission of the ship takes over the single box.
    fleet.missions[1].phase = .Loading
    cards = transport_cards(&fleet,catalog,text.entries,{16,64,300,176},0,true)
    testing.expect(t,len(cards) == 2)
    testing.expect(t,cards[0].approve_id == 0)
    testing.expect(t,strings.contains(cards[0].lines[1],"H1"))
}
