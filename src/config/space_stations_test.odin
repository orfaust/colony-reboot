package config

import "core:mem"
import "core:strings"
import "core:testing"

@(test)
station_catalog_ids_order_and_shape :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := make(map[string]string, allocator)
    texts["station_name"] = "Station"
    first :: `{"id":"first","code":"FIRST","name_key":"station_name","resources":[],"subjects":[],"ships":[]}`
    second :: `{"id":"second","code":"SECOND","name_key":"station_name","resources":[],"subjects":[],"ships":[]}`
    data := "[" + first + "," + second + "]"
    stations, error := decode_space_stations(transmute([]byte)data, {}, texts, allocator)
    testing.expect(t, error == "", error)
    testing.expect(t, len(stations) == 2)
    if len(stations) == 2 { testing.expect(t, stations[0].id == "first" && stations[1].id == "second") }
    duplicate := "[" + first + "," + first + "]"
    _, duplicate_error := decode_space_stations(transmute([]byte)duplicate, {}, texts, allocator)
    testing.expect(t, strings.contains(duplicate_error, "duplicate ID"), duplicate_error)
    for invalid in ([?]string{first, "null", "[null]", `[{"name_key":"station_name","resources":[],"subjects":[],"ships":[]}]`}) {
        _, err := decode_space_stations(transmute([]byte)invalid, {}, texts, allocator)
        testing.expect(t, err != "", invalid)
    }
    empty := "[]"
    empty_stations, empty_error := decode_space_stations(transmute([]byte)empty, {}, texts, allocator)
    testing.expect(t, empty_error == "" && len(empty_stations) == 0)
}
