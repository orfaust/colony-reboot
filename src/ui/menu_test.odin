package ui

import "core:testing"
import c "../contracts"

@(test)
keyboard_navigation :: proc(t: ^testing.T) {
    state: State
    input := c.Input{width=1280, height=720, focused=true, up=true}
    _, action := update(&state, input)
    testing.expect(t, state.selected == 3 && action == .None)
    input.up = false
    input.activate = true
    _, action = update(&state, input)
    testing.expect(t, action == .Exit)
    input.activate = false
    input.down = true
    _, action = update(&state, input)
    testing.expect(t, state.selected == 0 && action == .None)
}

@(test)
mouse_and_focus :: proc(t: ^testing.T) {
    state: State
    input := c.Input{width=640, height=360, focused=true, click=true}
    view := layout(input.width, input.height)
    for button, i in view.buttons[:view.button_count] {
        input.mouse_x = button.bounds.x + 1
        input.mouse_y = button.bounds.y + 1
        _, action := update(&state, input)
        testing.expect(t, action == menu_action(state.resume_available,i))
    }
    input.focused = false
    _, action := update(&state, input)
    testing.expect(t, action == .None)
    input.focused = true
    input.mouse_x = 0
    input.mouse_y = 0
    _, action = update(&state, input)
    testing.expect(t, action == .None)
}

@(test)
resume_game_appears_only_for_a_paused_session :: proc(t: ^testing.T) {
    state := State{labels = {"RESUME GAME", "PLAY", "LOAD", "SETTINGS", "EXIT GAME"}}
    view, action := update(&state, c.Input{width=1280, height=720, focused=true})
    testing.expect(t, action == .None && view.button_count == 4)
    testing.expect(t, view.buttons[0].label == "PLAY" && view.buttons[3].label == "EXIT GAME")
    // Wrapping skips the hidden entry.
    _, action = update(&state, c.Input{width=1280, height=720, focused=true, up=true})
    testing.expect(t, state.selected == 3 && action == .None)

    state.resume_available = true
    state.selected = 0
    view, action = update(&state, c.Input{width=1280, height=720, focused=true})
    testing.expect(t, view.button_count == 5 && view.buttons[0].label == "RESUME GAME" && view.buttons[4].label == "EXIT GAME")
    testing.expect(t, action == .None)
    _, action = update(&state, c.Input{width=1280, height=720, focused=true, activate=true})
    testing.expect(t, action == .Resume)
    // Selection clamps back into range if the entry disappears.
    state.selected = 4
    state.resume_available = false
    view, _ = update(&state, c.Input{width=1280, height=720, focused=true})
    testing.expect(t, view.button_count == 4 && state.selected == 3 && view.buttons[3].selected)
}

@(test)
resize_layout :: proc(t: ^testing.T) {
    sizes := [3][2]f32{{640,360}, {1280,720}, {1920,1080}}
    for size in sizes {
        for resume_available in ([?]bool{false,true}) {
            state := State{title = "test title", resume_available = resume_available}
            view, action := update(&state, c.Input{width=size[0], height=size[1]})
            testing.expect(t, view.title == state.title && action == .None)
            testing.expect(t, view.title_font_size > view.font_size)
            testing.expect(t, view.title_bounds.y >= 0)
            testing.expect(t, view.title_bounds.y + view.title_bounds.height < view.buttons[0].bounds.y)
            testing.expect(t, view.title_bounds.x + view.title_bounds.width/2 == size[0]/2)
            testing.expect(t, view.button_count == menu_count(resume_available))
            for button in view.buttons[:view.button_count] {
                r := button.bounds
                testing.expect(t, r.x >= 0 && r.y >= 0)
                testing.expect(t, r.x+r.width <= size[0] && r.y+r.height <= size[1])
                testing.expect(t, r.x+r.width/2 == size[0]/2)
                testing.expect(t, !contains(r, r.x+r.width, r.y))
            }
        }
    }
}
