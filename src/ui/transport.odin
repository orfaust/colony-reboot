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

// Approval is its own command inside the panel: overlay consumption already keeps
// the click away from world selection, and only the panel-visible button area counts.
approve_command :: proc(input: c.Input, cards: []c.Transport_Card, viewport: c.Rect) -> (c.Approve_Transport, bool) {
    if !input.focused || !input.click || input.back || input.right_pressed || input.right_released { return {}, false }
    if !contains(viewport,input.mouse_x,input.mouse_y) { return {}, false }
    for card in cards {
        if card.approve_id == 0 || card.approve_bounds.width <= 0 { continue }
        if contains(card.approve_bounds,input.mouse_x,input.mouse_y) { return {id=card.approve_id}, true }
    }
    return {}, false
}
