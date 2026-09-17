package ui

import c "../contracts"

// Wrapped card heights determine a pixel-scrollable list. Tall cards remain fully
// reachable even when just one card exceeds the viewport. Geometry is frame-owned.
layout_transport_cards :: proc(state: ^Scene_State, input: c.Input, bounds: c.Rect, cards: []c.Transport_Card) -> []c.Transport_Card {
    total: f32
    for &card in cards {
        card.bounds.height = max(c.TRANSPORT_CARD_HEIGHT, f32(len(card.rows))*c.INFO_ROW_HEIGHT+2*c.INFO_PADDING+40)
        total += card.bounds.height
    }
    if input.focused && !input.back && contains(bounds,input.mouse_x,input.mouse_y) {
        step := min(c.INFO_ROW_HEIGHT*3,max(f32(1),bounds.height-c.INFO_FONT_SIZE))
        state.transport_pixel_scroll -= input.zoom*step
    }
    state.transport_pixel_scroll = clamp(state.transport_pixel_scroll,0,max(f32(0),total-bounds.height))
    visible := make([dynamic]c.Transport_Card,context.temp_allocator)
    y := bounds.y-state.transport_pixel_scroll
    for &card in cards {
        card.bounds = {bounds.x,y,bounds.width,card.bounds.height}
        if card.approve_id != 0 {
            // Full button geometry; drawing is scissor-clipped and the click is
            // accepted only inside the panel viewport.
            card.approve_bounds = {card.bounds.x+card.bounds.width-40,card.bounds.y+card.bounds.height-36,32,32}
        } else {
            card.approve_bounds = {}
        }
        if bounds.width > 0 && bounds.height > 0 && y < bounds.y+bounds.height && y+card.bounds.height > bounds.y { append(&visible,card) }
        y += card.bounds.height
    }
    return visible[:]
}
