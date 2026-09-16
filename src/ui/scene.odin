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
    info_scroll, station_scroll: int,
    transport_pixel_scroll: f32,
    inspected_id: string, // Borrows a stable startup building ID, never a snapshot pointer.
    info_anchor, right_origin: c.Vector2,
    right_pending: bool,
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
notice_view :: proc(state: ^Scene_State, width, height: f32, wrapped_rows: int = 4) -> c.Notice_View {
    margin := min(f32(16), min(width,height)/2)
    // Retain the original minimum height; measured wrapping may grow the panel.
    panel_height := min(max(f32(144),f32(wrapped_rows)*c.INFO_ROW_HEIGHT+2*c.INFO_PADDING), max(f32(0), height-2*margin))
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

// Right-anchored panel; clamp to the viewport on small windows.
station_bounds :: proc(width, height: f32, line_count: int, notice_top: f32 = -1) -> c.Rect {
    margin := min(f32(16), min(width, height)/2)
    panel_width := clamp(width-2*margin, 0, 360)
    notice := notice_view(&Scene_State{}, width, height)
    // Keep station content above the notification panel; overflow is scrollable.
    available := max(f32(0), (notice_top < 0 ? notice.bounds.y : notice_top)-margin-8)
    return {width-margin-panel_width, margin, panel_width, clamp(f32(line_count)*c.INFO_ROW_HEIGHT+2*c.INFO_PADDING, 0, available)}
}

HUD_WIDTH :: f32(260)
HUD_HEIGHT :: f32(40)

// Top-left panel with the same margin as the notice panel; the app fills in the text.
hud_view :: proc(width, height: f32, rows: int = 1) -> c.Hud_View {
    margin := min(f32(16), min(width,height)/2)
    return {bounds={margin, margin, clamp(width-2*margin, 0, HUD_WIDTH), clamp(height-2*margin, 0, max(HUD_HEIGHT,f32(rows)*c.INFO_ROW_HEIGHT-2+2*c.INFO_PADDING))}}
}

// One speed change per frame; pressing both bindings together cancels out.
speed_command :: proc(input: c.Input) -> (c.Speed_Change, bool) {
    if !input.focused || input.back || input.speed_up == input.slow_down { return {}, false }
    return input.speed_up ? .Faster : .Slower, true
}

// UI overlays consume clicks first. Reverse draw order selects only the topmost
// building. No command is emitted while unfocused, on Escape, or without a click.
scene_command :: proc(input: c.Input, targets: []c.Building_Target, notice: c.Notice_View, hud: c.Hud_View) -> (c.Toggle_Building, bool) {
    if !input.focused || !input.click || input.right_pressed || input.right_released || input.back || over_overlay(input, notice, hud) {
        return {}, false
    }
    for i := len(targets)-1; i >= 0; i -= 1 {
        if contains(targets[i].bounds, input.mouse_x, input.mouse_y) {
            return {id=targets[i].id}, true
        }
    }
    return {}, false
}

// Overlays consume pointer input even while empty.
over_overlay :: proc(input: c.Input, notice: c.Notice_View, hud: c.Hud_View) -> bool {
    return contains(hud.transport_bounds, input.mouse_x, input.mouse_y) || contains(notice.bounds, input.mouse_x, input.mouse_y) || contains(hud.bounds, input.mouse_x, input.mouse_y) || contains(hud.station_bounds, input.mouse_x, input.mouse_y) || contains(hud.info_bounds, input.mouse_x, input.mouse_y)
}
