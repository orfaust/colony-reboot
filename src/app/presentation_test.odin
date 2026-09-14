package main

import "core:testing"

@(test)
building_dimensions_and_center_pivot :: proc(t: ^testing.T) {
    sizes := [?][2]f32{{640,360}, {1280,720}, {1920,1080}}
    for size in sizes {
        square := building_screen_bounds({0,0}, 1.5*WORLD_SCALE, 1.5*WORLD_SCALE, size[0], size[1])
        testing.expect(t, square.width == 96 && square.height == 96)
        testing.expect(t, square.x+square.width/2 == size[0]/2)
        testing.expect(t, square.y+square.height/2 == size[1]/2)
        rectangle := building_screen_bounds({2,-1}, 2*WORLD_SCALE, 0.5*WORLD_SCALE, size[0], size[1])
        testing.expect(t, rectangle.width == 128 && rectangle.height == 32)
        testing.expect(t, rectangle.x+rectangle.width/2 == size[0]/2+128)
        testing.expect(t, rectangle.y+rectangle.height/2 == size[1]/2-64)
    }
}
