package ui

import "core:testing"
import c "../contracts"

@(test)
transport_panel_layout_and_consumption :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    for size in ([?]c.Vector2{{640,360},{1280,720},{1920,1080}}) {
        panel := transport_bounds(size.x,size.y,20)
        station := station_bounds(size.x,size.y,10)
        testing.expect(t,panel.x+panel.width <= station.x)
        notice := notice_view(&Scene_State{},size.x,size.y)
        testing.expect(t,panel.y+panel.height <= notice.bounds.y)
        hud := hud_view(size.x,size.y)
        hud.transport_bounds = panel
        input := c.Input{width=size.x,height=size.y,focused=true,click=true,zoom=-1,mouse_x=panel.x+2,mouse_y=panel.y+2}
        targets := [?]c.Building_Target{{id="H",bounds=panel}}
        _, clicked := scene_command(input,targets[:],notice,hud)
        testing.expect(t,!clicked && over_overlay(input,notice,hud))
        state: Scene_State
        cards: [20]c.Transport_Card
        layout_transport_cards(&state,input,panel,cards[:])
        testing.expect(t,state.transport_pixel_scroll == 3*c.INFO_ROW_HEIGHT)
        input.focused = false
        layout_transport_cards(&state,input,panel,cards[:])
        testing.expect(t,state.transport_pixel_scroll == 3*c.INFO_ROW_HEIGHT)
        state.transport_pixel_scroll = 10000
        layout_transport_cards(&state,input,panel,cards[:])
        testing.expect(t,state.transport_pixel_scroll == 20*c.TRANSPORT_CARD_HEIGHT-panel.height)
    }
    testing.expect(t,transport_bounds(640,360,0) == c.Rect{})
}
