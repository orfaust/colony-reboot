package main

import "core:fmt"
import "core:mem"
import "core:strings"
import c "../contracts"
import "../config"
import "../logic"
import "../localization"
import "../ui"

// Player-facing notices about a specific building name it by its localized type name
// and its level instance ID (for example "Meals Factory (MF1)"), never by a generic
// "a building"/"this building" phrase and never by the short catalog `code`. Each key
// below is precomposed per building instance at load time so the bounded notice log
// never allocates per event and every notice keeps borrowing persistent storage.
BUILDING_NOTICE_KEY_COUNT :: 8
BUILDING_NOTICE_KEYS :: [BUILDING_NOTICE_KEY_COUNT]string{
    "notice_staffing_lost", "notice_staffing_restored",
    "notice_insufficient_power", "notice_insufficient_health",
    "notice_always_on_locked", "notice_generator_required",
    "notice_production_blocked", "notice_production_resumed",
}
// One composed template for one building instance; `name` is the localized building
// type name and `id` the instance ID in the level, never the catalog code.
Notice_Target :: struct { key, building_id: string }
Building_Notices :: struct {
    messages: map[Notice_Target]string,
    // Short per-instance identity ("Meals Factory (MF1)"), precomposed once per load
    // for the grouped power-shed notice, which lists runtime state instead of a
    // single building.
    identities: map[string]string,
}

// Localization key for one edge-triggered simulation event. The mapping is total so
// every published transition has exactly one player-facing message. Grouped kinds
// (Power_Shed) return an empty key and are composed by publish_event_notices instead.
event_notice_key :: proc(kind: c.Sim_Event_Kind) -> string {
    switch kind {
    case .Staffing_Lost: return "notice_staffing_lost"
    case .Staffing_Restored: return "notice_staffing_restored"
    case .Production_Blocked: return "notice_production_blocked"
    case .Production_Resumed: return "notice_production_resumed"
    case .Power_Shed: return ""
    case .Medical_Evacuation: return "notice_medical_evacuation"
    case .Medical_Return: return "notice_medical_return"
    case .Subject_Died: return "notice_subject_died"
    }
    return ""
}

// Composes the per-building variants of every template that names the building.
// `{name}` is the localized building type name and `{id}` the level instance ID, so
// the short catalog `code` is never used for notice identity. Composing per event
// would allocate on rare paths and force the notice log to own memory; precomposing
// once per load keeps notices borrowing arena/localization text.
build_building_notices :: proc(keys: [BUILDING_NOTICE_KEY_COUNT]string, buildings: []logic.Building_Instance, catalog: config.Catalog, texts: map[string]string, allocator: mem.Allocator) -> Building_Notices {
    notices: Building_Notices
    notices.messages = make(map[Notice_Target]string,len(keys)*len(buildings),allocator)
    notices.identities = make(map[string]string,len(buildings),allocator)
    for building in buildings {
        definition, found := config.find_building(catalog,building.building_id)
        if !found { continue }
        name := texts[definition.name_key]
        notices.identities[building.id] = fmt.aprintf("%s (%s)",name,building.id,allocator=allocator)
        for key in keys {
            named, _ := strings.replace_all(texts[key],"{name}",name,allocator)
            notices.messages[{key,building.id}], _ = strings.replace_all(named,"{id}",building.id,allocator)
        }
    }
    return notices
}

// Composed text for one building, or the provided template when the instance is
// unknown (a programmer-invariant path; validated levels always provide the id).
building_notice_text :: proc(notices: Building_Notices, key, building_id, fallback: string) -> string {
    if specific, found := notices.messages[{key,building_id}]; found { return specific }
    return fallback
}

// Grouped power-shed notice storage.
//
// The grouped notice is the only notice whose text depends on runtime state (the
// set of buildings shed in a tick), so it cannot be precomposed per entity. This
// ring instead owns POWER_SHED_TEXT_SLOTS fixed-size buffers of the worst-case
// joined length for the loaded level, allocated once at load from persistent arena
// storage. The i-th grouped notice composes into buffer i % POWER_SHED_TEXT_SLOTS,
// so a buffer is only reused after POWER_SHED_TEXT_SLOTS newer notices; because the
// notice log itself keeps at most ui.NOTICE_CAPACITY entries, a notice still
// visible can never observe overwritten text. Composing allocates nothing.
POWER_SHED_TEXT_SLOTS :: ui.NOTICE_CAPACITY
Power_Shed_Notices :: struct {
    buffer: []u8, // POWER_SHED_TEXT_SLOTS concatenated buffers of `capacity` bytes.
    capacity: int, // Worst-case joined length for this level's buildings.
    next: int,
}

