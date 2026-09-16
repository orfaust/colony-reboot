package render

import c "../contracts"
import "core:strings"
import rl "vendor:raylib"

FONT_PATH :: "assets/fonts/LCDBlock.ttf"
// Glyphs are rasterized once at this size; drawing above it gets blurry.
FONT_BASE_SIZE :: 64

ui_font: rl.Font
ui_font_loaded: bool

// Window and GPU resources are owned here and used only on the main thread.
open :: proc(title: string) -> bool {
	window_title := strings.clone_to_cstring(title)
	defer delete(window_title)
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, window_title)
	if !rl.IsWindowReady() {return false}
	rl.SetWindowMinSize(640, 360)
	rl.SetExitKey(rl.KeyboardKey(0))
	rl.SetTargetFPS(60)
	ui_font = rl.LoadFontEx(FONT_PATH, FONT_BASE_SIZE, nil, 0)
	// raylib returns its default font when loading fails; never unload that one.
	ui_font_loaded = ui_font.texture.id != rl.GetFontDefault().texture.id
	if ui_font_loaded {rl.SetTextureFilter(ui_font.texture, .BILINEAR)}
	return true
}

// Commit barrier: pump input once so the triggering key edge cannot be replayed
// by the new session before its first frame. No old presentation data is retained.
finish_reload_frame :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground({18,20,26,255})
    rl.EndDrawing()
}

set_title :: proc(title: string) {
    value := strings.clone_to_cstring(title)
    defer delete(value)
    rl.SetWindowTitle(value)
}

close :: proc() {
    destroy_sprites()
	if ui_font_loaded {rl.UnloadFont(ui_font)}
	rl.CloseWindow()
}

current_font :: proc() -> rl.Font {return ui_font_loaded ? ui_font : rl.GetFontDefault()}

// Matches raylib's DrawText spacing (size/10) so menu layout stays proportional.
measure_text :: proc(text: cstring, size: i32) -> f32 {
	return rl.MeasureTextEx(current_font(), text, f32(size), f32(size) / 10).x
}

draw_text :: proc(text: cstring, x, y: f32, size: i32, color: rl.Color) {
	rl.DrawTextEx(current_font(), text, {x, y}, f32(size), f32(size) / 10, color)
}

should_close :: proc() -> bool {return rl.WindowShouldClose()}
elapsed_seconds :: proc() -> f64 {return f64(rl.GetFrameTime())}

// Screen-space 2D presentation only; bounds do not define gameplay collision.
Building_Draw :: struct {
	bounds:                                    c.Rect,
	color:                                     c.RGB,
	code:                                      string,
    sprite:                                    string, // Borrowed preloaded asset path.
	illuminated:                               bool, // Supplied by app; never inferred from command activity.
	power_output, power_need, power_available: string,
	level_bar:                                 c.Rect, // Screen bounds of the startup bar.
	level:                                     f32, // Startup progress in [0,1], filled bottom-up.
}

// Description and borrowed code are consumed synchronously and never retained.
draw_scene :: proc(buildings: []Building_Draw, notice: c.Notice_View, hud: c.Hud_View, landings: []Landing_Draw = nil) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.BLACK)
	for building in buildings {
		r := building.bounds
		color := building.color
        draw_sprite_or_color(r, building.sprite, color)
		lines := [?]string {
			building.code,
			building.power_output,
			building.power_need,
			building.power_available,
		}
		draw_building_lines(r, lines[:], building_code_color(color))
		// Overlay the whole building, including its text, with 50% black.
		if !building.illuminated {rl.DrawRectangleRec({r.x, r.y, r.width, r.height}, {0, 0, 0, 128})}
		draw_level_bar(building.level_bar, building.level)
	}
    draw_landings(landings)
    draw_scene_overlays(notice,hud)
}

// Shared by the game and the opt-in visual smoke capture.
draw_scene_overlays :: proc(notice: c.Notice_View, hud: c.Hud_View) {
	r := notice.bounds
	rl.DrawRectangleRec({r.x, r.y, r.width, r.height}, {24, 24, 24, 255})
	rl.DrawRectangleLinesEx({r.x, r.y, r.width, r.height}, 1, rl.GRAY)
    notice_text: [c.NOTICE_VISIBLE_ROWS]string
    for i in 0..<notice.count { notice_text[i] = notice.lines[i].text }
    notice_rows := wrap_info_lines(notice_text[:notice.count], notice.bounds.width)
    for &row in notice_rows { row.title = true }
    // The log follows the newest wrapped rows, rather than shrinking older warnings.
    slots := max(1,int((notice.bounds.height-2*c.INFO_PADDING)/c.INFO_ROW_HEIGHT))
    draw_info_rows(notice.bounds, notice_rows[max(0,len(notice_rows)-slots):], {255,220,120})
	draw_hud(hud)
    draw_transports(hud.transports, hud.transport_bounds)
	if len(hud.station_rows) > 0 {
		r := hud.station_bounds
		rl.DrawRectangleRec({r.x, r.y, r.width, r.height}, {24, 24, 24, 255})
		rl.DrawRectangleLinesEx({r.x, r.y, r.width, r.height}, 1, rl.GRAY)
		draw_info_rows(r, hud.station_rows, {255, 255, 255})
	}
	if len(hud.info_rows) > 0 {
		r := hud.info_bounds
		rl.DrawRectangleRec({r.x, r.y, r.width, r.height}, {24, 24, 24, 255})
		rl.DrawRectangleLinesEx({r.x, r.y, r.width, r.height}, 1, rl.GRAY)
		draw_info_rows(r, hud.info_rows, hud.info_title_color)
	}
}

