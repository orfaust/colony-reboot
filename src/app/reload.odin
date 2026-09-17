package main

import "core:mem"
import "core:fmt"
import "../config"
import "../localization"
import "../render"
import "../logic"

// Explicit capability, not ODIN_DEBUG or a guessed parent process identity.
DEVELOPMENT_RELOAD :: #config(DEVELOPMENT_RELOAD, false)
// Level file of the default profile, repository-relative. Tests and smoke tools use
// it directly; the application derives the path from the selected profile instead.
INITIAL_LEVEL_PATH :: "assets/config/default/levels/level_0.json"
Reload_Data :: struct {
    arena: mem.Dynamic_Arena,
    text: localization.Text,
    catalog: config.Catalog,
    level: config.Level,
    bindings: render.Bindings,
    // The profile every catalog file was read from, and the repository-relative
    // source of `level` (reload re-reads exactly this file). Both are borrowed and
    // must outlive this value: the profile name is a command-line string constant.
    profile: config.Profile,
    level_path: string,
    // Precomposed per-building notice text keyed by template + instance id; persistent
    // arena storage so the bounded notice log never allocates per event.
    building_notices: Building_Notices,
    // Preallocated ring for the grouped power-shed notice, the only notice whose text
    // depends on runtime state; persistent arena storage, allocation-free per event.
    power_shed: Power_Shed_Notices,
}

// Heap address is stable: allocator handles point into this arena. Never copy it.
// `profile` selects the configuration directory every file except `level_path` is
// read from; `level_path` stays explicit because reload can target a test file.
load_reload_data :: proc(level_path: string, profile: config.Profile = config.DEFAULT_PROFILE) -> ^Reload_Data {
    data := new(Reload_Data)
    mem.dynamic_arena_init(&data.arena,alignment=64)
    data.profile = profile
    data.level_path = level_path
    allocator := mem.dynamic_arena_allocator(&data.arena)
    ok := false
    defer { if !ok { destroy_reload_data(data) } }
    text_path := config.profile_path(profile,"localization/en.json",allocator)
    data.text, ok = localization.load_english(text_path,allocator)
    if !ok { return nil }
    data.catalog, data.level, ok = config.load(data.text.entries,allocator,level_path,profile)
    if !ok { return nil }
    data.building_notices = build_building_notices(BUILDING_NOTICE_KEYS,data.level.buildings,data.catalog,data.text.entries,allocator)
    data.power_shed = build_power_shed_notices(data.text.entries["notice_power_shed"],data.building_notices.identities,data.level.buildings,allocator)
    keys, keys_ok := config.load_key_bindings(allocator,profile)
    ok = keys_ok
    if !ok { return nil }
    error: string
    data.bindings, error = render.resolve_bindings(keys,allocator)
    ok = error == ""
    if !ok { fmt.eprintf("Invalid %s: %s\n",config.profile_path(profile,config.KEY_BINDINGS_RELATIVE_PATH,allocator),error); return nil }
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
    // Materialized slots start empty until coverage is derived from the level's
    // initial assignments and the fresh subject state; the scheduler then fills the
    // remaining open slots.
    logic.derive_staffing(&game,&fleet)
    logic.schedule_staffing(&game,&fleet)
    return game,fleet
}

// Caller keeps its old session until this succeeds. Sprite staging must also be
// atomic; callback injection permits headless rollback tests without GPU handles.
prepare_reload :: proc(level_path: string, sprites: proc([]string)->bool, profile: config.Profile = config.DEFAULT_PROFILE) -> ^Reload_Data {
    candidate := load_reload_data(level_path,profile)
    if candidate == nil { fmt.eprintln("Reload rejected: fix the diagnostic above and press Ctrl+R again. Current session preserved."); return nil }
    if !sprites(sprite_paths(candidate.catalog)) {
        destroy_reload_data(candidate)
        fmt.eprintln("Reload rejected: sprite staging failed; current session preserved.")
        return nil
    }
    return candidate
}
