package main

import "core:fmt"
import "core:strings"
import "../config"
import "../logic"
import "../ui"
import c "../contracts"

// Loading is an active departure; return handling is already back at base.
transport_box_visible :: proc(mission: logic.Transport) -> bool {
    return mission.phase != .Completed && mission.phase != .Cancelled && mission.phase != .Return_Unloading
}
transport_box_count :: proc(fleet: ^logic.Transport_State) -> int {
    count := 0
    for mission in fleet.missions[:fleet.count] {
        if transport_box_visible(mission) { count += 1 }
    }
    return count
}

transport_cards :: proc(fleet: ^logic.Transport_State, catalog: config.Catalog, texts: map[string]string, bounds: c.Rect, first: int, all: bool = false) -> []c.Transport_Card {
    active: [logic.TRANSPORT_LIMIT]int
    count := 0
    for mission, index in fleet.missions[:fleet.count] {
        if transport_box_visible(mission) { active[count] = index; count += 1 }
    }
    visible := all ? count : ui.transport_visible(bounds)
    start := clamp(first,0,max(0,count-visible))
    cards := make([]c.Transport_Card,min(visible,count),context.temp_allocator)
    for &card, i in cards {
        mission := logic.transport_snapshot(fleet,active[start+i])
        card.bounds = {bounds.x,bounds.y+f32(i)*c.TRANSPORT_CARD_HEIGHT,bounds.width,min(c.TRANSPORT_CARD_HEIGHT,bounds.height-f32(i)*c.TRANSPORT_CARD_HEIGHT)}
        cargo := logic.transport_cargo(mission)
        card.passengers = int(min(cargo,f32(20)))
        name, subject_name: string
        for ship in catalog.ships { if ship.id == mission.ship_id { name = ship.name; card.ship_color = ship.color; break } }
        for subject in catalog.subjects { if subject.id == mission.subject_id { subject_name = texts[subject.name_key]; card.subject_color = subject.color; card.subject_sprite = subject_sprite_definitions(subject.roles, catalog); break } }
        status_keys := [logic.Transport_Phase]string{
            .Loading="transport_loading", .Outbound="transport_travelling", .Waiting_Landing="transport_waiting_landing",
            .Landing="transport_landing", .Unloading="transport_unloading", .Taking_Off="transport_taking_off",
            .Braking="transport_braking", .Returning="transport_returning", .Return_Unloading="transport_return_unloading",
            .Completed="transport_arrived", .Cancelled="transport_cancelled",
        }
        status := texts[status_keys[mission.phase]]
        if mission.evacuation && mission.phase == .Unloading { status = texts["transport_loading"] }
        card.lines = make([]string,5,context.temp_allocator)
        card.lines[0] = name
        card.lines[1], _ = strings.replace_all(texts["transport_cargo_format"],"{name}",subject_name,context.temp_allocator)
        card.lines[1], _ = strings.replace_all(card.lines[1],"{units}",fmt.tprintf("%.0f",cargo),context.temp_allocator)
        destination := mission.destination
        if mission.requested == 0 { destination = fleet.station.name }
        card.lines[1], _ = strings.replace_all(card.lines[1],"{destination}",destination,context.temp_allocator)
        remaining := max(f64(0), mission.distance-mission.travelled)
        if mission.requested == 0 && (!mission.evacuation || mission.arrived) { remaining = mission.travelled }
        card.lines[2], _ = strings.replace_all(texts["transport_trip_format"],"{remaining}",fmt.tprintf("%.0f",remaining),context.temp_allocator)
        card.lines[3], _ = strings.replace_all(texts["transport_speed_format"],"{speed}",fmt.tprintf("%.0f",mission.speed),context.temp_allocator)
        card.lines[3], _ = strings.replace_all(card.lines[3],"{max_speed}",fmt.tprintf("%.0f",mission.max_speed),context.temp_allocator)
        eta := logic.transport_eta(mission)
        eta_text := texts["transport_eta_unknown"]
        if eta >= 0 { eta_text, _ = strings.replace_all(texts["transport_hours_format"],"{value}",fmt.tprintf("%.0f",eta),context.temp_allocator) }
        card.lines[4], _ = strings.replace_all(texts["transport_eta_format"],"{hours}",eta_text,context.temp_allocator)
        card.lines[4], _ = strings.replace_all(card.lines[4],"{status}",status,context.temp_allocator)
    }
    return cards
}
