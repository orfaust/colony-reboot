package localization

import "core:mem"
import "core:testing"
import "core:strings"

@(test)
english_catalog :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    data :: #load("../../assets/localization/en.json")
    text, ok := decode(transmute([]byte)data, mem.dynamic_arena_allocator(&arena))
    testing.expect(t, ok)
    testing.expect(t, len(text.window_title) > 0 && len(text.exit_game) > 0)
    testing.expect(t, len(text.menu_title) > 0)
    testing.expect(t, len(text.building_control_unit_name) > 0)
    testing.expect(t, len(text.building_control_unit_description) > 0)
}

@(test)
invalid_catalog :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    cases := [?]string{"{", "{}", "[]", "{\"play\": 42}"}
    for data in cases {
        _, ok := decode(transmute([]byte)data, allocator)
        testing.expect(t, !ok)
    }
    data :: #load("../../assets/localization/en.json")
    text, _ := decode(transmute([]byte)data, allocator)
    empty, _ := strings.replace_all(string(data), text.window_title, "", allocator)
    _, ok := decode(transmute([]byte)empty, allocator)
    testing.expect(t, !ok)
    replacements := [?]string{"", "   "}
    for replacement in replacements {
        invalid, _ := strings.replace_all(string(data), text.menu_title, replacement, allocator)
        _, valid := decode(transmute([]byte)invalid, allocator)
        testing.expect(t, !valid)
    }
    missing, _ := strings.replace_all(string(data), "\"menu_title\"", "\"unused_title\"", allocator)
    _, valid := decode(transmute([]byte)missing, allocator)
    testing.expect(t, !valid)
    building_fields := [?]string{"building_control_unit_name", "building_control_unit_description"}
    for field in building_fields {
        missing_field, _ := strings.replace_all(string(data), field, "unused_field", allocator)
        _, field_ok := decode(transmute([]byte)missing_field, allocator)
        testing.expect(t, !field_ok)
    }
}
