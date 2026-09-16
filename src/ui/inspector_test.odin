package ui

import c "../contracts"
import "core:testing"

@(test)
inspector_click_drag_focus_and_overlay :: proc(t: ^testing.T) {
    state: Scene_State
    targets := [?]c.Building_Target{{id="back",bounds={100,100,100,100}}, {id="front",bounds={100,100,100,100}}}
    press := c.Input{focused=true, right_pressed=true, mouse_x=120, mouse_y=120}
    release := press
    release.right_pressed = false
    release.right_released = true
    update_inspector(&state, press, targets[:], {}, {})
    update_inspector(&state, release, targets[:], {}, {})
    testing.expect(t, state.inspected_id == "front")
    bounds := inspector_bounds(&state, 200, 150)
    testing.expect(t, bounds.x >= 0 && bounds.y >= 0 && bounds.x+bounds.width <= 200 && bounds.y+bounds.height <= 150)
    update_inspector(&state, c.Input{focused=true,back=true}, targets[:], {}, {})
    testing.expect(t, state.inspected_id == "")
    update_inspector(&state, press, targets[:], {}, {})
    drag := release
    drag.mouse_x += 10
    update_inspector(&state, drag, targets[:], {}, {})
    testing.expect(t, state.inspected_id == "")
    update_inspector(&state, press, targets[:], {}, {})
    update_inspector(&state, {}, targets[:], {}, {})
    update_inspector(&state, release, targets[:], {}, {})
    testing.expect(t, state.inspected_id == "")
    hud := c.Hud_View{info_bounds={100,100,100,100}}
    update_inspector(&state, press, targets[:], {}, hud)
    update_inspector(&state, release, targets[:], {}, hud)
    testing.expect(t, state.inspected_id == "")
    left := press
    left.right_pressed = false
    left.click = true
    _, clicked := scene_command(left, targets[:], {}, hud)
    testing.expect(t, !clicked && over_overlay(left, {}, hud))
    left.right_pressed = true
    _, clicked = scene_command(left, targets[:], {}, {})
    testing.expect(t, !clicked)
    // A right click on empty space dismisses an existing inspector.
    state.inspected_id = "front"
    press.mouse_x, release.mouse_x = 300, 300
    update_inspector(&state, press, targets[:], {}, {})
    update_inspector(&state, release, targets[:], {}, {})
    testing.expect(t, state.inspected_id == "")
}
