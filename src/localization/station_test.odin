package localization

import "core:mem"
import "core:strings"
import "core:testing"

@(test)
station_and_building_text_requirements :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    source :: #load("../../assets/localization/en.json")
    for key in ([?]string{"transport_loading", "transport_waiting_landing", "transport_landing", "transport_unloading", "transport_taking_off", "transport_braking", "transport_returning", "transport_return_unloading", "transport_cancelled", "transport_eta_unknown", "transport_travelling", "transport_arrived", "transport_cargo_format", "transport_trip_format", "transport_speed_format", "transport_eta_format", "station_resources", "station_subjects", "station_ships", "station_empty", "station_stock_format", "station_ship_format", "building_info_health", "building_info_level", "building_info_active", "building_info_inactive", "building_info_close"}) {
        invalid, _ := strings.replace_all(string(source), key, "unused_key", allocator)
        _, ok := decode(transmute([]byte)invalid, allocator)
        testing.expect(t, !ok, key)
    }
    for token in ([?]string{"{name}", "{units}", "{capacity}", "{rate}", "{value}", "{hours}", "{speed}", "{destination}", "{remaining}", "{max_speed}", "{status}"}) {
        invalid, _ := strings.replace_all(string(source), token, "missing_token", allocator)
        _, ok := decode(transmute([]byte)invalid, allocator)
        testing.expect(t, !ok, token)
    }
}
