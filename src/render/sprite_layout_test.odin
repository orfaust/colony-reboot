package render

import "core:testing"
import c "../contracts"

@(test)
sprites_align_to_screen_pixels_without_mutating_input :: proc(t: ^testing.T) {
    bounds := c.Rect{1.2,-2.7,9.2,15.8}
    aligned := sprite_pixel_bounds(bounds)
    testing.expect(t, aligned == c.Rect{1,-3,9,16})
    testing.expect(t, bounds == c.Rect{1.2,-2.7,9.2,15.8})
    testing.expect(t, sprite_pixel_bounds({0,0,0.1,0.1}) == c.Rect{0,0,1,1})
}
