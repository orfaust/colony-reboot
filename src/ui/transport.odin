package ui

import c "../contracts"

// Fixed pixel icons and scrollable cards below the clock, above the notice panel.
transport_bounds :: proc(width, height: f32, count: int, clock_bottom: f32 = 56, notice_top: f32 = -1) -> c.Rect {
    if count == 0 { return {} }
    station := station_bounds(width,height,1)
    top := max(f32(64),clock_bottom+8)
    bottom := notice_top < 0 ? height-160 : notice_top
    return {16,top,max(f32(0),min(f32(300),station.x-32)),max(f32(0),bottom-top-8)}
}
transport_visible :: proc(bounds: c.Rect) -> int {
    if bounds.height <= 0 { return 0 }
    return max(1,int(bounds.height/c.TRANSPORT_CARD_HEIGHT))
}
