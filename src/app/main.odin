package main

import "core:fmt"
import "core:os"
import "core:mem"
import "../config"
import "../logic"
import "../render"
import "../ui"
import c "../contracts"

main :: proc() {
    when DEVELOPMENT_RELOAD {
        if len(os.args) == 2 && os.args[1] == "--reload-smoke" {
            if !reload_smoke() { os.exit(1) }
            return
        }
    }
    if !run() { os.exit(1) }
}

run :: proc() -> bool {
    data := load_reload_data(INITIAL_LEVEL_PATH)
    if data == nil { return false }
    defer { destroy_reload_data(data) }
    if !render.open(data.text.window_title) {
        fmt.eprintln("Unable to initialize the game window and graphics context.")
        return false
    }
    defer render.close()
    if !render.init_sprites(sprite_paths(data.catalog)) { return false }
    start_play := false
    for {
        next, ok := run_level(data,start_play)
        if next == nil { return ok }
        destroy_reload_data(data)
        data = next
        render.set_title(data.text.window_title)
        start_play = true
    }
}

run_level :: proc(data: ^Reload_Data, start_play: bool) -> (^Reload_Data, bool) {
    allocator := mem.dynamic_arena_allocator(&data.arena)
    text, catalog, level, bindings := data.text, data.catalog, data.level, data.bindings
    menu := ui.State{title = text.menu_title, labels = {text.play, text.load, text.settings, text.exit_game}}
    game, fleet := new_level_runtime(data)
    defer logic.destroy_transports(&fleet,context.allocator)
    scene: ui.Scene_State
    targets := make([]c.Building_Target, len(level.buildings), allocator)
    power_sources := make([]bool, len(level.buildings), allocator)
    power_consumers := make([]bool, len(level.buildings), allocator)
    descriptions := make([]render.Building_Draw, len(level.buildings), allocator)
    sizes := make([]c.Vector2, len(level.buildings), allocator)
    always_on := make([]bool, len(level.buildings), allocator)
    for &description, i in descriptions {
        definition, found := config.find_building(catalog, level.buildings[i].building_id)
        assert(found) // Level references were validated before opening the window.
        power_sources[i] = definition.power_output_kw > 0
        power_consumers[i] = definition.power_need_kw > 0
        description.color = definition.color
        description.code = definition.code
        description.sprite = definition.sprite
        always_on[i] = definition.always_on
        sizes[i] = {definition.width, definition.height}
    }
    camera := DEFAULT_CAMERA
    in_game := start_play
    if start_play { logic.dispatch_transports(&fleet,&game,catalog.buildings) }
    skip_time := true
    for !render.should_close() {
        input := render.poll_input(bindings,DEVELOPMENT_RELOAD)
        elapsed := skip_time ? f64(0) : render.elapsed_seconds()
        skip_time = false
        if input.reload_requested {
            // Path identifies the current level source, not a newly selected level.
            next := prepare_reload(INITIAL_LEVEL_PATH,render.init_sprites)
            if next != nil {
                fmt.eprintf("Reload complete: restarted %s from fresh configuration.\n",INITIAL_LEVEL_PATH)
                render.finish_reload_frame()
                free_all(context.temp_allocator)
                return next,true
            }
            elapsed = 0
            skip_time = true // Discard disk/GPU staging time on the next frame too.
            scene.right_pending = false
        }
        ui.advance_notice(&scene, elapsed)
        if in_game {
            if input.focused && input.back && scene.inspected_id == "" {
                scene.right_pending = false
                in_game = false
            } else {
                notice := measured_notice_view(&scene, input.width, input.height)
                hud := ui.hud_view(input.width, input.height)
                hud.clock = clock_text(text.hud_clock_format,logic.clock_snapshot(game.clock))
                clock_rows := render.wrap_info_lines([]string{hud.clock},hud.bounds.width)
                hud.bounds = ui.hud_view(input.width,input.height,len(clock_rows)).bounds
                live_station := level.space_station
                live_station.subjects = fleet.stock
                station_text := station_lines(catalog,live_station,text.entries,context.temp_allocator,fleet.available)
                station_width := ui.station_bounds(input.width,input.height,1).width
                hud.station_rows = render.wrap_info_lines(station_text,station_width)
                hud.station_bounds = ui.station_bounds(input.width,input.height,len(hud.station_rows),notice.bounds.y)
                hud.transport_bounds = ui.transport_bounds(input.width,input.height,transport_box_count(&fleet),hud.bounds.y+hud.bounds.height,notice.bounds.y)
                hud.info_bounds = ui.inspector_bounds(&scene, input.width, input.height)
                if input.focused {
                    // A drag keeps panning across overlays, but zooming over them is ignored.
                    pan_camera(&camera, input.pan_x, input.pan_y)
                    if !ui.over_overlay(input, notice, hud) {
                        zoom_camera(&camera, input.zoom, input.mouse_x, input.mouse_y, input.width, input.height)
                    }
                }
                // Speed changes apply before this frame's time is simulated.
                if change, requested := ui.speed_command(input); requested {
                    logic.change_speed(&game.clock, change)
                }
                // Time-based rules run once per fixed tick, never once per frame.
                ticks := logic.advance_clock(&game.clock, elapsed)
                for _ in 0..<ticks {
                    logic.step(&game)
                    logic.step_transports(&fleet,&game,catalog.buildings)
                }
                hud.transport_bounds = ui.transport_bounds(input.width,input.height,transport_box_count(&fleet),hud.bounds.y+hud.bounds.height,notice.bounds.y)
                hud.clock = clock_text(text.hud_clock_format, logic.clock_snapshot(game.clock))
                clock_rows = render.wrap_info_lines([]string{hud.clock},hud.bounds.width)
                hud.bounds = ui.hud_view(input.width,input.height,len(clock_rows)).bounds
                for &description, i in descriptions {
                    building := logic.snapshot(&game, i)
                    description.bounds = building_screen_bounds(camera, building.position, sizes[i], input.width, input.height)
                    description.level_bar = level_bar_bounds(description.bounds, always_on[i])
                    targets[i] = {id=building.id, bounds=description.bounds}
                }
                if command, clicked := ui.scene_command(input, targets, notice, hud); clicked {
                    result := logic.toggle(&game, command)
                    switch result {
                    case .Insufficient_Health: ui.show_notice(&scene, text.notice_insufficient_health)
                    case .Insufficient_Power: ui.show_notice(&scene, text.notice_insufficient_power)
                    case .Generator_Required: ui.show_notice(&scene, text.notice_generator_required)
                    case .Control_Unit_Locked: ui.show_notice(&scene, text.notice_control_unit_locked)
                    case .Always_On_Locked: ui.show_notice(&scene, text.notice_always_on_locked)
                    case .Applied: logic.dispatch_transports(&fleet,&game,catalog.buildings)
                    case .None, .Unknown_Building:
                    }
                }
                ui.update_inspector(&scene, input, targets, notice, hud)
                hud.info_bounds = ui.inspector_bounds(&scene, input.width, input.height)
                power := logic.balance(&game)
                for &description, i in descriptions {
                    building := logic.snapshot(&game, i)
                    if building.id == scene.inspected_id {
                        definition, found := config.find_building(catalog, building.building_id)
                        assert(found)
                        lines := building_info_lines(building, definition, text, game.buildings[i], catalog, fleet.subjects[:])
                        rows := render.wrap_info_lines(lines[:len(lines)-1],hud.info_bounds.width)
                        hint := render.wrap_info_lines([]string{text.entries["building_info_scroll"]},hud.info_bounds.width)
                        hud.info_rows = ui.inspector_visible_lines(&scene,input,hud.info_bounds,rows,hint)
                        hud.info_title_color = definition.color
                    }
                    apply_building_activity(&description,building)
                    // Only configured lines are shown: generators like the Solar Panel have no need line.
                    if power_consumers[i] {
                        description.power_need = power_text(text.power_need_format, building.power_need_kw)
                    }
                    if power_sources[i] {
                        description.power_output = power_text(text.power_output_format, building.power_output_kw)
                    }
                    if building.building_id == c.CONTROL_UNIT_ID {
                        description.power_available = power_text(text.power_available_format, power.available_kw)
                    }
                }
                notice = measured_notice_view(&scene,input.width,input.height)
                hud.transport_bounds = ui.transport_bounds(input.width,input.height,transport_box_count(&fleet),hud.bounds.y+hud.bounds.height,notice.bounds.y)
                cards := transport_cards(&fleet,catalog,text.entries,hud.transport_bounds,0,true)
                for &card in cards { card.rows = render.wrap_info_lines(card.lines,hud.transport_bounds.width) }
                transport_input := input
                if ui.contains(hud.info_bounds,input.mouse_x,input.mouse_y) || ui.contains(hud.station_bounds,input.mouse_x,input.mouse_y) { transport_input.zoom = 0 }
                hud.transports = ui.layout_transport_cards(&scene,transport_input,hud.transport_bounds,cards)
                live_station.subjects = fleet.stock
                station_text = station_lines(catalog,live_station,text.entries,context.temp_allocator,fleet.available)
                station_rows := render.wrap_info_lines(station_text,station_width)
                hud.station_bounds = ui.station_bounds(input.width,input.height,len(station_rows),notice.bounds.y)
                station_input := input
                if ui.contains(hud.info_bounds,input.mouse_x,input.mouse_y) { station_input.zoom = 0 }
                station_hint: []c.Info_Row
                if len(station_rows) > ui.info_row_slots(hud.station_bounds) {
                    station_hint = render.wrap_info_lines([]string{text.entries["info_scroll_hint"]},station_width)
                }
                hud.station_rows = ui.info_visible_rows(&scene.station_scroll,station_input,hud.station_bounds,station_rows,station_hint)
                render.draw_scene(descriptions, notice, hud, landing_draws(&fleet,catalog,targets,camera,input.width,input.height))
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
            logic.reset_transports(&fleet,level.space_station,level.buildings,level.subjects)
            logic.dispatch_transports(&fleet,&game,catalog.buildings)
            scene = {}
            camera = DEFAULT_CAMERA
            menu.status = ""
            in_game = true
        case .Load: menu.status = text.load_unavailable
        case .Settings: menu.status = text.settings_unavailable
        case .Exit: return nil,true
        case .None:
        }
        view.status = menu.status
        render.draw(view)
        free_all(context.temp_allocator)
    }
    return nil,true
}
