package render

import c "../contracts"

// Fixed-size UI text starts at a common inset, never centered or scaled to fit.
info_text_origin :: proc(bounds: c.Rect) -> c.Vector2 {
    return {bounds.x+c.INFO_PADDING, bounds.y+c.INFO_PADDING}
}

info_line_color :: proc(index: int, title_color: c.RGB) -> c.RGB {
    if index == 0 { return title_color }
    return {255,255,255}
}

intersect_info_bounds :: proc(a, b: c.Rect) -> c.Rect {
    x, y := max(a.x,b.x), max(a.y,b.y)
    return {x,y,max(f32(0),min(a.x+a.width,b.x+b.width)-x),max(f32(0),min(a.y+a.height,b.y+b.height)-y)}
}
