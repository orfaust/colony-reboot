package main

import "core:mem"
import "core:fmt"
import "../config"
import "../localization"
import "../render"
import "../logic"

// Explicit capability, not ODIN_DEBUG or a guessed parent process identity.
DEVELOPMENT_RELOAD :: #config(DEVELOPMENT_RELOAD, false)
INITIAL_LEVEL_PATH :: "assets/levels/level_0.json"
Reload_Data :: struct {
    arena: mem.Dynamic_Arena,
    text: localization.Text,
    catalog: config.Catalog,
    level: config.Level,
    bindings: render.Bindings,
}

// Heap address is stable: allocator handles point into this arena. Never copy it.
load_reload_data :: proc(level_path: string) -> ^Reload_Data {
    data := new(Reload_Data)
    mem.dynamic_arena_init(&data.arena,alignment=64)
    allocator := mem.dynamic_arena_allocator(&data.arena)
    ok := false
    defer { if !ok { destroy_reload_data(data) } }
    data.text, ok = localization.load_english(allocator)
    if !ok { return nil }
    data.catalog, data.level, ok = config.load(data.text.entries,allocator,level_path)
    if !ok { return nil }
    keys, keys_ok := config.load_key_bindings(allocator)
    ok = keys_ok
    if !ok { return nil }
    error: string
    data.bindings, error = render.resolve_bindings(keys,allocator)
    ok = error == ""
    if !ok { fmt.eprintf("Invalid %s: %s\n",config.KEY_BINDINGS_PATH,error); return nil }
    return data
}
destroy_reload_data :: proc(data: ^Reload_Data) {
    if data == nil { return }
    mem.dynamic_arena_destroy(&data.arena)
    free(data)
}

// Game arrays belong to the data arena; fleet manifests use the heap and must be
// destroyed before that arena. Fresh constructors reset clock, people and queues.
new_level_runtime :: proc(data: ^Reload_Data) -> (logic.State, logic.Transport_State) {
    game := logic.new_session(data.level.buildings,data.catalog.buildings,mem.dynamic_arena_allocator(&data.arena))
    station, _ := config.find_station(data.catalog,data.level.space_station.station_id)
    fleet := logic.new_transports(station,data.level.space_station,data.catalog.ships,data.level.buildings,data.level.subjects,context.allocator,data.catalog.buildings,data.catalog.subjects)
    return game,fleet
}

// Caller keeps its old session until this succeeds. Sprite staging must also be
// atomic; callback injection permits headless rollback tests without GPU handles.
prepare_reload :: proc(level_path: string, sprites: proc([]string)->bool) -> ^Reload_Data {
    candidate := load_reload_data(level_path)
    if candidate == nil { fmt.eprintln("Reload rejected: fix the diagnostic above and press Ctrl+R again. Current session preserved."); return nil }
    if !sprites(sprite_paths(candidate.catalog)) {
        destroy_reload_data(candidate)
        fmt.eprintln("Reload rejected: sprite staging failed; current session preserved.")
        return nil
    }
    return candidate
}
