package main

import "core:fmt"
import "core:os"
import "core:mem"
import "../localization"
import "../config"
import "../logic"
import "../render"
import "../ui"
import c "../contracts"

main :: proc() {
    if !run() { os.exit(1) }
}

run :: proc() -> bool {
    arena: mem.Dynamic_Arena
    // This Odin version's dynamic arena uses a fixed alignment; JSON maps need 64 bytes.
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    text, ok := localization.load_english(mem.dynamic_arena_allocator(&arena))
    if !ok { return false }
    catalog, level, config_ok := config.load(text.entries, mem.dynamic_arena_allocator(&arena))
    if !config_ok { return false }
    if !render.open(text.window_title) {
        fmt.eprintln("Unable to initialize the game window and graphics context.")
        return false
    }
    defer render.close()

    menu := ui.State{title = text.menu_title, labels = {text.play, text.load, text.settings, text.exit_game}}
    game := logic.new_session(level.buildings, catalog.buildings, mem.dynamic_arena_allocator(&arena))
    scene: ui.Scene_State
    targets := make([]c.Building_Target, len(level.buildings), mem.dynamic_arena_allocator(&arena))
    power_sources := make([]bool, len(level.buildings), mem.dynamic_arena_allocator(&arena))
    descriptions := make([]render.Building_Draw, len(level.buildings), mem.dynamic_arena_allocator(&arena))
    for &description, i in descriptions {
        definition, found := config.find_building(catalog, level.buildings[i].building_id)
        assert(found) // Level references were validated before opening the window.
        power_sources[i] = definition.power_output_kw > 0
        description.color = definition.color
        description.code = definition.code
        description.bounds.width = definition.width * WORLD_SCALE
        description.bounds.height = definition.height * WORLD_SCALE
    }
    in_game := false
    for !render.should_close() {
        input := render.poll_input()
        ui.advance_notice(&scene, render.elapsed_seconds())
        if in_game {
            if input.focused && input.back {
                in_game = false
            } else {
                for &description, i in descriptions {
                    building := logic.snapshot(&game, i)
                    description.bounds = building_screen_bounds(building.position,
                        description.bounds.width, description.bounds.height, input.width, input.height)
                    targets[i] = {id=building.id, bounds=description.bounds}
                }
                notice := ui.notice_view(&scene, input.width, input.height)
                if command, clicked := ui.scene_command(input, targets, notice); clicked {
                    result := logic.toggle(&game, command)
                    switch result {
                    case .Insufficient_Power: ui.show_notice(&scene, text.notice_insufficient_power)
                    case .Generator_Required: ui.show_notice(&scene, text.notice_generator_required)
                    case .Control_Unit_Locked: ui.show_notice(&scene, text.notice_control_unit_locked)
                    case .None, .Applied, .Unknown_Building:
                    }
                }
                power := logic.balance(&game)
                for &description, i in descriptions {
                    building := logic.snapshot(&game, i)
                    description.active = building.active
                    description.power_need = power_text(text.power_need_format, building.power_need_kw)
                    if power_sources[i] {
                        description.power_output = power_text(text.power_output_format, building.power_output_kw)
                    }
                    if building.building_id == c.CONTROL_UNIT_ID {
                        description.power_available = power_text(text.power_available_format, power.available_kw)
                    }
                }
                render.draw_scene(descriptions, ui.notice_view(&scene, input.width, input.height))
                for &description in descriptions {
                    description.power_output = ""
                    description.power_need = ""
                    description.power_available = ""
                }
                free_all(context.temp_allocator)
                continue
            }
        }
        view, action := ui.update(&menu, input)
        switch action {
        case .Play:
            logic.reset(&game, level.buildings)
            scene = {}
            menu.status = ""
            in_game = true
        case .Load: menu.status = text.load_unavailable
        case .Settings: menu.status = text.settings_unavailable
        case .Exit: return true
        case .None:
        }
        view.status = menu.status
        render.draw(view)
        free_all(context.temp_allocator)
    }
    return true
}
