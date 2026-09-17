package ui

import c "../contracts"

// A right-button gesture becomes an inspection only on release, within 4 pixels.
// Focus loss, Escape and starting over an overlay cancel the gesture.
update_inspector :: proc(state: ^Scene_State, input: c.Input, targets: []c.Building_Target, notice: c.Notice_View, hud: c.Hud_View) {
    if state.modal != .None { state.right_pending = false; return }
    if !input.focused || input.back {
        state.right_pending = false
        if input.back { state.inspected_id = "" }
        return
    }
    if input.right_pressed {
        state.right_origin = {input.mouse_x, input.mouse_y}
        state.right_pending = !over_overlay(input, notice, hud)
    }
    dx, dy := input.mouse_x-state.right_origin.x, input.mouse_y-state.right_origin.y
    if dx*dx+dy*dy > 16 { state.right_pending = false }
    if input.right_released {
        pending := state.right_pending
        state.right_pending = false
        if !pending || over_overlay(input, notice, hud) { return }
        state.inspected_id = ""
        state.info_scroll = 0
        for i := len(targets)-1; i >= 0; i -= 1 {
            if contains(targets[i].bounds, input.mouse_x, input.mouse_y) {
                state.inspected_id = targets[i].id
                state.info_anchor = {input.mouse_x+12, input.mouse_y+12}
                break
            }
        }
    }
}

inspector_bounds :: proc(state: ^Scene_State, width, height: f32) -> c.Rect {
    if state.inspected_id == "" { return {} }
    w, h := min(f32(420), max(f32(0), width)), min(f32(520), max(f32(0), height))
    return {clamp(state.info_anchor.x, 0, max(f32(0),width-w)), clamp(state.info_anchor.y, 0, max(f32(0),height-h)), w, h}
}
