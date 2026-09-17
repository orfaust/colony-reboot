package config

import "core:fmt"
import "core:mem"
import "core:os"
import c "../contracts"

KEY_BINDINGS_RELATIVE_PATH :: "key_bindings.json"

// Structure only: every action needs at least one distinct input name. Whether a
// name denotes a real key is checked by the renderer, which owns the key tables.
decode_key_bindings :: proc(data: []byte, allocator: mem.Allocator) -> (bindings: c.Key_Bindings, error: string) {
    error = parse_typed(data, &bindings, allocator)
    if error != "" { return }
    if bindings.version != 1 { return {}, "version: expected 1" }
    Action :: struct { name: string, inputs: []string }
    actions := [?]Action{
        {"menu_up", bindings.menu_up}, {"menu_down", bindings.menu_down},
        {"activate", bindings.activate}, {"back", bindings.back}, {"select", bindings.select},
        {"zoom_in", bindings.zoom_in}, {"zoom_out", bindings.zoom_out}, {"pan", bindings.pan},
        {"speed_up", bindings.speed_up}, {"slow_down", bindings.slow_down},
        {"overview_buildings", bindings.overview_buildings}, {"overview_subjects", bindings.overview_subjects},
    }
    for action in actions {
        if len(action.inputs) == 0 {
            return {}, fmt.aprintf("%s: bind at least one input", action.name, allocator=allocator)
        }
        for input, i in action.inputs {
            for previous in action.inputs[:i] {
                if previous == input { return {}, fmt.aprintf("%s[%d]: duplicate input %q", action.name, i, input, allocator=allocator) }
            }
        }
    }
    return
}

load_key_bindings :: proc(allocator: mem.Allocator, profile: Profile = DEFAULT_PROFILE) -> (c.Key_Bindings, bool) {
    path := profile_path(profile, KEY_BINDINGS_RELATIVE_PATH, allocator)
    data, ok := os.read_entire_file(path)
    if !ok { fmt.eprintf("Cannot read %s. Run from the repository root, or select another profile with --config <name>.\n", path); return {}, false }
    defer delete(data)
    bindings, error := decode_key_bindings(data, allocator)
    if error != "" { fmt.eprintf("Invalid %s: %s\n", path, error); return {}, false }
    return bindings, true
}
