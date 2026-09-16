package main

import "../ui"
import "../render"
import c "../contracts"

// Measure before input mapping so notification geometry and consumption agree.
// Typical warnings retain all four messages at fixed font size; extreme content
// is bounded by the viewport and the renderer follows the latest visible rows.
measured_notice_view :: proc(state: ^ui.Scene_State, width, height: f32) -> c.Notice_View {
    view := ui.notice_view(state,width,height)
    lines: [c.NOTICE_VISIBLE_ROWS]string
    for i in 0..<view.count { lines[i] = view.lines[i].text }
    rows := render.wrap_info_lines(lines[:view.count],view.bounds.width)
    return ui.notice_view(state,width,height,len(rows))
}
