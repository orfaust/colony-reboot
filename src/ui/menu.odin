package ui

import c "../contracts"

State :: struct {
    selected: int,
    status: string,
    title: string,
    labels: [4]string,
}

layout :: proc(width, height: f32) -> c.Menu_View {
    scale := min(f32(1), min(width / 640, height / 360))
    w, h, gap := 280 * scale, 48 * scale, 12 * scale
    top := (height - (4*h + 3*gap)) / 2
    view := c.Menu_View{
        font_size = i32(24 * scale),
        title_bounds = {0, top - 56 * scale, width, 32 * scale},
        title_font_size = i32(32 * scale),
    }
    for i in 0..<4 {
        view.buttons[i] = {bounds = {(width-w)/2, top+f32(i)*(h+gap), w, h}, label = ""}
    }
    return view
}

contains :: proc(r: c.Rect, x, y: f32) -> bool {
    return x >= r.x && x < r.x+r.width && y >= r.y && y < r.y+r.height
}

// Input and output are values. The menu owns focus and consumes all menu input.
update :: proc(state: ^State, input: c.Input) -> (view: c.Menu_View, action: c.Action) {
    view = layout(input.width, input.height)
    if input.focused {
        if input.up { state.selected = (state.selected + 3) % 4 }
        if input.down { state.selected = (state.selected + 1) % 4 }
        if input.mouse_moved || input.click {
            for button, i in view.buttons {
                if contains(button.bounds, input.mouse_x, input.mouse_y) {
                    state.selected = i
                    if input.click { action = c.Action(i+1) }
                }
            }
        }
        if input.activate && action == .None { action = c.Action(state.selected+1) }
    }
    for &button, i in view.buttons { button.label = state.labels[i] }
    view.buttons[state.selected].selected = true
    view.title = state.title
    view.status = state.status
    return
}
