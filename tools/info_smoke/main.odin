package info_smoke

import app "../../src/app"
import "../../src/render"
import "../../src/ui"
import "../../src/logic"
import c "../../src/contracts"
import "core:fmt"

// Localized production data and actual font metrics; no configuration files are edited.
main :: proc() {
    data := app.load_reload_data(app.INITIAL_LEVEL_PATH)
    assert(data != nil)
    defer app.destroy_reload_data(data)
    assert(render.open_info_smoke(data.text.window_title))
    defer render.close()
    assert(render.init_sprites(app.sprite_paths(data.catalog)))
    game, fleet := app.new_level_runtime(data)
    defer logic.destroy_transports(&fleet,context.allocator)
    logic.dispatch_transports(&fleet,&game,data.catalog.buildings)
    // Display-only fixture: activate a building with both continuous staffing and
    // configured needs, and add one individual assigned to it, so the capture
    // exercises coverage fractions and an individual block. No asset is modified and
    // normal game behavior is unchanged.
    fixture := -1
    for instance, i in game.buildings {
        for definition in data.catalog.buildings {
            if definition.id != instance.building_id { continue }
            if logic.building_required_slots(&game,i) > 0 && len(definition.needs) > 0 { fixture = i }
            break
        }
        if fixture >= 0 { break }
    }
    fixture_roles: [1]logic.Subject_Role
    if fixture >= 0 {
        game.active[fixture] = true
        game.level[fixture] = 1
        building := game.buildings[fixture]
        fixture_roles[0] = .worker
        for definition in data.catalog.buildings {
            if definition.id != building.building_id { continue }
            for entry in definition.subject_roles {
                if entry.staffing_mode == .continuous && entry.quantity > 0 { fixture_roles[0] = entry.role_id; break }
            }
            break
        }
        for subject_type in data.catalog.subjects {
            if subject_type.id != "human" { continue }
            person: logic.Runtime_Subject
            fleet.next_subject_id += 1
            person.id = c.Subject_ID(fleet.next_subject_id)
            person.subject_id = subject_type.id
            person.residence = building.id
            person.destination = building.id
            person.position = building.position
            person.target = building.position
            person.activity = .Inside
            person.phase = .Working
            person.health = 0.62
            person.work_hours = 3
            person.roles = fixture_roles[:]
            person.assignment = c.Shift_Assignment{building_id=building.id,role_id=fixture_roles[0],slot_index=0}
            count := min(len(subject_type.needs),c.NEED_SLOT_LIMIT)
            person.need_count = count
            for need, n in subject_type.needs[:count] {
                person.needs[n] = {resource_id=need.resource_id,fulfillment=0.6,shortage_hours=1}
            }
            append(&fleet.subjects,person)
            break
        }
        logic.derive_staffing(&game,&fleet)
    }
    // Exercise transport layout even when the shipped level has no active request.
    // A pending ordinary request guarantees the rocket approval button is captured.
    if len(data.catalog.ships) > 0 && len(data.catalog.subjects) > 0 && fleet.count < logic.TRANSPORT_LIMIT {
        pending := false
        for mission in fleet.missions[:fleet.count] { if mission.phase == .Awaiting_Approval { pending = true } }
        if !pending {
            fleet.next_mission_id += 1
            fleet.missions[fleet.count] = {id=fleet.next_mission_id,phase=.Awaiting_Approval,ship_id=data.catalog.ships[0].id,
                subject_id=data.catalog.subjects[0].id,destination=data.level.buildings[0].id,units=3,requested=3,
                distance=12.5,max_speed=f64(data.catalog.ships[0].max_speed)}
            fleet.count += 1
        }
    }
    for size, pass in ([?][2]f32{{1280,900},{640,360},{640,360},{1280,900},{1280,900}}) {
        width,height := size[0],size[1]
        scene: ui.Scene_State
        hud := ui.hud_view(width,height)
        toggle_bounds := ui.modal_toggle_bounds(width,height)
        for &toggle, i in hud.toggles {
            toggle.bounds = toggle_bounds[i]
            toggle.label = data.text.entries[i == 0 ? "modal_buildings_toggle" : "modal_subjects_toggle"]
        }
        hud.clock = app.clock_text(data.text.hud_clock_format,{elapsed_hours=123,speed=4})
        raw_station := app.station_lines(data.catalog,data.level.space_station,data.text.entries,context.temp_allocator)
        station_width := ui.station_bounds(width,height,1).width
        station_rows := render.wrap_info_lines(raw_station,station_width)
        hud.station_bounds = ui.station_bounds(width,height,len(station_rows))
        hint := render.wrap_info_lines([]string{data.text.entries["info_scroll_hint"]},station_width)
        if len(station_rows) <= ui.info_row_slots(hud.station_bounds) { hint = nil }
        hud.station_rows = ui.info_visible_rows(&scene.station_scroll,{},hud.station_bounds,station_rows,hint)
        hud.transport_bounds = ui.transport_bounds(width,height,app.transport_box_count(&fleet))
        cards := app.transport_cards(&fleet,data.catalog,data.text.entries,hud.transport_bounds,0,true)
        for &card in cards { card.rows = render.wrap_info_lines(card.lines,hud.transport_bounds.width) }
        if pass == 2 { scene.transport_pixel_scroll = 3*c.INFO_ROW_HEIGHT }
        hud.transports = ui.layout_transport_cards(&scene,{},hud.transport_bounds,cards)
        for instance, i in game.buildings {
            for definition in data.catalog.buildings {
                if definition.id != instance.building_id || len(definition.needs) == 0 { continue }
                if fixture >= 0 && i != fixture { continue } // Prefer the fixture building for the capture.
                scene.inspected_id = instance.id
                scene.info_anchor = pass == 0 ? c.Vector2{400,64} : c.Vector2{16,16}
                hud.info_bounds = ui.inspector_bounds(&scene,width,height)
                coverage: [3]c.Staffing_Coverage
                for role in logic.Subject_Role { coverage[int(role)] = logic.staffing_coverage(&game,i,role) }
                stock := logic.stock_snapshot(&game,i)
                rates := make([]c.Production_Rate,len(stock),context.temp_allocator)
                rate_count := logic.production_rates(&game,i,rates)
                lines := app.building_info_lines(logic.snapshot(&game,i),definition,data.text,instance,data.catalog,fleet.subjects[:],coverage[:],stock,logic.production_status(&game,i),rates[:rate_count])
                rows := render.wrap_info_lines(lines[:len(lines)-1],hud.info_bounds.width)
                footer := render.wrap_info_lines([]string{data.text.entries["building_info_scroll"]},hud.info_bounds.width)
                if pass == 1 { scene.info_scroll = 10 } // Show later body rows at minimum size.
                hud.info_rows = ui.inspector_visible_lines(&scene,{},hud.info_bounds,rows,footer)
                hud.info_title_color = definition.color
                break
            }
            if scene.inspected_id != "" { break }
        }
        notice_state: ui.Scene_State
        // Show a real building-specific notice so the capture proves {name}/{id} composition.
        notice_text := data.text.entries["notice_medical_evacuation"]
        if len(data.level.buildings) > 0 {
            if specific, found := data.building_notices.messages[{app.BUILDING_NOTICE_KEYS[0],data.level.buildings[0].id}]; found { notice_text = specific }
        }
        ui.show_notice(&notice_state,notice_text)
        if pass == 2 { hud.info_rows = nil; hud.info_bounds = {} }
        // Fourth and fifth captures: the overview grids opened by each toggle.
        if pass >= 3 {
            kind := pass == 3 ? c.Modal_Kind.Buildings : c.Modal_Kind.Subjects
            scene.modal = kind
            scene.inspected_id = ""
            hud.info_rows = nil
            hud.info_bounds = {}
            hud.toggles[kind == .Buildings ? 0 : 1].active = true
            hud.modal = {kind=kind,bounds=ui.modal_bounds(width,height),hint=data.text.entries["modal_scroll_hint"]}
            grid: []c.Modal_Row
            if kind == .Buildings {
                hud.modal.title = data.text.entries["modal_buildings_title"]
                hud.modal.columns = app.building_grid_columns(data.text)
                grid = app.building_grid_rows(&game,data.catalog,data.text)
            } else {
                hud.modal.title = data.text.entries["modal_subjects_title"]
                hud.modal.columns = app.subject_grid_columns(data.text)
                grid = app.subject_grid_rows(&game,&fleet,data.catalog,data.text)
            }
            hud.modal.rows = ui.modal_visible_rows(&scene.modal_scroll,{},hud.modal.bounds,grid)
        }
        path: string
        switch pass {
        case 0: path = "build/info-boxes-wide.png"
        case 1: path = "build/info-boxes-small.png"
        case 2: path = "build/info-boxes-small-panels.png"
        case 3: path = "build/overview-buildings.png"
        case 4: path = "build/overview-subjects.png"
        }
        assert(render.capture_info_smoke(hud,ui.notice_view(&notice_state,width,height),i32(width),i32(height),path))
        free_all(context.temp_allocator)
    }
    // World capture: configured sprites/fills with no text drawn over them.
    world: [4]render.Building_Draw
    world_count := min(len(world),len(data.catalog.buildings))
    for i in 0..<world_count {
        definition := data.catalog.buildings[i]
        world[i] = {bounds={64+f32(i)*150,260,120,120},color=definition.color,sprite=definition.sprite,illuminated=i != 1,level_bar={},level=0}
    }
    assert(render.capture_world_smoke(world[:world_count],1280,900,"build/buildings-no-text.png"))
    fmt.println("Info-box visual smoke captures completed.")
}
