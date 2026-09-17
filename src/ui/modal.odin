package ui

import c "../contracts"

// The two overview toggles sit bottom-right, beside the notice panel, which shrinks
// to leave them room. Geometry is frame-owned and matches the notice margins.
MODAL_TOGGLE_HEIGHT :: f32(40)
MODAL_TOGGLE_GAP :: f32(8)

// Right-hand column reserved for the toggles, clamped on narrow windows.
modal_reserve_width :: proc(width: f32) -> f32 {
    return clamp(width*0.28, f32(200), f32(320))
}

// Notice panel width after the toggle column is reserved; notice_view uses it so
// wrapping always matches the visible box.
notice_panel_width :: proc(width: f32) -> f32 {
    margin := min(f32(16), width/2)
    reserve := min(modal_reserve_width(width), max(f32(0), width-2*margin))
    return max(f32(0), width-2*margin-reserve-MODAL_TOGGLE_GAP)
}

// Two stacked toggles, bottom-aligned with the notice panel.
modal_toggle_bounds :: proc(width, height: f32) -> [2]c.Rect {
    margin := min(f32(16), min(width, height)/2)
    reserve := min(modal_reserve_width(width), max(f32(0), width-2*margin))
    x := width-margin-reserve
    bottom := height-margin
    bounds: [2]c.Rect
    bounds[1] = {x, bottom-MODAL_TOGGLE_HEIGHT, reserve, MODAL_TOGGLE_HEIGHT}
    bounds[0] = {x, bottom-MODAL_TOGGLE_HEIGHT*2-MODAL_TOGGLE_GAP, reserve, MODAL_TOGGLE_HEIGHT}
    return bounds
}

// Toggle clicks take priority over world input. Clicking the active toggle closes.
modal_toggle_command :: proc(input: c.Input, toggles: [2]c.Modal_Toggle, current: c.Modal_Kind) -> (c.Modal_Kind, bool) {
    if !input.focused || !input.click || input.back || input.right_pressed || input.right_released { return {}, false }
    kinds := [2]c.Modal_Kind{.Buildings,.Subjects}
    for toggle, i in toggles {
        if !contains(toggle.bounds, input.mouse_x, input.mouse_y) { continue }
        if current == kinds[i] { return .None, true }
        return kinds[i], true
    }
    return {}, false
}

// Configurable keyboard bindings mirror the buttons. Pressing both together cancels
// out; callers pass one press edge per frame, so holding a key never repeats.
modal_key_toggle :: proc(current: c.Modal_Kind, buildings, subjects: bool) -> (c.Modal_Kind, bool) {
    if buildings == subjects { return {}, false }
    if buildings {
        if current == .Buildings { return .None, true }
        return .Buildings, true
    }
    if current == .Subjects { return .None, true }
    return .Subjects, true
}

// Nearly full-screen modal; margins scale down on tiny windows.
modal_bounds :: proc(width, height: f32) -> c.Rect {
    margin := min(f32(16), min(width, height)/2)
    return {margin, margin, max(f32(0), width-2*margin), max(f32(0), height-2*margin)}
}

// Rows available for grid content: the panel holds a title, a header and a hint.
modal_body_slots :: proc(bounds: c.Rect) -> int {
    slots := int(max(f32(0), bounds.height-2*c.INFO_PADDING)/c.INFO_ROW_HEIGHT) - 3
    return max(1, slots)
}

// UI owns modal scrolling; renderer only draws the returned visible page.
modal_visible_rows :: proc(scroll: ^int, input: c.Input, bounds: c.Rect, rows: []c.Modal_Row) -> []c.Modal_Row {
    if len(rows) == 0 { scroll^ = 0; return nil }
    slots := modal_body_slots(bounds)
    if input.focused && !input.back && contains(bounds, input.mouse_x, input.mouse_y) {
        if input.zoom > 0 { scroll^ -= 1 }
        if input.zoom < 0 { scroll^ += 1 }
    }
    scroll^ = clamp(scroll^, 0, max(0, len(rows)-slots))
    count := min(slots, len(rows)-scroll^)
    return rows[scroll^:scroll^+count]
}
