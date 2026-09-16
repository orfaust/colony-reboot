package main

import c "../contracts"
import "core:fmt"
import "core:math"
import "core:strings"

WORLD_SCALE :: f32(64)

// Returned text lives only until the frame allocator is reset. All UI wording
// comes from a startup-validated localization template, never a printf template.
power_text :: proc(template: string, value: f64) -> string {
    number := info_number(value)
    result, _ := strings.replace_all(template, "{value}", number, context.temp_allocator)
    return result
}

// Same lifetime and template rules as power_text; hours are whole simulated hours.
clock_text :: proc(template: string, clock: c.Clock_Snapshot) -> string {
    hours := fmt.aprintf("%d", clock.elapsed_hours, allocator=context.temp_allocator)
    speed := fmt.aprintf("%d", clock.speed, allocator=context.temp_allocator)
    with_hours, _ := strings.replace_all(template, "{hours}", hours, context.temp_allocator)
    result, _ := strings.replace_all(with_hours, "{speed}", speed, context.temp_allocator)
    return result
}

// Startup bar beside the building's right edge; it scales with the building on screen.
// Always-on buildings omit it: zero bounds tell the renderer not to draw a bar.
level_bar_bounds :: proc(building: c.Rect, always_on: bool) -> c.Rect {
    if always_on { return {} }
    width := clamp(building.width*0.08, 3, 12)
    return {building.x+building.width+width/2, building.y, width, building.height}
}

MIN_ZOOM :: f32(0.25)
MAX_ZOOM :: f32(4)
// Each wheel notch multiplies or divides the zoom by this factor.
ZOOM_STEP :: f32(1.1)

// Center is the world point shown at the viewport center.
Camera :: struct {
    center: c.Vector2,
    zoom: f32,
}

DEFAULT_CAMERA :: Camera{zoom = 1}

// Zoom around the cursor: the world point under the mouse stays under the mouse.
zoom_camera :: proc(camera: ^Camera, wheel, mouse_x, mouse_y, viewport_width, viewport_height: f32) {
    if wheel == 0 { return }
    next := clamp(camera.zoom*math.pow(ZOOM_STEP, wheel), MIN_ZOOM, MAX_ZOOM)
    if next == camera.zoom { return }
    dx, dy := mouse_x-viewport_width/2, mouse_y-viewport_height/2
    camera.center.x += dx/(WORLD_SCALE*camera.zoom) - dx/(WORLD_SCALE*next)
    camera.center.y += dy/(WORLD_SCALE*camera.zoom) - dy/(WORLD_SCALE*next)
    camera.zoom = next
}

// Dragging moves the world with the cursor at any zoom level.
pan_camera :: proc(camera: ^Camera, dx, dy: f32) {
    scale := WORLD_SCALE*camera.zoom
    camera.center.x -= dx/scale
    camera.center.y -= dy/scale
}

// Position and size are world units; authoritative positions never change with
// the camera. The building pivot is its center.
building_screen_bounds :: proc(camera: Camera, position, size: c.Vector2, viewport_width, viewport_height: f32) -> c.Rect {
    scale := WORLD_SCALE*camera.zoom
    width, height := size.x*scale, size.y*scale
    return {
        viewport_width/2 + (position.x-camera.center.x)*scale - width/2,
        viewport_height/2 + (position.y-camera.center.y)*scale - height/2,
        width, height,
    }
}
