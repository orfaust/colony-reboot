package main

import c "../contracts"
import "core:fmt"
import "core:strings"

WORLD_SCALE :: f32(64)

// Returned text lives only until the frame allocator is reset. All UI wording
// comes from a startup-validated localization template, never a printf template.
power_text :: proc(template: string, value: f64) -> string {
    number := fmt.aprintf("%.2f", value, allocator=context.temp_allocator)
    result, _ := strings.replace_all(template, "{value}", number, context.temp_allocator)
    return result
}

// Width/height are cached screen dimensions; authoritative positions remain in
// world units. The pivot and world origin both map to the viewport center at (0,0).
building_screen_bounds :: proc(position: c.Vector2, width, height, viewport_width, viewport_height: f32) -> c.Rect {
    return {
        viewport_width/2 + position.x*WORLD_SCALE - width/2,
        viewport_height/2 + position.y*WORLD_SCALE - height/2,
        width, height,
    }
}
