package render

import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import c "../contracts"
import rl "vendor:raylib"

Wheel_Direction :: enum { Up, Down }
Binding :: union { rl.KeyboardKey, rl.MouseButton, Wheel_Direction }

// Resolved once at startup; polling never parses names.
Bindings :: struct {
    menu_up, menu_down, activate, back, select, zoom_in, zoom_out, pan: []Binding,
    speed_up, slow_down: []Binding,
}

// Names are "key:<raylib key>", "mouse:<raylib button>" or "wheel:<up|down>".
// The part after the colon is case-insensitive, e.g. "key:enter" or "key:KP_ADD".
parse_binding :: proc(name: string) -> (Binding, bool) {
    colon := strings.index_byte(name, ':')
    if colon < 0 { return nil, false }
    kind, value := name[:colon], name[colon+1:]
    switch kind {
    case "key":
        if key, ok := enum_from_name_fold(rl.KeyboardKey, value); ok && key != rl.KeyboardKey(0) { return key, true }
    case "mouse":
        if button, ok := enum_from_name_fold(rl.MouseButton, value); ok { return button, true }
    case "wheel":
        if strings.equal_fold(value, "up") { return Wheel_Direction.Up, true }
        if strings.equal_fold(value, "down") { return Wheel_Direction.Down, true }
    }
    return nil, false
}

@(private)
enum_from_name_fold :: proc($T: typeid, name: string) -> (T, bool) {
    values := reflect.enum_field_values(T)
    for field, i in reflect.enum_field_names(T) {
        if strings.equal_fold(field, name) { return T(values[i]), true }
    }
    return {}, false
}

// Binding slices and error strings belong to allocator.
resolve_bindings :: proc(config: c.Key_Bindings, allocator: mem.Allocator) -> (bindings: Bindings, error: string) {
    Action :: struct { name: string, inputs: []string, output: ^[]Binding, held: bool }
    actions := [?]Action{
        {"menu_up", config.menu_up, &bindings.menu_up, false},
        {"menu_down", config.menu_down, &bindings.menu_down, false},
        {"activate", config.activate, &bindings.activate, false},
        {"back", config.back, &bindings.back, false},
        {"select", config.select, &bindings.select, false},
        {"zoom_in", config.zoom_in, &bindings.zoom_in, false},
        {"zoom_out", config.zoom_out, &bindings.zoom_out, false},
        {"pan", config.pan, &bindings.pan, true},
        {"speed_up", config.speed_up, &bindings.speed_up, false},
        {"slow_down", config.slow_down, &bindings.slow_down, false},
    }
    for action in actions {
        codes := make([]Binding, len(action.inputs), allocator)
        for input, i in action.inputs {
            code, ok := parse_binding(input)
            if !ok {
                return {}, fmt.aprintf("%s[%d]: unknown input %q; use key:<name>, mouse:<left|right|middle> or wheel:<up|down>", action.name, i, input, allocator=allocator)
            }
            // The wheel has no held state, so it cannot drive a drag.
            if _, is_wheel := code.(Wheel_Direction); is_wheel && action.held {
                return {}, fmt.aprintf("%s[%d]: %q cannot be held; use a key or mouse button", action.name, i, input, allocator=allocator)
            }
            codes[i] = code
        }
        action.output^ = codes
    }
    return
}

// Fixed development chord has priority over configurable bindings and overlays.
reload_input :: proc(input: c.Input, development, control_down, r_pressed: bool) -> c.Input {
    if development && input.focused && control_down && r_pressed {
        return {width=input.width,height=input.height,mouse_x=input.mouse_x,mouse_y=input.mouse_y,focused=true,reload_requested=true}
    }
    return input
}

poll_input :: proc(bindings: Bindings, development: bool = false) -> c.Input {
    mouse := rl.GetMousePosition()
    delta := rl.GetMouseDelta()
    wheel := rl.GetMouseWheelMove()
    panning := held(bindings.pan)
    input := c.Input{
        width = f32(rl.GetScreenWidth()), height = f32(rl.GetScreenHeight()),
        mouse_x = mouse.x, mouse_y = mouse.y,
        zoom = steps(bindings.zoom_in, wheel) - steps(bindings.zoom_out, wheel),
        pan_x = panning ? delta.x : 0, pan_y = panning ? delta.y : 0,
        mouse_moved = delta.x != 0 || delta.y != 0,
        click = pressed(bindings.select, wheel),
        right_pressed = rl.IsMouseButtonPressed(.RIGHT),
        right_released = rl.IsMouseButtonReleased(.RIGHT),
        up = pressed(bindings.menu_up, wheel), down = pressed(bindings.menu_down, wheel),
        activate = pressed(bindings.activate, wheel),
        focused = rl.IsWindowFocused(),
        back = pressed(bindings.back, wheel),
        speed_up = pressed(bindings.speed_up, wheel), slow_down = pressed(bindings.slow_down, wheel),
    }
    return reload_input(input,development,rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL),rl.IsKeyPressed(.R))
}

@(private)
pressed :: proc(codes: []Binding, wheel: f32) -> bool {
    return steps(codes, wheel) > 0
}

// Wheel bindings count their notches; keys and buttons count one per press.
@(private)
steps :: proc(codes: []Binding, wheel: f32) -> (total: f32) {
    for code in codes {
        switch v in code {
        case rl.KeyboardKey: if rl.IsKeyPressed(v) { total += 1 }
        case rl.MouseButton: if rl.IsMouseButtonPressed(v) { total += 1 }
        case Wheel_Direction:
            if v == .Up && wheel > 0 { total += wheel }
            if v == .Down && wheel < 0 { total -= wheel }
        }
    }
    return
}

@(private)
held :: proc(codes: []Binding) -> bool {
    for code in codes {
        #partial switch v in code {
        case rl.KeyboardKey: if rl.IsKeyDown(v) { return true }
        case rl.MouseButton: if rl.IsMouseButtonDown(v) { return true }
        }
    }
    return false
}
