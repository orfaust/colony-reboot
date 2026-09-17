package main

import "../config"
import "../logic"
import "../localization"
import "../ui"
import c "../contracts"
import "core:mem"
import "core:strings"
import "core:testing"

// Convention regression: a notice about a specific building names its localized type
// name plus its instance ID, never the short catalog `code`. Any new building-specific
// template must declare `{name}` and `{id}` and is composed once per load, so no notice
// allocates per event or shows a raw placeholder.
@(test)
building_notice_templates_compose_per_name_and_instance :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), mem.dynamic_arena_allocator(&arena))
    testing.expect(t, ok)
    for key in BUILDING_NOTICE_KEYS {
        testing.expectf(t, strings.contains(text.entries[key],"{name}"), key)
        testing.expectf(t, strings.contains(text.entries[key],"{id}"), key)
        testing.expectf(t, !strings.contains(text.entries[key],"{code}"), key)
    }
    definitions := [?]logic.Building_Type{{id="water_collector",name_key="building_water_collector_name"}}
    instances := [?]logic.Building_Instance{{id="WC1",building_id="water_collector"}}
    notices := build_building_notices(BUILDING_NOTICE_KEYS,instances[:],config.Catalog{buildings=definitions[:]},text.entries,mem.dynamic_arena_allocator(&arena))
    for key in BUILDING_NOTICE_KEYS {
        message, found := notices.messages[{key,"WC1"}]
        testing.expectf(t, found && strings.contains(message,"Water Collector") && strings.contains(message,"(WC1)"), key)
        testing.expectf(t, !strings.contains(message,"{name}") && !strings.contains(message,"{id}"), key)
        testing.expect(t, building_notice_text(notices,key,"WC1","fallback") == message)
    }
    // An unknown instance falls back instead of inventing an identity.
    testing.expect(t, building_notice_text(notices,"notice_staffing_lost","missing","fallback") == "fallback")
    // The immediate toggle-feedback path also publishes the composed, specific text.
    scene: ui.Scene_State
    show_building_notice(&scene,notices,"notice_insufficient_power","WC1",text.entries["notice_insufficient_power"])
    testing.expect(t, scene.notice_count == 1 && strings.contains(scene.notices[0].text,"Water Collector"))
    testing.expect(t, strings.contains(scene.notices[0].text,"(WC1)"))
    testing.expect(t, !strings.contains(scene.notices[0].text,"{name}") && !strings.contains(scene.notices[0].text,"{id}"))
}

// The grouped power-shed notice is one notice per fixed tick, lists every affected
// building in shed order using the composed "Localized Name (ID)" identity, and never
// leaks the {buildings} placeholder.
@(test)
grouped_power_shed_notice_lists_every_shed_building_in_order :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), allocator)
    testing.expect(t, ok)
    definitions := [?]logic.Building_Type{
        {id="water_collector",name_key="building_water_collector_name"},
        {id="greenhouse",name_key="building_greenhouse_name"},
    }
    instances := [?]logic.Building_Instance{
        {id="WC1",building_id="water_collector"},
        {id="GH1",building_id="greenhouse"},
    }
    catalog := config.Catalog{buildings=definitions[:]}
    notices := build_building_notices(BUILDING_NOTICE_KEYS,instances[:],catalog,text.entries,allocator)
    shed := build_power_shed_notices(text.entries["notice_power_shed"],notices.identities,instances[:],allocator)
    game: logic.State
    testing.expect(t, logic.push_event(&game.events, .Staffing_Lost, building_id="WC1"))
    testing.expect(t, logic.push_event(&game.events, .Power_Shed, building_id="GH1"))
    testing.expect(t, logic.push_event(&game.events, .Power_Shed, building_id="WC1"))
    scene: ui.Scene_State
    publish_event_notices(&scene,&game,text,notices,&shed)
    // One grouped notice, appended after the non-grouped transitions of the tick.
    testing.expect(t, scene.notice_count == 2, "all sheds of one tick must group into one notice")
    grouped := scene.notices[1].text
    testing.expect(t, strings.contains(grouped,"Greenhouse (GH1), Water Collector (WC1)"), grouped)
    testing.expect(t, !strings.contains(grouped,"{buildings}"))
    testing.expect(t, len(logic.pending_events(&game.events)) == 0)
    // A tick with no sheds adds nothing.
    publish_event_notices(&scene,&game,text,notices,&shed)
    testing.expect(t, scene.notice_count == 2)
    // Production transitions use the same per-entity identity as the other notices.
    testing.expect(t, logic.push_event(&game.events, .Production_Blocked, building_id="GH1"))
    testing.expect(t, logic.push_event(&game.events, .Production_Resumed, building_id="GH1"))
    publish_event_notices(&scene,&game,text,notices,&shed)
    testing.expect(t, scene.notice_count == 4)
    for notice in scene.notices[:scene.notice_count] {
        testing.expect(t, !strings.contains(notice.text,"{name}") && !strings.contains(notice.text,"{id}") && !strings.contains(notice.text,"{buildings}"), notice.text)
    }
}

