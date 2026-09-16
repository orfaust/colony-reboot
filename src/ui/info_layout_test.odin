package ui

import "core:testing"
import c "../contracts"

@(test)
wrapped_clock_and_notices_reserve_overlay_space :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    clock := hud_view(640,360,2)
    testing.expect(t,clock.bounds.height > HUD_HEIGHT)
    notice := notice_view(&Scene_State{},640,360,8)
    testing.expect(t,notice.bounds.height == 8*c.INFO_ROW_HEIGHT+2*c.INFO_PADDING)
    station := station_bounds(640,360,30,notice.bounds.y)
    testing.expect(t,station.y+station.height <= notice.bounds.y)
    panel := transport_bounds(640,360,1,clock.bounds.y+clock.bounds.height,notice.bounds.y)
    testing.expect(t,panel.y >= clock.bounds.y+clock.bounds.height)
    testing.expect(t,panel.y+panel.height <= notice.bounds.y)
    // In narrow remaining space a wheel step must not skip unread content.
    cards := [?]c.Transport_Card{{}}
    state: Scene_State
    input := c.Input{focused=true,zoom=-1,mouse_x=1,mouse_y=1}
    layout_transport_cards(&state,input,{0,0,200,48},cards[:])
    testing.expect(t,state.transport_pixel_scroll > 0 && state.transport_pixel_scroll <= 48)
}
