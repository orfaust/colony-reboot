package render

import c "../contracts"
import "core:strings"
import rl "vendor:raylib"

// All information text uses exactly the shared font size, including titles.
// Wrapping and UI pagination happen before submission; clip only at panel edges.
draw_info_rows :: proc(bounds: c.Rect, rows: []c.Info_Row, title_color: c.RGB, clip: c.Rect = {}) {
    visible := bounds
    if clip.width > 0 && clip.height > 0 { visible = intersect_info_bounds(bounds,clip) }
    if visible.width <= 0 || visible.height <= 0 { return }
    rl.BeginScissorMode(i32(visible.x),i32(visible.y),i32(visible.width),i32(visible.height))
    defer rl.EndScissorMode()
    origin := info_text_origin(bounds)
    for row, i in rows {
        y := origin.y+f32(i)*c.INFO_ROW_HEIGHT
        if y+c.INFO_FONT_SIZE <= visible.y || y >= visible.y+visible.height { continue }
        ink := info_line_color(row.title ? 0 : 1,title_color)
        text := strings.clone_to_cstring(row.text,context.temp_allocator)
        rl.DrawTextEx(current_font(),text,{origin.x,y},c.INFO_FONT_SIZE,1,{ink.r,ink.g,ink.b,255})
    }
}

draw_info_lines :: proc(bounds: c.Rect, lines: []string, title_color: c.RGB) {
    draw_info_rows(bounds,wrap_info_lines(lines,bounds.width),title_color)
}