// Outside the building, so the inactive overlay never dims it. The fill moves as the
// simulation advances the level, which animates warmup and cooldown.
draw_level_bar :: proc(bar: c.Rect, level: f32) {
	if bar.width <= 0 || bar.height <= 0 {return}
	rl.DrawRectangleRec({bar.x, bar.y, bar.width, bar.height}, {40, 40, 40, 255})
	fill := bar.height * clamp(level, 0, 1)
	rl.DrawRectangleRec({bar.x, bar.y + bar.height - fill, bar.width, fill}, {255, 210, 0, 255})
}

HUD_FONT_SIZE :: c.INFO_FONT_SIZE

// Overlays are drawn last so buildings never cover them.
draw_hud :: proc(hud: c.Hud_View) {
	r := hud.bounds
	rl.DrawRectangleRec({r.x, r.y, r.width, r.height}, {24, 24, 24, 255})
	rl.DrawRectangleLinesEx({r.x, r.y, r.width, r.height}, 1, rl.GRAY)
	if hud.clock == "" {return}
    lines := [?]string{hud.clock}
    draw_info_lines(r, lines[:], {255,255,255})
}

// Largest size for building text; smaller buildings shrink it to fit.
BUILDING_FONT_SIZE :: f32(28)
BUILDING_LINE_GAP :: f32(2)

// Fit the complete block, then center each line independently inside it.
draw_building_lines :: proc(bounds: c.Rect, lines: []string, ink: c.RGB) {
	font := current_font()
	line_height := BUILDING_FONT_SIZE + BUILDING_LINE_GAP
	width: f32
	count: int
	for line in lines {
		if line == "" {continue}
		text := strings.clone_to_cstring(line, context.temp_allocator)
		measured := rl.MeasureTextEx(font, text, BUILDING_FONT_SIZE, 1)
		width = max(width, measured.x)
		count += 1
	}
	if count == 0 {return}
	block, scale := fit_building_code(bounds, {width, f32(count) * line_height - BUILDING_LINE_GAP})
	if scale <= 0 {return}
	y := block.y
	for line in lines {
		if line == "" {continue}
		text := strings.clone_to_cstring(line, context.temp_allocator)
		measured := rl.MeasureTextEx(font, text, BUILDING_FONT_SIZE, 1)
		rl.DrawTextEx(
			font,
			text,
			{bounds.x + (bounds.width - measured.x * scale) / 2, y},
			BUILDING_FONT_SIZE * scale,
			scale,
			{ink.r, ink.g, ink.b, 255},
		)
		y += line_height * scale
	}
}

// Temporary C strings are released after drawing; no frame data is retained.
draw :: proc(view: c.Menu_View) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.BLACK)
	title := strings.clone_to_cstring(view.title, context.temp_allocator)
	title_width := measure_text(title, view.title_font_size)
	r := view.title_bounds
	draw_text(title, r.x + (r.width - title_width) / 2, r.y, view.title_font_size, rl.WHITE)
	for button in view.buttons {
		r := button.bounds
		color := rl.Color{180, 180, 180, 255}
		if button.selected {
			color = rl.WHITE
			rl.DrawRectangleLinesEx({r.x, r.y, r.width, r.height}, 1, rl.Color{90, 90, 90, 255})
		}
		label := strings.clone_to_cstring(button.label, context.temp_allocator)
		width := measure_text(label, view.font_size)
		draw_text(
			label,
			r.x + (r.width - width) / 2,
			r.y + (r.height - f32(view.font_size)) / 2,
			view.font_size,
			color,
		)
	}
	if view.status != "" {
		text := strings.clone_to_cstring(view.status, context.temp_allocator)
		size: i32 = 18
		width := measure_text(text, size)
		draw_text(
			text,
			(f32(rl.GetScreenWidth()) - width) / 2,
			f32(rl.GetScreenHeight() - 40),
			size,
			rl.GRAY,
		)
	}
}
