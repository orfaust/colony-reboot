package render

import "core:strings"
import c "../contracts"
import rl "vendor:raylib"

// Window and GPU resources are owned here and used only on the main thread.
open :: proc(title: string) -> bool {
    window_title := strings.clone_to_cstring(title)
    defer delete(window_title)
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(1280, 720, window_title)
    if !rl.IsWindowReady() { return false }
    rl.SetWindowMinSize(640, 360)
    rl.SetExitKey(rl.KeyboardKey(0))
    rl.SetTargetFPS(60)
    return true
}

close :: proc() { rl.CloseWindow() }
should_close :: proc() -> bool { return rl.WindowShouldClose() }
elapsed_seconds :: proc() -> f64 { return f64(rl.GetFrameTime()) }

poll_input :: proc() -> c.Input {
    mouse := rl.GetMousePosition()
    delta := rl.GetMouseDelta()
    return {
        width = f32(rl.GetScreenWidth()), height = f32(rl.GetScreenHeight()),
        mouse_x = mouse.x, mouse_y = mouse.y,
        mouse_moved = delta.x != 0 || delta.y != 0,
        click = rl.IsMouseButtonPressed(.LEFT),
        up = rl.IsKeyPressed(.UP), down = rl.IsKeyPressed(.DOWN),
        activate = rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE),
        focused = rl.IsWindowFocused(),
        back = rl.IsKeyPressed(.ESCAPE),
    }
}

// Screen-space 2D presentation only; bounds do not define gameplay collision.
Building_Draw :: struct {
    bounds: c.Rect,
    color: c.RGB,
    code: string,
    active: bool,
    power_output, power_need, power_available: string,
}

// Description and borrowed code are consumed synchronously and never retained.
draw_scene :: proc(buildings: []Building_Draw, notice: c.Notice_View) {
    rl.BeginDrawing()
    defer rl.EndDrawing()
    rl.ClearBackground(rl.BLACK)
    for building in buildings {
        r := building.bounds
        color := building.color
        rl.DrawRectangleRec({r.x, r.y, r.width, r.height}, {color.r, color.g, color.b, 255})
        lines := [?]string{building.code, building.power_output, building.power_need, building.power_available}
        draw_building_lines(r, lines[:], building_code_color(color))
        // Overlay the whole building, including its text, with 50% black.
        if !building.active { rl.DrawRectangleRec({r.x,r.y,r.width,r.height}, {0,0,0,128}) }
    }
    r := notice.bounds
    rl.DrawRectangleRec({r.x,r.y,r.width,r.height}, {24,24,24,255})
    rl.DrawRectangleLinesEx({r.x,r.y,r.width,r.height}, 1, rl.GRAY)
    for i in 0..<notice.count {
        line := notice.lines[i]
        text := strings.clone_to_cstring(line.text, context.temp_allocator)
        font := rl.GetFontDefault()
        measured := rl.MeasureTextEx(font, text, 18, 1)
        label, scale := fit_building_code(line.bounds, {measured.x, measured.y})
        if scale > 0 {
            rl.DrawTextEx(font, text, {line.bounds.x+4,label.y}, 18*scale, scale, {255,220,120,255})
        }
    }
}

// Fit the complete block, then center each line independently inside it.
draw_building_lines :: proc(bounds: c.Rect, lines: []string, ink: c.RGB) {
    font := rl.GetFontDefault()
    width: f32
    count: int
    for line in lines {
        if line == "" { continue }
        text := strings.clone_to_cstring(line, context.temp_allocator)
        measured := rl.MeasureTextEx(font, text, 18, 1)
        width = max(width, measured.x)
        count += 1
    }
    if count == 0 { return }
    block, scale := fit_building_code(bounds, {width, f32(count)*20-2})
    if scale <= 0 { return }
    y := block.y
    for line in lines {
        if line == "" { continue }
        text := strings.clone_to_cstring(line, context.temp_allocator)
        measured := rl.MeasureTextEx(font, text, 18, 1)
        rl.DrawTextEx(font, text, {bounds.x+(bounds.width-measured.x*scale)/2,y}, 18*scale, scale, {ink.r,ink.g,ink.b,255})
        y += 20*scale
    }
}

// Temporary C strings are released after drawing; no frame data is retained.
draw :: proc(view: c.Menu_View) {
    rl.BeginDrawing()
    defer rl.EndDrawing()
    rl.ClearBackground(rl.BLACK)
    title := strings.clone_to_cstring(view.title, context.temp_allocator)
    title_width := rl.MeasureText(title, view.title_font_size)
    r := view.title_bounds
    rl.DrawText(title, i32(r.x+(r.width-f32(title_width))/2), i32(r.y), view.title_font_size, rl.WHITE)
    for button in view.buttons {
        r := button.bounds
        color := rl.Color{180, 180, 180, 255}
        if button.selected {
            color = rl.WHITE
            rl.DrawRectangleLinesEx({r.x, r.y, r.width, r.height}, 1, rl.Color{90, 90, 90, 255})
        }
        label := strings.clone_to_cstring(button.label, context.temp_allocator)
        width := rl.MeasureText(label, view.font_size)
        rl.DrawText(label, i32(r.x+(r.width-f32(width))/2), i32(r.y+(r.height-f32(view.font_size))/2), view.font_size, color)
    }
    if view.status != "" {
        text := strings.clone_to_cstring(view.status, context.temp_allocator)
        size: i32 = 18
        width := rl.MeasureText(text, size)
        rl.DrawText(text, (rl.GetScreenWidth()-width)/2, rl.GetScreenHeight()-40, size, rl.GRAY)
    }
}
