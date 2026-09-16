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
    // Exercise transport layout even when the shipped level has no active request.
    if fleet.count == 0 && len(data.catalog.ships) > 0 && len(data.catalog.subjects) > 0 {
        fleet.count = 1
        fleet.missions[0] = {phase=.Outbound,ship_id=data.catalog.ships[0].id,subject_id=data.catalog.subjects[0].id,
            destination=data.level.buildings[0].id,requested=3,loaded=3,units=3,distance=12.5,travelled=0.25,
            speed=0.00002,max_speed=f64(data.catalog.ships[0].max_speed),duration=3,phase_duration=3,phase_elapsed=1}
    }
    for size, pass in ([?][2]f32{{1280,900},{640,360},{640,360}}) {
        width,height := size[0],size[1]
        scene: ui.Scene_State
        hud := ui.hud_view(width,height)
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
                scene.inspected_id = instance.id
                scene.info_anchor = pass == 0 ? c.Vector2{400,64} : c.Vector2{16,16}
                hud.info_bounds = ui.inspector_bounds(&scene,width,height)
                lines := app.building_info_lines(logic.snapshot(&game,i),definition,data.text,instance,data.catalog,fleet.subjects[:])
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
        ui.show_notice(&notice_state,data.text.notice_insufficient_power)
        if pass == 2 { hud.info_rows = nil; hud.info_bounds = {} }
        path := pass == 0 ? "build/info-boxes-wide.png" : (pass == 1 ? "build/info-boxes-small.png" : "build/info-boxes-small-panels.png")
        assert(render.capture_info_smoke(hud,ui.notice_view(&notice_state,width,height),i32(width),i32(height),path))
        free_all(context.temp_allocator)
    }
    fmt.println("Info-box visual smoke captures completed.")
}
