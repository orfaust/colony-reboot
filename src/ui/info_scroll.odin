package ui

import c "../contracts"

info_row_slots :: proc(bounds: c.Rect) -> int {
    return max(1, int(max(f32(0), bounds.height-2*c.INFO_PADDING)/c.INFO_ROW_HEIGHT))
}

// UI owns row scrolling; renderer only supplies wrapped, measured rows. Keep the
// first title row and footer visible. Other title fragments stay in the scrollable
// body with their original title color. All rows borrow frame-temporary text.
info_visible_rows :: proc(scroll: ^int, input: c.Input, bounds: c.Rect, rows, hint: []c.Info_Row) -> []c.Info_Row {
    if len(rows) == 0 { scroll^ = 0; return nil }
    slots := info_row_slots(bounds)
    footer := min(len(hint), max(0, slots-2))
    body_slots := max(0, slots-1-footer)
    if input.focused && !input.back && contains(bounds,input.mouse_x,input.mouse_y) {
        if input.zoom > 0 { scroll^ -= 1 }
        if input.zoom < 0 { scroll^ += 1 }
    }
    scroll^ = clamp(scroll^, 0, max(0,len(rows)-1-body_slots))
    count := min(body_slots,len(rows)-1-scroll^)
    visible := make([]c.Info_Row,1+count+footer,context.temp_allocator)
    visible[0] = rows[0]
    for i in 0..<count { visible[i+1] = rows[scroll^+1+i] }
    for i in 0..<footer { visible[1+count+i] = {hint[i].text, false} }
    return visible
}
