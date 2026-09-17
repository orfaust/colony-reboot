package ui

import c "../contracts"
import "core:testing"

@(test)
modal_toggle_geometry_and_command :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    sizes := [?][2]f32{{640,360},{1280,720},{1920,1080}}
    for size in sizes {
        view := notice_view(&Scene_State{},size[0],size[1])
        bounds := modal_toggle_bounds(size[0],size[1])
        // Toggles stay right of the notice panel and inside the screen margin.
        testing.expect(t,bounds[0].x >= view.bounds.x+view.bounds.width)
        testing.expect(t,bounds[1].x+bounds[1].width <= size[0]-8)
        testing.expect(t,bounds[0].y+bounds[0].height <= bounds[1].y)
        toggles: [2]c.Modal_Toggle
        toggles[0] = {bounds=bounds[0],label="Buildings"}
        toggles[1] = {bounds=bounds[1],label="Subjects"}
        click := c.Input{focused=true,click=true,mouse_x=bounds[0].x+4,mouse_y=bounds[0].y+4}
        kind, clicked := modal_toggle_command(click,toggles,.None)
        testing.expect(t,clicked && kind == .Buildings)
        // Clicking the active toggle closes the grid.
        kind, clicked = modal_toggle_command(click,toggles,.Buildings)
        testing.expect(t,clicked && kind == .None)
        // Clicking the other toggle switches the grid.
        kind, clicked = modal_toggle_command(click,toggles,.Subjects)
        testing.expect(t,clicked && kind == .Buildings)
        click.focused = false
        _, clicked = modal_toggle_command(click,toggles,.None)
        testing.expect(t,!clicked)
        click.focused = true
        click.back = true
        _, clicked = modal_toggle_command(click,toggles,.None)
        testing.expect(t,!clicked)
        click.back = false
        click.right_pressed = true
        _, clicked = modal_toggle_command(click,toggles,.None)
        testing.expect(t,!clicked)
        input := c.Input{width=size[0],height=size[1],focused=true,click=true,mouse_x=bounds[1].x+2,mouse_y=bounds[1].y+2}
        _, clicked = modal_toggle_command(input,toggles,.None)
        testing.expect(t,clicked)
    }
}

@(test)
modal_grid_pages_and_clamps :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    bounds := modal_bounds(1280,720)
    testing.expect(t,bounds.x == 16 && bounds.width == 1280-32)
    rows := make([]c.Modal_Row,100,context.temp_allocator)
    for i in 0..<len(rows) { rows[i] = {cells=[]string{"row"}} }
    slots := modal_body_slots(bounds)
    input := c.Input{focused=true,mouse_x=bounds.x+4,mouse_y=bounds.y+4}
    scroll := 0
    visible := modal_visible_rows(&scroll,input,bounds,rows)
    testing.expect(t,len(visible) == slots && scroll == 0)
    input.zoom = -1
    visible = modal_visible_rows(&scroll,input,bounds,rows)
    testing.expect(t,len(visible) == slots && scroll == 1)
    // Wheel over a cell row still scrolls the modal; a wheel outside it does not.
    input.zoom = -1
    input.mouse_x = 0
    input.mouse_y = 0
    modal_visible_rows(&scroll,input,bounds,rows)
    testing.expect(t,scroll == 1)
    scroll = 10000
    modal_visible_rows(&scroll,input,bounds,rows)
    testing.expect(t,scroll == len(rows)-slots)
    // An empty grid resets any stale scroll.
    visible = modal_visible_rows(&scroll,input,bounds,nil)
    testing.expect(t,scroll == 0 && len(visible) == 0)
}

@(test)
modal_toggles_and_open_grid_consume_pointer_input :: proc(t: ^testing.T) {
    notice := notice_view(&Scene_State{},1280,720)
    bounds := modal_toggle_bounds(1280,720)
    hud: c.Hud_View
    hud.toggles[0] = {bounds=bounds[0]}
    input := c.Input{width=1280,height=720,focused=true,click=true,mouse_x=bounds[0].x+2,mouse_y=bounds[0].y+2}
    testing.expect(t,over_overlay(input,notice,hud))
    // An open grid consumes clicks anywhere, including over a building underneath.
    hud.modal = {kind=.Buildings}
    input.mouse_x, input.mouse_y = 700, 300
    testing.expect(t,over_overlay(input,notice,hud))
    targets := [?]c.Building_Target{{id="H",bounds={0,0,1280,720}}}
    _, clicked := scene_command(input,targets[:],notice,hud)
    testing.expect(t,!clicked)
}

// Configurable B/S bindings toggle the same panels as the bottom-right buttons.
@(test)
modal_keyboard_toggles_mirror_the_buttons :: proc(t: ^testing.T) {
    kind, changed := modal_key_toggle(.None,true,false)
    testing.expect(t,changed && kind == .Buildings)
    kind, changed = modal_key_toggle(.Buildings,true,false)
    testing.expect(t,changed && kind == .None)
    kind, changed = modal_key_toggle(.Subjects,true,false)
    testing.expect(t,changed && kind == .Buildings)
    kind, changed = modal_key_toggle(.None,false,true)
    testing.expect(t,changed && kind == .Subjects)
    kind, changed = modal_key_toggle(.Subjects,false,true)
    testing.expect(t,changed && kind == .None)
    kind, changed = modal_key_toggle(.Buildings,false,true)
    testing.expect(t,changed && kind == .Subjects)
    // Pressing both keys together, or neither, leaves the current panel unchanged.
    _, changed = modal_key_toggle(.Buildings,true,true)
    testing.expect(t,!changed)
    _, changed = modal_key_toggle(.None,false,false)
    testing.expect(t,!changed)
}