// Sizes the ring from the template and the loaded building identities: the template
// once, every identity once, and one ", " separator between consecutive entries.
build_power_shed_notices :: proc(template: string, identities: map[string]string, buildings: []logic.Building_Instance, allocator: mem.Allocator) -> Power_Shed_Notices {
    worst := len(template)+1
    for building in buildings {
        if identity, found := identities[building.id]; found { worst += len(identity) } else { worst += len(building.id) }
    }
    worst += 2*max(0,len(buildings)-1)
    return {buffer=make([]u8,POWER_SHED_TEXT_SLOTS*worst,allocator),capacity=worst}
}

@(private)
Fixed_Text :: struct {
    bytes: []u8,
    length: int,
}

@(private)
fixed_text_append :: proc(text: ^Fixed_Text, value: string) {
    remaining := len(text.bytes)-text.length
    count := min(remaining,len(value))
    copy(text.bytes[text.length:],value[:count])
    text.length += count
}

// Composes the single grouped power-shed notice of one tick into the next ring
// buffer. Every Power_Shed event is listed in shed order as its precomposed
// "Localized Name (ID)" identity; other event kinds are ignored. The returned string
// borrows ring storage allocated at load and never allocates. An unknown instance ID
// falls back to the raw ID rather than hiding a shed building.
compose_power_shed_notice :: proc(ring: ^Power_Shed_Notices, template: string, identities: map[string]string, events: []c.Sim_Event) -> string {
    assert(ring.capacity > 0 && len(ring.buffer) == POWER_SHED_TEXT_SLOTS*ring.capacity)
    head, match, tail := strings.partition(template,"{buildings}")
    assert(match != "") // Localization validation requires the list placeholder.
    offset := (ring.next % POWER_SHED_TEXT_SLOTS)*ring.capacity
    ring.next = (ring.next+1) % POWER_SHED_TEXT_SLOTS
    buffer := ring.buffer[offset:offset+ring.capacity]
    text := Fixed_Text{bytes=buffer}
    fixed_text_append(&text,head)
    listed := 0
    for event in events {
        if event.kind != .Power_Shed { continue }
        if listed > 0 { fixed_text_append(&text,", ") }
        if identity, found := identities[event.building_id]; found {
            fixed_text_append(&text,identity)
        } else {
            fixed_text_append(&text,event.building_id)
        }
        listed += 1
    }
    fixed_text_append(&text,tail)
    assert(text.length <= len(buffer)) // Worst-case capacity is computed at load.
    return string(buffer[:text.length])
}

show_building_notice :: proc(scene: ^ui.Scene_State, notices: Building_Notices, key, building_id, fallback: string) {
    ui.show_notice(scene,building_notice_text(notices,key,building_id,fallback))
}

// Consumes the session's pending events in ascending sequence order and appends one
// bounded notice each, then clears the queue so it cannot fill and drop newer
// transitions. Called once per fixed tick, never once per frame or per rendered frame.
// Every Power_Shed event of the tick is grouped into a single notice listing the
// affected buildings in shed order (see compose_power_shed_notice).
publish_event_notices :: proc(scene: ^ui.Scene_State, game: ^logic.State, text: localization.Text, notices: Building_Notices, shed: ^Power_Shed_Notices) {
    events := logic.pending_events(&game.events)
    shed_any := false
    for event in events {
        if event.kind == .Power_Shed { shed_any = true; continue }
        key := event_notice_key(event.kind)
        if key == "" { continue }
        ui.show_notice(scene,building_notice_text(notices,key,event.building_id,text.entries[key]))
    }
    if shed_any {
        ui.show_notice(scene,compose_power_shed_notice(shed,text.entries["notice_power_shed"],notices.identities,events))
    }
    logic.clear_events(&game.events)
}
