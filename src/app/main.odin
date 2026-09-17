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
    // Profile selection is a startup contract: resolve it before allocating any
    // session state so a typo fails fast with an actionable message.
    name, argument_error := config.parse_profile_name(os.args,context.allocator)
    if argument_error != "" { fmt.eprintf("Configuration error: %s\n",argument_error); os.exit(2) }
    profile, profile_error := config.resolve_profile(name,context.allocator)
    if profile_error != "" { fmt.eprintf("Configuration error: %s\n",profile_error); os.exit(2) }
    if profile.name != config.DEFAULT_PROFILE_NAME {
        fmt.eprintf("Configuration profile: %s (%s/%s)\n",profile.name,config.CONFIG_ROOT,profile.name)
    }
    if !run(profile) { os.exit(1) }
}

run :: proc(profile: config.Profile) -> bool {
    level_path := config.profile_path(profile,config.DEFAULT_LEVEL,context.allocator)
    defer delete(level_path)
    data := load_reload_data(level_path,profile)
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

// The menu is the pause screen. While it is shown (`in_game == false`) the session
// must not advance: this is the only place frame time becomes simulation ticks, so
// a paused menu consumes no time and cannot catch up after Resume.
session_ticks :: proc(in_game: bool, clock: ^logic.Clock, elapsed_seconds: f64) -> int {
    if !in_game { return 0 }
    return logic.advance_clock(clock, elapsed_seconds)
}

run_level :: proc(data: ^Reload_Data, start_play: bool) -> (^Reload_Data, bool) {
    allocator := mem.dynamic_arena_allocator(&data.arena)
    text, catalog, level, bindings := data.text, data.catalog, data.level, data.bindings
    menu := ui.State{title = text.menu_title, labels = {text.resume_game, text.play, text.load, text.settings, text.exit_game}}
    game, fleet := new_level_runtime(data)
    defer logic.destroy_transports(&fleet,context.allocator)
    scene: ui.Scene_State
    targets := make([]c.Building_Target, len(level.buildings), allocator)
    descriptions := make([]render.Building_Draw, len(level.buildings), allocator)
    sizes := make([]c.Vector2, len(level.buildings), allocator)
    always_on := make([]bool, len(level.buildings), allocator)
    for &description, i in descriptions {
        definition, found := config.find_building(catalog, level.buildings[i].building_id)
        assert(found) // Level references were validated before opening the window.
        description.color = definition.color
        description.sprite = definition.sprite
        always_on[i] = definition.always_on
        sizes[i] = {definition.width, definition.height}
    }
    camera := DEFAULT_CAMERA
    in_game := start_play
    // A paused session makes Resume Game available; Play still starts a fresh one.
    menu.resume_available = start_play
    if start_play { logic.dispatch_transports(&fleet,&game,catalog.buildings) }
    skip_time := true
    for !render.should_close() {
        input := render.poll_input(bindings,DEVELOPMENT_RELOAD)
        elapsed := skip_time ? f64(0) : render.elapsed_seconds()
        skip_time = false
        if input.reload_requested {
            // Path identifies the current level source, not a newly selected level.
            next := prepare_reload(data.level_path,render.init_sprites,data.profile)
            if next != nil {
                fmt.eprintf("Reload complete: restarted %s from fresh configuration.\n",data.level_path)
                render.finish_reload_frame()
                free_all(context.temp_allocator)
                return next,true
            }
            elapsed = 0
            skip_time = true // Discard disk/GPU staging time on the next frame too.
            scene.right_pending = false
        }
        ui.advance_notice(&scene, elapsed)
        if in_game && input.focused && input.back && scene.modal != .None {
            // Escape closes the overview before it can close the inspector or the session.
            scene.modal = .None
            scene.modal_scroll = 0
            free_all(context.temp_allocator)
            continue
        }
        if in_game {
            if input.focused && input.back && scene.inspected_id == "" && scene.modal == .None {
                scene.right_pending = false
                in_game = false
                menu.resume_available = true
                menu.selected = 0
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
                // Overview toggles sit beside the notice panel and own their clicks.
                toggle_bounds := ui.modal_toggle_bounds(input.width, input.height)
                for &toggle, i in hud.toggles {
                    toggle.bounds = toggle_bounds[i]
                    toggle.label = text.entries[i == 0 ? "modal_buildings_toggle" : "modal_subjects_toggle"]
                }
                if input.focused {
                    if kind, clicked := ui.modal_toggle_command(input,hud.toggles,scene.modal); clicked {
                        scene.modal = kind
                        scene.modal_scroll = 0
                    } else if kind, toggled := ui.modal_key_toggle(scene.modal,input.toggle_buildings,input.toggle_subjects); toggled {
                        // Configurable B/S bindings mirror the buttons during play.
                        scene.modal = kind
                        scene.modal_scroll = 0
                    } else if scene.modal != .None && input.click && !ui.contains(ui.modal_bounds(input.width,input.height),input.mouse_x,input.mouse_y) {
                        // A click on the dimmed backdrop closes the overview.
                        scene.modal = .None
                        scene.modal_scroll = 0
                    }
                }
                hud.toggles[0].active = scene.modal == .Buildings
                hud.toggles[1].active = scene.modal == .Subjects
                hud.modal.kind = scene.modal // Overlay consumption sees the open modal this frame.
                if input.focused && scene.modal == .None {
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
                // While the menu is open the session is paused: session_ticks
                // returns zero, so the clock, subjects and transports stay frozen.
                ticks := session_ticks(in_game,&game.clock,elapsed)
                // The clock already holds the post-frame count; the loop reconstructs
                // the logical tick index so the hourly production step can run exactly
                // once per simulated hour even when a frame advances many ticks.
                first_tick := game.clock.ticks-i64(ticks)+1
                for step in 0..<ticks {
                    logic.step(&game)
                    // Coverage is derived first so this tick's hourly production runs on
                    // the staffing state committed at the end of the previous tick; the
                    // second derivation below settles movement before shedding.
                    logic.derive_staffing(&game,&fleet)
                    logic.step_production(&game,first_tick+i64(step))
                    // Fulfillment shares the same hour boundary, after production, so a
                    // subject draws from the stock its building produced this hour.
                    logic.step_need_fulfillment(&game,&fleet,first_tick+i64(step))
                    logic.step_subject_health(&fleet)
                    logic.step_medical(&game,&fleet)
                    logic.step_shifts(&game,&fleet)
                    logic.step_transports(&fleet,&game,catalog.buildings)
                    logic.commit_shift_handoffs(&game,&fleet)
                    // Movement has committed arrivals this tick; coverage is rebuilt
                    // before power evaluation and load shedding.
                    logic.derive_staffing(&game,&fleet)
                    // A negative balance force-stops the greatest active consumer in
                    // this same tick; generators and existing shutdown locks are kept.
                    logic.step_load_shedding(&game)
                    // Stale reservations were cancelled above; the scheduler refills
                    // open slots in the same tick.
                    logic.schedule_staffing(&game,&fleet)
                    // Every transition published by this tick becomes one bounded notice,
                    // in sequence order; all sheds are grouped into one notice. The
                    // queue is drained so it cannot overflow.
                    publish_event_notices(&scene,&game,text,data.building_notices,&data.power_shed)
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
                if scene.modal == .None {
                    if command, clicked := ui.scene_command(input, targets, notice, hud); clicked {
                        result := logic.toggle(&game, command)
                        switch result {
                        case .Insufficient_Health: show_building_notice(&scene,data.building_notices,"notice_insufficient_health",command.id,text.entries["notice_insufficient_health"])
                        case .Insufficient_Power: show_building_notice(&scene,data.building_notices,"notice_insufficient_power",command.id,text.entries["notice_insufficient_power"])
                        case .Generator_Required: show_building_notice(&scene,data.building_notices,"notice_generator_required",command.id,text.entries["notice_generator_required"])
                        case .Control_Unit_Locked: ui.show_notice(&scene, text.notice_control_unit_locked)
                        case .Always_On_Locked: show_building_notice(&scene,data.building_notices,"notice_always_on_locked",command.id,text.entries["notice_always_on_locked"])
                        case .Applied: logic.dispatch_transports(&fleet,&game,catalog.buildings)
                        case .None, .Unknown_Building:
                        }
                    }
                    ui.update_inspector(&scene, input, targets, notice, hud)
                }
                hud.info_bounds = ui.inspector_bounds(&scene, input.width, input.height)
                for &description, i in descriptions {
                    building := logic.snapshot(&game, i)
                    if building.id == scene.inspected_id {
                        definition, found := config.find_building(catalog, building.building_id)
                        assert(found)
                        coverage: [3]c.Staffing_Coverage
                        for role in logic.Subject_Role { coverage[int(role)] = logic.staffing_coverage(&game, i, role) }
                        stock := logic.stock_snapshot(&game,i)
                        // Frame-temporary resolved rates; the inspector consumes them
                        // synchronously and never retains them.
                        rates := make([]c.Production_Rate,len(stock),context.temp_allocator)
                        rate_count := logic.production_rates(&game,i,rates)
                        lines := building_info_lines(building, definition, text, game.buildings[i], catalog, fleet.subjects[:], coverage[:], stock, logic.production_status(&game,i), rates[:rate_count])
                        rows := render.wrap_info_lines(lines[:len(lines)-1],hud.info_bounds.width)
                        hint := render.wrap_info_lines([]string{text.entries["building_info_scroll"]},hud.info_bounds.width)
                        hud.info_rows = ui.inspector_visible_lines(&scene,input,hud.info_bounds,rows,hint)
                        hud.info_title_color = definition.color
                    }
                    apply_building_activity(&description,building)
                }
                notice = measured_notice_view(&scene,input.width,input.height)
                hud.transport_bounds = ui.transport_bounds(input.width,input.height,transport_box_count(&fleet),hud.bounds.y+hud.bounds.height,notice.bounds.y)
                cards := transport_cards(&fleet,catalog,text.entries,hud.transport_bounds,0,true)
                for &card in cards { card.rows = render.wrap_info_lines(card.lines,hud.transport_bounds.width) }
                transport_input := input
                if scene.modal != .None || ui.contains(hud.info_bounds,input.mouse_x,input.mouse_y) || ui.contains(hud.station_bounds,input.mouse_x,input.mouse_y) { transport_input.zoom = 0 }
                hud.transports = ui.layout_transport_cards(&scene,transport_input,hud.transport_bounds,cards)
                // An approval click is already consumed by the panel overlay above;
                // it only starts the ordinary mission the player selected.
                if approval, requested := ui.approve_command(input,hud.transports,hud.transport_bounds); requested {
                    logic.approve_transport(&fleet,approval.id)
                }
                live_station.subjects = fleet.stock
                station_text = station_lines(catalog,live_station,text.entries,context.temp_allocator,fleet.available)
                station_rows := render.wrap_info_lines(station_text,station_width)
                hud.station_bounds = ui.station_bounds(input.width,input.height,len(station_rows),notice.bounds.y)
                station_input := input
                if scene.modal != .None || ui.contains(hud.info_bounds,input.mouse_x,input.mouse_y) { station_input.zoom = 0 }
                station_hint: []c.Info_Row
                if len(station_rows) > ui.info_row_slots(hud.station_bounds) {
                    station_hint = render.wrap_info_lines([]string{text.entries["info_scroll_hint"]},station_width)
                }
                hud.station_rows = ui.info_visible_rows(&scene.station_scroll,station_input,hud.station_bounds,station_rows,station_hint)
                // The overview modal shadows the world; toggles stay drawn on top of it.
                if scene.modal != .None {
                    hud.modal = {kind=scene.modal,bounds=ui.modal_bounds(input.width,input.height),hint=text.entries["modal_scroll_hint"]}
                    grid_rows: []c.Modal_Row
                    switch scene.modal {
                    case .Buildings:
                        hud.modal.title = text.entries["modal_buildings_title"]
                        hud.modal.columns = building_grid_columns(text)
                        grid_rows = building_grid_rows(&game,catalog,text)
                    case .Subjects:
                        hud.modal.title = text.entries["modal_subjects_title"]
                        hud.modal.columns = subject_grid_columns(text)
                        grid_rows = subject_grid_rows(&game,&fleet,catalog,text)
                    case .None:
                    }
                    hud.modal.rows = ui.modal_visible_rows(&scene.modal_scroll,input,hud.modal.bounds,grid_rows)
                }
                render.draw_scene(descriptions, notice, hud, landing_draws(&fleet,catalog,targets,camera,input.width,input.height))
                free_all(context.temp_allocator)
                continue
            }
        }
        view, action := ui.update(&menu, input)
        switch action {
        case .Resume:
            // Continue the paused session exactly where it stopped; never reset it.
            menu.status = ""
            in_game = true
        case .Play:
            logic.reset(&game, level.buildings)
            logic.reset_transports(&fleet,level.space_station,level.buildings,level.subjects)
            logic.derive_staffing(&game,&fleet)
            logic.schedule_staffing(&game,&fleet)
            logic.dispatch_transports(&fleet,&game,catalog.buildings)
            scene = {}
            camera = DEFAULT_CAMERA
            menu.status = ""
            menu.resume_available = true
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
