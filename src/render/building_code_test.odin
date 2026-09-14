package render

import "core:math"
import "core:testing"
import c "../contracts"

@(test)
code_is_centered_and_fits :: proc(t: ^testing.T) {
    rectangles := [?]c.Rect{{0,0,96,96}, {50,20,128,32}, {10,10,12,8}, {0,0,1,1}}
    for bounds in rectangles {
        label, scale := fit_building_code(bounds, {40,24})
        testing.expect(t, scale > 0 && scale <= 1)
        testing.expect(t, label.x >= bounds.x && label.y >= bounds.y)
        testing.expect(t, label.x+label.width <= bounds.x+bounds.width)
        testing.expect(t, label.y+label.height <= bounds.y+bounds.height)
        testing.expect(t, math.abs(label.x+label.width/2 - (bounds.x+bounds.width/2)) < 0.001)
        testing.expect(t, math.abs(label.y+label.height/2 - (bounds.y+bounds.height/2)) < 0.001)
    }
    _, empty_scale := fit_building_code({0,0,96,96}, {0,0})
    testing.expect(t, empty_scale == 0)
}

@(test)
code_contrast :: proc(t: ^testing.T) {
    testing.expect(t, building_code_color({0,0,255}) == c.RGB{255,255,255})
    testing.expect(t, building_code_color({255,255,0}) == c.RGB{0,0,0})
    testing.expect(t, building_code_color({0,255,255}) == c.RGB{0,0,0})
    testing.expect(t, building_code_color({0,255,0}) == c.RGB{0,0,0})
    testing.expect(t, building_code_color({128,128,128}) == c.RGB{0,0,0})
}
