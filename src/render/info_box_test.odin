package render

import c "../contracts"
import "core:testing"

@(test)
info_text_fixed_size_and_inset :: proc(t: ^testing.T) {
    testing.expect(t, c.INFO_FONT_SIZE == 24 && c.INFO_ROW_HEIGHT == 26)
    testing.expect(t, info_text_origin({100,50,420,250}) == c.Vector2{108,58})
    testing.expect(t, info_text_origin({100,50,20,10}) == c.Vector2{108,58})
    testing.expect(t, intersect_info_bounds({10,10,40,40},{20,20,10,10}) == c.Rect{20,20,10,10})
}

@(test)
info_title_uses_element_color_only :: proc(t: ^testing.T) {
    color := c.RGB{0,86,179}
    testing.expect(t, info_line_color(0,color) == color)
    testing.expect(t, info_line_color(1,color) == c.RGB{255,255,255})
    testing.expect(t, info_line_color(7,color) == c.RGB{255,255,255})
}

fixed_glyph_advance :: proc(r: rune) -> f32 { return 11 }

@(test)
info_wrap_preserves_words_unicode_and_title_color :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    lines := [?]string{"Long title", "one two three", "abcdef", "café café", "two\nrows"}
    rows := wrap_info_text(lines[:], 71, fixed_glyph_advance)
    expected := [?]string{"Long","title","one","two","three","abcde","f","café","café","two","rows"}
    testing.expect(t, len(rows) == len(expected))
    for row, i in rows {
        if i < len(expected) { testing.expect(t, row.text == expected[i], row.text) }
        testing.expect(t, row.title == (i < 2))
    }
    // A resize changes wrapping, never the font size; long tokens remain reachable.
    wider := wrap_info_text(lines[:],300,fixed_glyph_advance)
    testing.expect(t, len(wider) == 6 && wider[0].text == "Long title")
    tiny := wrap_info_text([]string{"ab"},0,fixed_glyph_advance)
    testing.expect(t, len(tiny) == 2 && tiny[1].text == "b")
}
