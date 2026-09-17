package render

import "core:strings"
import "core:testing"
import c "../contracts"
import rl "vendor:raylib"

@(test)
binding_names :: proc(t: ^testing.T) {
    code, ok := parse_binding("key:enter")
    testing.expect(t, ok && code == Binding(rl.KeyboardKey.ENTER))
    code, ok = parse_binding("key:KP_ADD")
    testing.expect(t, ok && code == Binding(rl.KeyboardKey.KP_ADD))
    code, ok = parse_binding("mouse:Middle")
    testing.expect(t, ok && code == Binding(rl.MouseButton.MIDDLE))
    code, ok = parse_binding("wheel:down")
    testing.expect(t, ok && code == Binding(Wheel_Direction.Down))
    invalid := [?]string{"enter", "key:", "key:enterr", "key:key_null", "Key:enter", "mouse:up", "wheel:left", ""}
    for name in invalid {
        _, found := parse_binding(name)
        testing.expect(t, !found, name)
    }
}

@(test)
binding_resolution :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    config := c.Key_Bindings{
        version = 1,
        menu_up = {"key:up"}, menu_down = {"key:down"}, activate = {"key:enter", "key:space"},
        back = {"key:escape"}, select = {"mouse:left"}, zoom_in = {"wheel:up", "key:equal"},
        zoom_out = {"wheel:down"}, pan = {"mouse:right", "mouse:middle"},
        speed_up = {"key:e"}, slow_down = {"key:q"},
        overview_buildings = {"key:b"}, overview_subjects = {"key:s"},
    }
    bindings, error := resolve_bindings(config, context.temp_allocator)
    testing.expect(t, error == "", error)
    testing.expect(t, len(bindings.zoom_in) == 2 && bindings.zoom_in[1] == Binding(rl.KeyboardKey.EQUAL))
    testing.expect(t, len(bindings.pan) == 2 && bindings.pan[0] == Binding(rl.MouseButton.RIGHT))
    testing.expect(t, bindings.speed_up[0] == Binding(rl.KeyboardKey.E) && bindings.slow_down[0] == Binding(rl.KeyboardKey.Q))
    testing.expect(t, bindings.overview_buildings[0] == Binding(rl.KeyboardKey.B) && bindings.overview_subjects[0] == Binding(rl.KeyboardKey.S))
    unknown := config
    unknown.back = {"key:esc"}
    _, error = resolve_bindings(unknown, context.temp_allocator)
    testing.expect(t, strings.contains(error, "back[0]"), error)
    wheel_pan := config
    wheel_pan.pan = {"mouse:right", "wheel:up"}
    _, error = resolve_bindings(wheel_pan, context.temp_allocator)
    testing.expect(t, strings.contains(error, "cannot be held"), error)
}
