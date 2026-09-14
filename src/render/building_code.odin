package render

import c "../contracts"

// Fit backend-measured text inside the building, preserving aspect ratio and a
// small inset. Scale never exceeds the base font size; no graphics state is used.
fit_building_code :: proc(bounds: c.Rect, measured: c.Vector2) -> (label: c.Rect, scale: f32) {
    if bounds.width <= 0 || bounds.height <= 0 || measured.x <= 0 || measured.y <= 0 { return }
    inset := min(f32(4), min(bounds.width, bounds.height)*0.1)
    scale = min(f32(1), min((bounds.width-2*inset)/measured.x, (bounds.height-2*inset)/measured.y))
    width, height := measured.x*scale, measured.y*scale
    label = {bounds.x+(bounds.width-width)/2, bounds.y+(bounds.height-height)/2, width, height}
    return
}

// Dark text on bright fills, light text on dark fills (including the blue CU).
building_code_color :: proc(fill: c.RGB) -> c.RGB {
    brightness := (299*i32(fill.r) + 587*i32(fill.g) + 114*i32(fill.b)) / 1000
    if brightness >= 128 { return {0,0,0} }
    return {255,255,255}
}
