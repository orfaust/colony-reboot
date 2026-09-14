package ui

import "core:math"
import c "../contracts"

NOTICE_CAPACITY :: 32
Notice :: struct {
    text: string, // Borrowed localization text, never frame-temporary storage.
    remaining: f64,
}
Scene_State :: struct {
    notices: [NOTICE_CAPACITY]Notice,
    notice_count: int,
}

// Chronological bounded log. Overflow drops the oldest entry; repeated warnings
// remain distinct. New messages never reset the lifetime of previous messages.
show_notice :: proc(state: ^Scene_State, text: string) {
    if text == "" { return }
    if state.notice_count == NOTICE_CAPACITY {
        for i in 1..<NOTICE_CAPACITY { state.notices[i-1] = state.notices[i] }
        state.notice_count -= 1
    }
    state.notices[state.notice_count] = {text=text, remaining=10}
    state.notice_count += 1
}

advance_notice :: proc(state: ^Scene_State, elapsed: f64) {
    if math.is_nan(elapsed) || elapsed <= 0 { return }
    kept := 0
    for notice in state.notices[:state.notice_count] {
        next := notice
        next.remaining = max(f64(0), next.remaining-elapsed)
        if next.remaining > 0 {
            state.notices[kept] = next
            kept += 1
        }
    }
    for i in kept..<state.notice_count { state.notices[i] = {} }
    state.notice_count = kept
}

// Follow the newest messages automatically: older rows move upward as messages
// arrive. Return independent row values, not a slice into mutable UI state.
notice_view :: proc(state: ^Scene_State, width, height: f32) -> c.Notice_View {
    margin := min(f32(16), min(width,height)/2)
    panel_height := min(f32(112), max(f32(0), height-2*margin))
    view := c.Notice_View{bounds={margin, height-margin-panel_height, max(f32(0),width-2*margin), panel_height}}
    view.count = min(state.notice_count, c.NOTICE_VISIBLE_ROWS)
    padding := min(f32(8), panel_height/2)
    row_height := (panel_height-2*padding)/f32(c.NOTICE_VISIBLE_ROWS)
    start := state.notice_count-view.count
    for i in 0..<view.count {
        row := c.NOTICE_VISIBLE_ROWS-view.count+i
        view.lines[i] = {
            bounds={view.bounds.x+padding, view.bounds.y+padding+f32(row)*row_height,
                    max(f32(0),view.bounds.width-2*padding),row_height},
            text=state.notices[start+i].text,
        }
    }
    return view
}

// UI overlays consume clicks first. Reverse draw order selects only the topmost
// building. No command is emitted while unfocused, on Escape, or without a click.
scene_command :: proc(input: c.Input, targets: []c.Building_Target, notice: c.Notice_View) -> (c.Toggle_Building, bool) {
    if !input.focused || !input.click || input.back || contains(notice.bounds, input.mouse_x, input.mouse_y) {
        return {}, false
    }
    for i := len(targets)-1; i >= 0; i -= 1 {
        if contains(targets[i].bounds, input.mouse_x, input.mouse_y) {
            return {id=targets[i].id}, true
        }
    }
    return {}, false
}
