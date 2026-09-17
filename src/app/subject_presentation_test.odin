package main

import c "../contracts"
import "../config"
import "../logic"
import "../localization"
import "../render"
import "../ui"
import "core:mem"
import "core:strings"
import "core:testing"

// Task-11 headless presentation tests: formatting, decimals only when useful, empty
// states, long localized text, event ordering, and frame-allocator-only memory.
// The window, GPU and real font are never initialized here.

presentation_text_fixture :: proc(t: ^testing.T, arena: ^mem.Dynamic_Arena) -> localization.Text {
    text, ok := localization.decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), mem.dynamic_arena_allocator(arena))
    testing.expect(t, ok)
    text.entries["fixture_subject"] = "Human"
    return text
}

@(test)
subject_info_formatting_and_empty_states :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text := presentation_text_fixture(t, &arena)
    definition := logic.Subject_Type{id="human", name_key="fixture_subject", work_time=12, rest_time=12}
    // Whole percentages drop decimals; fractional health keeps only what is useful.
    view := c.Subject_Snapshot{id=3, subject_id="human", health=0.4, work_phase=.Extra_Working, medical=.Hospitalized, work_hours=12.5}
    lines := subject_info_lines(view, nil, "Human", definition, text, config.Catalog{})
    for expected in ([?]string{"Human #3", "Health: 40%", "Phase: Overtime", "Role: Unassigned", "Assigned: Unassigned", "Work 12.5/12 h | Rest 0/12 h | Idle 0 h", "Medical: Hospitalized", text.entries["subject_info_no_needs"]}) {
        found := false
        for line in lines { if line == expected { found = true } }
        testing.expect(t, found, expected)
    }
    view.health = 0.875
    view.work_phase = .Working
    view.medical = .None
    lines = subject_info_lines(view, nil, "Human", definition, text, config.Catalog{})
    for expected in ([?]string{"Health: 87.5%", "Phase: Working", "Medical: None"}) {
        found := false
        for line in lines { if line == expected { found = true } }
        testing.expect(t, found, expected)
    }
}

// The event adapter drains the queue in sequence order and leaves it empty, so a
// later transition can never be dropped by a full log.
@(test)
event_notices_follow_sequence_order_and_drain :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text := presentation_text_fixture(t, &arena)
    definitions := [?]logic.Building_Type{{id="greenhouse",name_key="building_greenhouse_name"}}
    instances := [?]logic.Building_Instance{{id="B1",building_id="greenhouse"}}
    catalog := config.Catalog{buildings=definitions[:]}
    notices := build_building_notices(BUILDING_NOTICE_KEYS,instances[:],catalog,text.entries,mem.dynamic_arena_allocator(&arena))
    shed := build_power_shed_notices(text.entries["notice_power_shed"],notices.identities,instances[:],mem.dynamic_arena_allocator(&arena))
    game: logic.State
    testing.expect(t, logic.push_event(&game.events, .Staffing_Lost, building_id="B1"))
    testing.expect(t, logic.push_event(&game.events, .Medical_Evacuation, subject_id=7))
    testing.expect(t, logic.push_event(&game.events, .Subject_Died, subject_id=8))
    scene: ui.Scene_State
    publish_event_notices(&scene,&game,text,notices,&shed)
    testing.expect(t, scene.notice_count == 3)
    // The staffing-loss message names the localized type name plus the instance ID.
    testing.expect(t, scene.notices[0].text == building_notice_text(notices,"notice_staffing_lost","B1",""))
    testing.expect(t, strings.contains(scene.notices[0].text,"Greenhouse"))
    testing.expect(t, strings.contains(scene.notices[0].text,"(B1)"))
    testing.expect(t, !strings.contains(scene.notices[0].text,"{name}") && !strings.contains(scene.notices[0].text,"{id}"))
    testing.expect(t, scene.notices[1].text == text.entries["notice_medical_evacuation"])
    testing.expect(t, scene.notices[2].text == text.entries["notice_subject_died"])
    testing.expect(t, len(logic.pending_events(&game.events)) == 0)
    // A second call with no new transitions adds nothing.
    publish_event_notices(&scene,&game,text,notices,&shed)
    testing.expect(t, scene.notice_count == 3)
}

