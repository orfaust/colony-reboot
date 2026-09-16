package main

import "core:mem"
import "core:testing"
import "../localization"

@(test)
localized_power_values :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    context.temp_allocator = mem.dynamic_arena_allocator(&arena)
    source :: #load("../../assets/localization/en.json")
    text, ok := localization.decode(transmute([]byte)source, context.temp_allocator)
    testing.expect(t, ok)
    testing.expect(t, power_text(text.power_output_format,16) == "+16 kW")
    testing.expect(t, power_text(text.power_need_format,7) == "-7 kW")
    testing.expect(t, power_text(text.power_available_format,9) == "9 kW free")
}
