package render

import "core:testing"
import c "../contracts"

@(test)
development_reload_consumes_only_focused_press_edges :: proc(t: ^testing.T) {
    input := c.Input{width=640,height=360,focused=true,click=true,activate=true,back=true,speed_up=true,zoom=2,pan_x=4,right_pressed=true}
    testing.expect(t,!reload_input(input,false,true,true).reload_requested)
    testing.expect(t,!reload_input(input,true,false,true).reload_requested)
    testing.expect(t,!reload_input(input,true,true,false).reload_requested) // Held R, no new press.
    consumed := reload_input(input,true,true,true)
    testing.expect(t,consumed.reload_requested && consumed.width == 640 && consumed.focused)
    testing.expect(t,!consumed.click && !consumed.activate && !consumed.back && !consumed.speed_up && !consumed.right_pressed)
    testing.expect(t,consumed.zoom == 0 && consumed.pan_x == 0)
    input.focused = false
    testing.expect(t,!reload_input(input,true,true,true).reload_requested)
}
