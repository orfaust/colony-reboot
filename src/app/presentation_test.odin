package main

import c "../contracts"
import "core:math"
import "core:testing"

@(test)
clock_text_fills_placeholders :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    testing.expect(t, clock_text("Hour {hours}  x{speed}", {elapsed_hours=1234, speed=16}) == "Hour 1234  x16")
    testing.expect(t, clock_text("{speed}/{hours}", {elapsed_hours=0, speed=1}) == "1/0")
}

@(test)
level_bar_sits_beside_building :: proc(t: ^testing.T) {
    buildings := [?]c.Rect{{100,50,96,96}, {0,0,10,40}, {0,0,1000,20}}
    for building in buildings {
        testing.expect(t, level_bar_bounds(building, true) == c.Rect{})
        bar := level_bar_bounds(building, false)
        testing.expect(t, bar.x > building.x+building.width)
        testing.expect(t, bar.y == building.y && bar.height == building.height)
        testing.expect(t, bar.width >= 3 && bar.width <= 12)
    }
}

@(test)
building_dimensions_and_center_pivot :: proc(t: ^testing.T) {
    sizes := [?][2]f32{{640,360}, {1280,720}, {1920,1080}}
    for size in sizes {
        square := building_screen_bounds(DEFAULT_CAMERA, {0,0}, {1.5,1.5}, size[0], size[1])
        testing.expect(t, square.width == 96 && square.height == 96)
        testing.expect(t, square.x+square.width/2 == size[0]/2)
        testing.expect(t, square.y+square.height/2 == size[1]/2)
        rectangle := building_screen_bounds(DEFAULT_CAMERA, {2,-1}, {2,0.5}, size[0], size[1])
        testing.expect(t, rectangle.width == 128 && rectangle.height == 32)
        testing.expect(t, rectangle.x+rectangle.width/2 == size[0]/2+128)
        testing.expect(t, rectangle.y+rectangle.height/2 == size[1]/2-64)
    }
}

@(test)
zoom_scales_building_size :: proc(t: ^testing.T) {
    camera := Camera{zoom=2}
    bounds := building_screen_bounds(camera, {1,0}, {1,1}, 1280, 720)
    testing.expect(t, bounds.width == 128 && bounds.height == 128)
    testing.expect(t, bounds.x+bounds.width/2 == 640+128)
}

@(test)
zoom_keeps_point_under_cursor :: proc(t: ^testing.T) {
    camera := DEFAULT_CAMERA
    mouse_x, mouse_y := f32(900), f32(200)
    before := building_screen_bounds(camera, {3,-2}, {0,0}, 1280, 720)
    testing.expect(t, before.x == 640+192 && before.y == 360-128)
    // The world point under the cursor, at zoom 1.
    world_x, world_y := (mouse_x-640)/WORLD_SCALE, (mouse_y-360)/WORLD_SCALE
    zoom_camera(&camera, 3, mouse_x, mouse_y, 1280, 720)
    testing.expect(t, camera.zoom > 1)
    after := building_screen_bounds(camera, {world_x,world_y}, {0,0}, 1280, 720)
    testing.expect(t, math.abs(after.x-mouse_x) < 0.01 && math.abs(after.y-mouse_y) < 0.01)
}

@(test)
pan_follows_cursor :: proc(t: ^testing.T) {
    zooms := [?]f32{MIN_ZOOM, 1, 2.5}
    for zoom in zooms {
        camera := Camera{zoom=zoom}
        before := building_screen_bounds(camera, {1,1}, {0,0}, 1280, 720)
        pan_camera(&camera, 30, -12)
        after := building_screen_bounds(camera, {1,1}, {0,0}, 1280, 720)
        testing.expect(t, math.abs(after.x-before.x-30) < 0.01 && math.abs(after.y-before.y+12) < 0.01)
    }
}

@(test)
zoom_is_clamped :: proc(t: ^testing.T) {
    camera := DEFAULT_CAMERA
    zoom_camera(&camera, 100, 0, 0, 1280, 720)
    testing.expect(t, camera.zoom == MAX_ZOOM)
    zoom_camera(&camera, -100, 0, 0, 1280, 720)
    testing.expect(t, camera.zoom == MIN_ZOOM)
    center := camera.center
    zoom_camera(&camera, -1, 10, 10, 1280, 720)
    testing.expect(t, camera.center == center)
}
