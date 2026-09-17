package ui

import c "../contracts"

State :: struct {
    selected: int,
    status: string,
    title: string,
    // Resume Game is offered only while a paused session exists.
    resume_available: bool,
    // Index 0 is Resume Game; indices 1..4 mirror Play, Load, Settings, Exit.
    labels: [5]string,
}

// Action for each visible entry in render order. Resume Game is first when a
// paused session exists; otherwise the base four keep their original order.
menu_action :: proc(resume_available: bool, button: int) -> c.Action {
    with_resume := [?]c.Action{.Resume, .Play, .Load, .Settings, .Exit}
    without_resume := [?]c.Action{.Play, .Load, .Settings, .Exit}
    if resume_available { return with_resume[button] }
    return without_resume[button]
}

menu_count :: proc(resume_available: bool) -> int {
    return resume_available ? 5 : 4
}

// Hidden Resume Game shifts every base label by one.
label_index :: proc(resume_available: bool, button: int) -> int {
    return resume_available ? button : button + 1
}

layout :: proc(width, height: f32, resume_available := false) -> c.Menu_View {
    scale := min(f32(1), min(width / 640, height / 360))
    w, h, gap := 280 * scale, 48 * scale, 12 * scale
    title_h, title_gap := 32 * scale, 24 * scale
    count := menu_count(resume_available)
    // Stack title plus entries and center the whole block, so the added Resume
    // entry still leaves the title inside the window at the minimum size.
    block := title_h + title_gap + f32(count)*h + f32(count-1)*gap
    top := max(f32(0), (height - block) / 2)
    view := c.Menu_View{
        font_size = i32(24 * scale),
        title_bounds = {0, top, width, title_h},
        title_font_size = i32(32 * scale),
        button_count = count,
    }
    buttons_top := top + title_h + title_gap
    for i in 0..<count {
        view.buttons[i] = {bounds = {(width-w)/2, buttons_top+f32(i)*(h+gap), w, h}, label = ""}
    }
    return view
}

contains :: proc(r: c.Rect, x, y: f32) -> bool {
    return x >= r.x && x < r.x+r.width && y >= r.y && y < r.y+r.height
}

// Input and output are values. The menu owns focus and consumes all menu input.
update :: proc(state: ^State, input: c.Input) -> (view: c.Menu_View, action: c.Action) {
    count := menu_count(state.resume_available)
    // Availability can change between frames; keep the selection inside the list.
    state.selected = clamp(state.selected, 0, count-1)
    view = layout(input.width, input.height, state.resume_available)
    if input.focused {
        if input.up { state.selected = (state.selected + count - 1) % count }
        if input.down { state.selected = (state.selected + 1) % count }
        if input.mouse_moved || input.click {
            for button, i in view.buttons[:count] {
                if contains(button.bounds, input.mouse_x, input.mouse_y) {
                    state.selected = i
                    if input.click { action = menu_action(state.resume_available,i) }
                }
            }
        }
        if input.activate && action == .None { action = menu_action(state.resume_available,state.selected) }
    }
    for &button, i in view.buttons[:count] { button.label = state.labels[label_index(state.resume_available,i)] }
    view.buttons[state.selected].selected = true
    view.title = state.title
    view.status = state.status
    return
}