// The inspector and notice paths must not allocate from the session/heap allocator;
// they build frame-temporary strings only.
@(test)
presentation_uses_frame_memory_only :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text := presentation_text_fixture(t, &arena)
    definition := logic.Subject_Type{id="human", name_key="fixture_subject", work_time=12, rest_time=12}
    view := c.Subject_Snapshot{id=9, subject_id="human", health=0.5, need_count=1}
    view.needs[0] = {resource_id="water", fulfillment=0.5, shortage_hours=3}
    subjects := [?]logic.Runtime_Subject{{id=9, residence="home", activity=.Inside, health=0.5, phase=.Working}}
    coverages: [3]c.Staffing_Coverage
    coverages[0] = {role_id=.worker, required_slots=1, covered_slots=0}
    game: logic.State
    testing.expect(t, logic.push_event(&game.events, .Staffing_Restored, building_id="home"))
    // The grouped power-shed notice composes into preallocated ring storage too.
    testing.expect(t, logic.push_event(&game.events, .Power_Shed, building_id="home"))
    definitions := [?]logic.Building_Type{{id="home",name_key="building_humans_residence_name"}}
    instances := [?]logic.Building_Instance{{id="home",building_id="home"}}
    notices := build_building_notices(BUILDING_NOTICE_KEYS,instances[:],config.Catalog{buildings=definitions[:]},text.entries,mem.dynamic_arena_allocator(&arena))
    shed := build_power_shed_notices(text.entries["notice_power_shed"],notices.identities,instances[:],mem.dynamic_arena_allocator(&arena))

    backing := context.allocator
    tracking: mem.Tracking_Allocator
    mem.tracking_allocator_init(&tracking, backing)
    defer mem.tracking_allocator_destroy(&tracking)
    context.allocator = mem.tracking_allocator(&tracking)
    defer context.allocator = backing
    scene: ui.Scene_State
    for _ in 0..<8 {
        _ = subject_info_lines(view, nil, "Human", definition, text, config.Catalog{})
        _ = building_info_lines(c.Building_Snapshot{id="home"}, logic.Building_Type{}, text, {}, config.Catalog{}, subjects[:], coverages[:], nil, .Unstaffed, nil)
        publish_event_notices(&scene,&game,text,notices,&shed)
        free_all(context.temp_allocator)
    }
    testing.expectf(t, len(tracking.allocation_map) == 0, "presentation allocated %d long-lived block(s)", len(tracking.allocation_map))
    testing.expect(t, len(tracking.bad_free_array) == 0)
}

// Long localized text is preserved and wraps at word boundaries through the shared
// measurement contract; it is never truncated or shrunk to fit.
app_test_advance :: proc(r: rune) -> f32 { return 10 }

@(test)
long_localized_subject_text_wraps_without_loss :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text := presentation_text_fixture(t, &arena)
    definition := logic.Subject_Type{id="human", name_key="fixture_subject", work_time=12, rest_time=12}
    long_name := "Human With A Very Long Localized Name That Must Wrap"
    view := c.Subject_Snapshot{id=5, subject_id="human", health=1, work_phase=.Working}
    lines := subject_info_lines(view, nil, long_name, definition, text, config.Catalog{})
    identity := lines[0]
    testing.expect(t, strings.contains(identity,long_name))
    rows := render.wrap_info_text(lines, 80, app_test_advance)
    testing.expect(t, len(rows) > len(lines))
    // A long token may split at a character boundary, so compare the combined text
    // while ignoring the whitespace the wrapper trims between rows.
    builder: strings.Builder
    strings.builder_init(&builder, context.temp_allocator)
    for row in rows { strings.write_string(&builder, row.text) }
    stripped, _ := strings.replace_all(strings.to_string(builder), " ", "", context.temp_allocator)
    expected_stripped, _ := strings.replace_all(identity, " ", "", context.temp_allocator)
    testing.expect(t, strings.contains(stripped, expected_stripped))
    for row in rows { testing.expect(t, len(row.text) > 0 && row.text[0] != ' ') }
}
