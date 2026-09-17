package ui

import c "../contracts"
import "core:testing"

@(test)
tall_transport_card_scrolls_to_last_row_and_clamps :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    rows: [40]c.Info_Row
    cards := [?]c.Transport_Card{{rows=rows[:]},{}}
    state: Scene_State
    bounds := c.Rect{16,64,240,128}
    visible := layout_transport_cards(&state,{},bounds,cards[:])
    testing.expect(t,len(visible) == 1 && visible[0].bounds.height > bounds.height)
    input := c.Input{focused=true,mouse_x=20,mouse_y=70,zoom=-100}
    visible = layout_transport_cards(&state,input,bounds,cards[:])
    testing.expect(t,len(visible) == 1 && visible[0].bounds.y+visible[0].bounds.height == bounds.y+bounds.height)
    // Removing history and resizing cannot retain an out-of-range scroll position.
    visible = layout_transport_cards(&state,{}, {16,64,400,1500},cards[:1])
    testing.expect(t,state.transport_pixel_scroll == 0 && len(visible) == 1)
    visible = layout_transport_cards(&state,{},bounds,nil)
    testing.expect(t,state.transport_pixel_scroll == 0 && len(visible) == 0)
}

@(test)
approval_button_bounds_and_command_consumption :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    cards := [?]c.Transport_Card{{approve_id=7},{approve_id=0}}
    state: Scene_State
    bounds := c.Rect{16,64,240,300}
    visible := layout_transport_cards(&state,{},bounds,cards[:])
    testing.expect(t,len(visible) == 2)
    button := visible[0].approve_bounds
    testing.expect(t,button.width == 32 && button.height == 32)
    testing.expect(t,button.x+button.width <= bounds.x+bounds.width && button.y+button.height <= bounds.y+bounds.height)
    testing.expect(t,visible[1].approve_bounds.width == 0) // Non-pending card.
    input := c.Input{focused=true,click=true,mouse_x=button.x+8,mouse_y=button.y+8}
    command, approved := approve_command(input,visible,bounds)
    testing.expect(t,approved && command.id == 7)
    input.back = true
    _, approved = approve_command(input,visible,bounds)
    testing.expect(t,!approved)
    input.back = false
    input.right_pressed = true
    _, approved = approve_command(input,visible,bounds)
    testing.expect(t,!approved)
    input.right_pressed = false
    input.click = false
    _, approved = approve_command(input,visible,bounds)
    testing.expect(t,!approved)
    // A button scrolled outside the panel is not actionable even though it has geometry.
    input.click = true
    input.mouse_x = visible[1].approve_bounds.x+8
    input.mouse_y = visible[1].approve_bounds.y+8
    _, approved = approve_command(input,visible,bounds)
    testing.expect(t,!approved)
    // Only the panel-visible part of a clipped button accepts the click.
    state = {}
    clipped := [?]c.Transport_Card{{approve_id=9,rows=make([]c.Info_Row,10,context.temp_allocator)}}
    visible = layout_transport_cards(&state,{},bounds,clipped[:])
    button = visible[0].approve_bounds
    testing.expect(t,button.width == 32 && button.y+button.height > bounds.y+bounds.height)
    input = c.Input{focused=true,click=true,mouse_x=button.x+8,mouse_y=bounds.y+bounds.height-4}
    command, approved = approve_command(input,visible,bounds)
    testing.expect(t,approved && command.id == 9)
    input.mouse_y = bounds.y+bounds.height+4 // Clipped away, outside the panel.
    _, approved = approve_command(input,visible,bounds)
    testing.expect(t,!approved)
}
