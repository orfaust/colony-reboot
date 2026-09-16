package main

import "core:testing"
import "core:os"
import "core:strings"
import "core:fmt"
import "../logic"

reload_test_sprites_ok :: proc(paths: []string) -> bool { return true }
reload_test_sprites_fail :: proc(paths: []string) -> bool { return false }

@(test)
reload_is_transactional_and_reconstructs_runtime :: proc(t: ^testing.T) {
    old := load_reload_data(INITIAL_LEVEL_PATH)
    testing.expect(t,old != nil)
    if old == nil { return }
    defer destroy_reload_data(old)
    game, fleet := new_level_runtime(old)
    defer logic.destroy_transports(&fleet,context.allocator)
    game.clock.ticks = 123
    game.clock.pending_ticks = 0.5
    fleet.next_landing_ticket = 42
    fleet.evacuation_pending[0] = true
    fleet.evacuation_started[0] = true
    old_title := old.text.window_title
    failed := prepare_reload(INITIAL_LEVEL_PATH,reload_test_sprites_fail)
    testing.expect(t,failed == nil && game.clock.ticks == 123 && fleet.next_landing_ticket == 42)
    testing.expect(t,old.text.window_title == old_title && fleet.evacuation_pending[0] && fleet.evacuation_started[0])
    path := "build/reload-valid-level-test.json"
    testing.expect(t,!os.exists(path))
    if os.exists(path) { return }
    defer os.remove(path)
    source, read_ok := os.read_entire_file(INITIAL_LEVEL_PATH)
    testing.expect(t,read_ok)
    if !read_ok { return }
    defer delete(source)
    quoted_id := fmt.aprintf("\"%s\"",old.level.buildings[0].id)
    defer delete(quoted_id)
    changed, _ := strings.replace_all(string(source),quoted_id,`"reload-fresh-building"`,context.allocator)
    defer delete(changed)
    testing.expect(t,os.write_entire_file(path,transmute([]byte)changed))
    next := prepare_reload(path,reload_test_sprites_ok)
    testing.expect(t,next != nil)
    if next == nil { return }
    defer destroy_reload_data(next)
    fresh, fresh_fleet := new_level_runtime(next)
    defer logic.destroy_transports(&fresh_fleet,context.allocator)
    testing.expect(t,next != old && next.level.level == old.level.level)
    testing.expect(t,&next.level.buildings[0] != &old.level.buildings[0])
    testing.expect(t,next.level.buildings[0].id == "reload-fresh-building" && old.level.buildings[0].id != "reload-fresh-building")
    testing.expect(t,fresh.clock.ticks == 0 && fresh.clock.pending_ticks == 0 && fresh.clock.speed_index == 0)
    testing.expect(t,fresh_fleet.count == 0 && fresh_fleet.next_landing_ticket == 0)
    for value in fresh_fleet.stock_fraction { testing.expect(t,value == 0) }
    for value in fresh_fleet.reserved { testing.expect(t,value == 0) }
    for value in fresh_fleet.evacuation_pending { testing.expect(t,!value) }
    for value in fresh_fleet.evacuation_started { testing.expect(t,!value) }
    for subject in fresh_fleet.subjects { testing.expect(t,!subject.evacuating && !subject.evacuation_reserved) }
    for stock, i in fresh_fleet.stock { testing.expect(t,stock.units == next.level.space_station.subjects[i].units) }
}

@(test)
reload_rejects_bad_json_and_references_without_touching_old_data :: proc(t: ^testing.T) {
    // Test-owned path only; shipped/editable files are never modified.
    path := "build/reload-invalid-level-test.json"
    testing.expect(t,!os.exists(path))
    if os.exists(path) { return }
    defer os.remove(path)
    old := load_reload_data(INITIAL_LEVEL_PATH)
    testing.expect(t,old != nil)
    if old == nil { return }
    defer destroy_reload_data(old)
    for source in ([?]string{"{",  `{"version":1,"level":0,"buildings":[],"subjects":[],"space_station":{"station_id":"unknown-reload-station","distance":0,"resources":[],"subjects":[]}}`}) {
        testing.expect(t,os.write_entire_file(path,transmute([]byte)source))
        candidate := prepare_reload(path,reload_test_sprites_ok)
        testing.expect(t,candidate == nil)
        testing.expect(t,len(old.level.buildings) > 0 && old.text.window_title != "")
    }
}
