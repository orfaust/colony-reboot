package render

import c "../contracts"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"

// Return per-rune advance INCLUDING the one-pixel spacing used by DrawTextEx.
// Backend-free wrapping accepts an explicit measurement contract for headless tests.
Glyph_Advance :: #type proc(rune) -> f32

wrap_info_text :: proc(lines: []string, width: f32, advance: Glyph_Advance) -> []c.Info_Row {
    rows := make([dynamic]c.Info_Row, context.temp_allocator)
    available := max(f32(1), width-2*c.INFO_PADDING)
    for line, line_index in lines {
        start := 0
        for start < len(line) {
            for start < len(line) && line[start] == ' ' { start += 1 }
            if start == len(line) { break }
            cursor, last_space := start, -1
            measured: f32
            for cursor < len(line) {
                r, size := utf8.decode_rune(line[cursor:])
                if r == '\n' {
                    append(&rows, c.Info_Row{line[start:cursor], line_index == 0})
                    start = cursor+size
                    break
                }
                next := advance(r)
                if measured+next-1 > available && cursor > start {
                    end := cursor
                    if last_space > start { end = last_space }
                    append(&rows, c.Info_Row{strings.trim_right(line[start:end], " "), line_index == 0})
                    start = end
                    break
                }
                if r == ' ' { last_space = cursor }
                measured += next
                cursor += size
                if cursor == len(line) {
                    append(&rows, c.Info_Row{strings.trim_right(line[start:cursor], " "), line_index == 0})
                    start = cursor
                }
            }
        }
    }
    return rows[:]
}

@(private)
info_glyph_advance :: proc(codepoint: rune) -> f32 {
    font := current_font()
    index := rl.GetGlyphIndex(font, codepoint)
    glyph := font.glyphs[index]
    width := glyph.advanceX != 0 ? f32(glyph.advanceX) : font.recs[index].width
    return width * c.INFO_FONT_SIZE/f32(font.baseSize) + 1
}

// Measurement is backend-owned; returned rows borrow input strings for this frame.
// Call after opening the window, before passing rows to UI pagination/layout.
wrap_info_lines :: proc(lines: []string, width: f32) -> []c.Info_Row {
    rows := wrap_info_text(lines, width, info_glyph_advance)
    when #config(INFO_BOX_SMOKE, false) {
        // Verify the headless wrapping contract against raylib's real font metrics.
        for row in rows {
            text := strings.clone_to_cstring(row.text,context.temp_allocator)
            measured := rl.MeasureTextEx(current_font(),text,c.INFO_FONT_SIZE,1)
            assert(measured.x <= max(f32(1),width-2*c.INFO_PADDING)+1, "wrapped text exceeds measured panel width")
        }
    }
    return rows
}
