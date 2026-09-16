package ui

import "core:testing"
import c "../contracts"

@(test)
station_top_right_and_consumes_clicks :: proc(t: ^testing.T) {
    for size in ([?][2]f32{{640,360},{1280,720},{1920,1080}}) {
        bounds := station_bounds(size[0], size[1], 7)
        testing.expect(t, bounds.x+bounds.width == size[0]-16)
        testing.expect(t, bounds.y == 16)
        hud := hud_view(size[0],size[1])
        hud.station_bounds = bounds
        input := c.Input{focused=true, click=true, mouse_x=bounds.x+1, mouse_y=bounds.y+1}
        targets := [?]c.Building_Target{{id="covered", bounds=bounds}}
        _, clicked := scene_command(input, targets[:], {}, hud)
        testing.expect(t, !clicked)
        testing.expect(t, over_overlay(input, {}, hud))
    }
    tiny := station_bounds(20,10,7)
    testing.expect(t, tiny.x >= 0 && tiny.y >= 0)
    testing.expect(t, tiny.x+tiny.width <= 20 && tiny.y+tiny.height <= 10)
}