// The grouped notice ring keeps ui.NOTICE_CAPACITY distinct buffers: a buffer is only
// reused after that many newer grouped notices, and the bounded notice log can never
// hold more, so a visible shed notice always shows the text it was composed with.
@(test)
power_shed_ring_reuses_a_buffer_only_after_the_notice_log_capacity :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), allocator)
    testing.expect(t, ok)
    definitions := [?]logic.Building_Type{{id="water_collector",name_key="building_water_collector_name"}}
    instances := [?]logic.Building_Instance{{id="WC1",building_id="water_collector"}}
    notices := build_building_notices(BUILDING_NOTICE_KEYS,instances[:],config.Catalog{buildings=definitions[:]},text.entries,allocator)
    shed := build_power_shed_notices(text.entries["notice_power_shed"],notices.identities,instances[:],allocator)
    events := [?]c.Sim_Event{{kind=.Power_Shed,building_id="WC1"}}
    template := text.entries["notice_power_shed"]
    first := compose_power_shed_notice(&shed,template,notices.identities,events[:])
    second := compose_power_shed_notice(&shed,template,notices.identities,events[:])
    testing.expect(t, first == second && first == "Insufficient power: automatic shutdown of Water Collector (WC1).")
    testing.expect(t, raw_data(first) != raw_data(second), "distinct buffers")
    for _ in 2..<ui.NOTICE_CAPACITY { _ = compose_power_shed_notice(&shed,template,notices.identities,events[:]) }
    reused := compose_power_shed_notice(&shed,template,notices.identities,events[:])
    testing.expect(t, raw_data(reused) == raw_data(first), "buffer 0 is reused only after NOTICE_CAPACITY grouped notices")
}

// End-to-end adaptation: the automatic load-shedding step queues one event per shed
// building and the application turns the whole tick into a single localized notice
// with the composed identities, in shed order.
@(test)
load_shedding_through_the_event_queue_produces_one_grouped_notice :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), allocator)
    testing.expect(t, ok)
    text.entries["fixture_workshop"] = "Workshop"
    text.entries["fixture_factory"] = "Factory"
    // Power attributes are mutually exclusive: one generator, two consumers.
    definitions := [?]logic.Building_Type{
        {id="control_unit"},
        {id="solar",power_output_kw=30},
        {id="workshop",power_need_kw=15,name_key="fixture_workshop"},
        {id="factory",power_need_kw=10,name_key="fixture_factory"},
    }
    initial := [?]logic.Building_Instance{
        {id="CU1",building_id="control_unit",health=1,enable_at_start=true},
        {id="SP1",building_id="solar",health=1,enable_at_start=true},
        {id="WS1",building_id="workshop",health=1},
        {id="F1",building_id="factory",health=1},
    }
    game := logic.new_session(initial[:],definitions[:],allocator)
    testing.expect(t, logic.toggle(&game,{id="WS1"}) == .Applied)
    testing.expect(t, logic.toggle(&game,{id="F1"}) == .Applied)
    testing.expect(t, logic.balance(&game).available_kw == 5)
    // The generator's output collapses; the balance is negative in the same tick.
    game.level[1] = 0
    testing.expect(t, logic.balance(&game).available_kw == -25)
    logic.step_load_shedding(&game)
    testing.expect(t, logic.balance(&game).available_kw == 0)
    notices := build_building_notices(BUILDING_NOTICE_KEYS,initial[:],config.Catalog{buildings=definitions[:]},text.entries,allocator)
    shed := build_power_shed_notices(text.entries["notice_power_shed"],notices.identities,initial[:],allocator)
    scene: ui.Scene_State
    publish_event_notices(&scene,&game,text,notices,&shed)
    testing.expect(t, scene.notice_count == 1, "one notice for all sheds of the tick")
    testing.expect(t, strings.contains(scene.notices[0].text,"Workshop (WS1), Factory (F1)"), scene.notices[0].text)
    testing.expect(t, len(logic.pending_events(&game.events)) == 0)
}
