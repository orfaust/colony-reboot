package ui

import "core:testing"
import c "../contracts"

@(test)
inspector_scroll_keeps_title_and_consumes_wheel :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    state := Scene_State{inspected_id="building"}
    bounds := c.Rect{100,100,420,120}
    rows := [?]c.Info_Row{{"title",true},{"one",false},{"two",false},{"three",false},{"four",false},{"five",false}}
    hint := [?]c.Info_Row{{"scroll",false}}
    input := c.Input{focused=true,mouse_x=110,mouse_y=110,zoom=-1}
    visible := inspector_visible_lines(&state,input,bounds,rows[:],hint[:])
    testing.expect(t,state.info_scroll == 1 && visible[0].text == "title" && visible[1].text == "two")
    testing.expect(t,visible[len(visible)-1].text == "scroll")
    for _ in 0..<20 { visible = inspector_visible_lines(&state,input,bounds,rows[:],hint[:]) }
    testing.expect(t,state.info_scroll == 3 && visible[len(visible)-2].text == "five")
    input.focused = false
    input.zoom = 1
    inspector_visible_lines(&state,input,bounds,rows[:],hint[:])
    testing.expect(t,state.info_scroll == 3)
    input.focused = true
    input.mouse_x = 0
    inspector_visible_lines(&state,input,bounds,rows[:],hint[:])
    testing.expect(t,state.info_scroll == 3)
    visible = inspector_visible_lines(&state,{}, {0,0,420,520},rows[:],hint[:])
    testing.expect(t,state.info_scroll == 0 && len(visible) == len(rows)+len(hint))
    testing.expect(t,visible[0].title && !visible[len(visible)-1].title)
    hud := c.Hud_View{info_bounds=bounds}
    testing.expect(t,over_overlay(c.Input{mouse_x=110,mouse_y=110},{},hud))
}

@(test)
station_rows_scroll_and_clamp_on_resize :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    rows := [?]c.Info_Row{{"station",true},{"resource",false},{"stock",false},{"rate",false},{"ships",false}}
    scroll := 0
    input := c.Input{focused=true,mouse_x=1,mouse_y=1,zoom=-1}
    visible := info_visible_rows(&scroll,input,{0,0,360,94},rows[:],nil)
    testing.expect(t,scroll == 1 && visible[1].text == "stock")
    visible = info_visible_rows(&scroll,{}, {0,0,360,400},rows[:],nil)
    testing.expect(t,scroll == 0 && len(visible) == len(rows))
}
