package ui

import c "../contracts"
import "core:testing"

@(test)
tall_transport_card_scrolls_to_last_row_and_clamps :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    rows: [40]c.Info_Row
    cards := [?]c.Transport_Card{{rows=rows[:]},{}}
    state: Scene_State
    bounds := c.Rect{16,64,240,128}
    visible := layout_transport_cards(&state,{},bounds,cards[:])
    testing.expect(t,len(visible) == 1 && visible[0].bounds.height > bounds.height)
    input := c.Input{focused=true,mouse_x=20,mouse_y=70,zoom=-100}
    visible = layout_transport_cards(&state,input,bounds,cards[:])
    testing.expect(t,len(visible) == 1 && visible[0].bounds.y+visible[0].bounds.height == bounds.y+bounds.height)
    // Removing history and resizing cannot retain an out-of-range scroll position.
    visible = layout_transport_cards(&state,{}, {16,64,400,1500},cards[:1])
    testing.expect(t,state.transport_pixel_scroll == 0 && len(visible) == 1)
    visible = layout_transport_cards(&state,{},bounds,nil)
    testing.expect(t,state.transport_pixel_scroll == 0 && len(visible) == 0)
}
