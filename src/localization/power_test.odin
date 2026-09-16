package localization

import "core:mem"
import "core:strings"
import "core:testing"

@(test)
power_text_requires_templates_and_notices :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    source :: #load("../../assets/localization/en.json")
    text, ok := decode(transmute([]byte)source, allocator)
    testing.expect(t, ok)
    missing_placeholder, _ := strings.replace_all(string(source), "{value}", "", allocator)
    _, format_ok := decode(transmute([]byte)missing_placeholder, allocator)
    testing.expect(t, !format_ok)
    keys := [?]string{"power_output_format","power_need_format","power_available_format",
        "notice_insufficient_power","notice_generator_required","notice_control_unit_locked","notice_always_on_locked",
        "notice_insufficient_health"}
    placeholders := [?]string{"{hours}", "{speed}"}
    for placeholder in placeholders {
        missing_clock, _ := strings.replace_all(string(source), placeholder, "", allocator)
        _, clock_ok := decode(transmute([]byte)missing_clock, allocator)
        testing.expect(t, !clock_ok, placeholder)
    }
    missing_clock_key, _ := strings.replace_all(string(source), "hud_clock_format", "unused_text", allocator)
    _, clock_key_ok := decode(transmute([]byte)missing_clock_key, allocator)
    testing.expect(t, !clock_key_ok)
    for key in keys {
        testing.expect(t, text.entries[key] != "")
        missing, _ := strings.replace_all(string(source), key, "unused_text", allocator)
        _, key_ok := decode(transmute([]byte)missing, allocator)
        testing.expect(t, !key_ok, key)
    }
}
