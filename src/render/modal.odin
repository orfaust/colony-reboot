package render

import c "../contracts"
import "core:strings"
import rl "vendor:raylib"

// Dense overview grid. Columns are sized to their content and clipped per cell so a
// long value can never bleed into the next column. Text uses the shared info font.
draw_modal :: proc(modal: c.Modal_View) {
    if modal.kind == .None { return }
    rl.DrawRectangleRec({0,0,f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())},{0,0,0,200})
    b := modal.bounds
    rl.DrawRectangleRec({b.x,b.y,b.width,b.height},{24,24,24,255})
    rl.DrawRectangleLinesEx({b.x,b.y,b.width,b.height},1,rl.WHITE)
    if b.width <= 2*c.INFO_PADDING || b.height <= 2*c.INFO_PADDING { return }
    row := c.INFO_ROW_HEIGHT
    available := b.width-2*c.INFO_PADDING
    // A small square per row shows the element's configured color.
    swatch := min(f32(16), row-c.INFO_PADDING)
    swatch_gap := swatch > 0 ? f32(8) : f32(0)
    indent := swatch+swatch_gap
    draw_clipped_text({b.x+c.INFO_PADDING,b.y+c.INFO_PADDING,available,row},modal.title,rl.WHITE)
    columns := modal.columns
    count := len(columns)
    if count == 0 { return }
    gap := f32(12)
    widths := make([]f32,count,context.temp_allocator)
    content := make([]f32,count,context.temp_allocator)
    total := indent
    for col in 0..<count {
        w := measure_cell(columns[col])
        for data_row in modal.rows {
            if col < len(data_row.cells) { w = max(w,measure_cell(data_row.cells[col])) }
        }
        content[col] = w
        total += w
    }
    total += gap*f32(count-1)
    if total <= available {
        copy(widths,content)
    } else {
        // Cap every column at an equal share, then give the leftover to columns that
        // exceed it. Short columns and headers stay fully readable; only the widest
        // values truncate instead of every column shrinking proportionally.
        column_space := max(f32(0), available-indent-gap*f32(count-1))
        fair := column_space/f32(count)
        used, excess: f32
        for col in 0..<count {
            widths[col] = min(content[col],fair)
            used += widths[col]
            excess += max(f32(0),content[col]-fair)
        }
        leftover := max(f32(0),column_space-used)
        if excess > 0 {
            for col in 0..<count {
                if content[col] > fair { widths[col] += leftover*(content[col]-fair)/excess }
            }
        }
    }
    header_y := b.y+c.INFO_PADDING+row
    body_y := header_y+row
    hint_y := b.y+b.height-c.INFO_PADDING-row
    // Header, indented so it aligns with the cells after the color square.
    x := b.x+c.INFO_PADDING+indent
    header_clip := c.Rect{b.x+c.INFO_PADDING,header_y,available,row}
    for col in 0..<count {
        text := col < len(columns) ? columns[col] : ""
        clip := intersect_info_bounds({x,header_y,widths[col],row},header_clip)
        if clip.width > 0 { draw_clipped_text(clip,text,{180,180,180,255}) }
        x += widths[col]+gap
    }
    // Body, clipped to the space between the header and the hint.
    body_clip := c.Rect{b.x+c.INFO_PADDING,body_y,available,max(f32(0),hint_y-body_y)}
    for data_row, i in modal.rows {
        y := body_y+f32(i)*row
        if y+row <= body_clip.y || y >= body_clip.y+body_clip.height { continue }
        if data_row.has_swatch && swatch > 0 {
            origin := info_text_origin({b.x+c.INFO_PADDING,y,0,row})
            rl.DrawRectangleRec({origin.x,origin.y+(row-c.INFO_PADDING-swatch)/2,swatch,swatch},{data_row.swatch.r,data_row.swatch.g,data_row.swatch.b,255})
            rl.DrawRectangleLinesEx({origin.x,origin.y+(row-c.INFO_PADDING-swatch)/2,swatch,swatch},1,{150,150,150,255})
        }
        x = b.x+c.INFO_PADDING+indent
        for col in 0..<count {
            text := col < len(data_row.cells) ? data_row.cells[col] : ""
            clip := intersect_info_bounds({x,y,widths[col],row},body_clip)
            if clip.width > 0 && text != "" { draw_clipped_text(clip,text,rl.WHITE) }
            x += widths[col]+gap
        }
    }
    if modal.hint != "" { draw_clipped_text({b.x+c.INFO_PADDING,hint_y,available,row},modal.hint,{150,150,150,255}) }
}

// The two persistent toggles stay clickable above the modal backdrop.
draw_modal_toggles :: proc(toggles: [2]c.Modal_Toggle) {
    for toggle in toggles {
        b := toggle.bounds
        if b.width <= 0 || b.height <= 0 { continue }
        background := toggle.active ? rl.Color{60,90,150,255} : rl.Color{40,40,48,255}
        rl.DrawRectangleRec({b.x,b.y,b.width,b.height},background)
        rl.DrawRectangleLinesEx({b.x,b.y,b.width,b.height},1,toggle.active ? rl.WHITE : rl.GRAY)
        text := strings.clone_to_cstring(toggle.label,context.temp_allocator)
        width := rl.MeasureTextEx(current_font(),text,c.INFO_FONT_SIZE,1).x
        rl.DrawTextEx(current_font(),text,{b.x+(b.width-width)/2,b.y+(b.height-c.INFO_FONT_SIZE)/2},c.INFO_FONT_SIZE,1,rl.WHITE)
    }
}

@(private)
measure_cell :: proc(text: string) -> f32 {
    if text == "" { return 0 }
    value := strings.clone_to_cstring(text,context.temp_allocator)
    return rl.MeasureTextEx(current_font(),value,c.INFO_FONT_SIZE,1).x
}

@(private)
draw_clipped_text :: proc(bounds: c.Rect, text: string, color: rl.Color) {
    if text == "" || bounds.width <= 0 || bounds.height <= 0 { return }
    rl.BeginScissorMode(i32(bounds.x),i32(bounds.y),i32(bounds.width),i32(bounds.height))
    defer rl.EndScissorMode()
    value := strings.clone_to_cstring(text,context.temp_allocator)
    rl.DrawTextEx(current_font(),value,{bounds.x,bounds.y},c.INFO_FONT_SIZE,1,color)
}
