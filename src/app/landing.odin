package main

import "../config"
import "../logic"
import "../render"
import c "../contracts"

// Screen-pixel placeholders anchored to the platform's current camera projection.
// Screen Y is down; the current viewport starts at Y=0. At progress zero the
// 32px ship is just outside its top edge; at one it is centered on the projected
// pad. Takeoff (including interrupted descent) traverses this same path backwards.
// Smoothstep gives zero endpoint velocity. Camera changes never affect simulation.
landing_ship_bounds :: proc(platform: c.Rect, progress: f64) -> c.Rect {
    p := f32(clamp(progress,0,1))
    p = p*p*(3-2*p)
    top := f32(-32)
    return {platform.x+platform.width/2-16, top+(platform.y+platform.height/2-16-top)*p,32,32}
}
landing_draws :: proc(fleet: ^logic.Transport_State, catalog: config.Catalog, targets: []c.Building_Target, camera: Camera = {}, width: f32 = 1280, height: f32 = 720) -> []render.Landing_Draw {
    draws := make([dynamic]render.Landing_Draw,context.temp_allocator)
    waiting_slot := 0
    for mission in fleet.missions[:fleet.count] {
        waiting := mission.phase == .Waiting_Landing
        anchor := waiting ? mission.holding_platform_id : mission.platform_id
        if anchor == "" { continue }
        platform: c.Rect
        found := false
        for target in targets { if target.id == anchor { platform = target.bounds; found = true; break } }
        if !found { continue }
        draw := render.Landing_Draw{}
        for ship in catalog.ships { if ship.id == mission.ship_id { draw.ship_color = ship.color; break } }
        for subject in catalog.subjects { if subject.id == mission.subject_id { draw.subject_color = subject.color; break } }
        draw.ship_visible = waiting || mission.phase == .Landing || mission.phase == .Unloading || mission.phase == .Taking_Off
        draw.ship_bounds = landing_ship_bounds(platform,mission.landing_progress)
        if waiting {
            draw.ship_bounds = {platform.x+platform.width/2-16,max(f32(0),platform.y-96),32,32}
            // Holding altitude is independent of the viewport-edge transit path.
            // Separate screen-space holding slots; presentation never grants clearance.
            columns := max(1,int(width/40))
            column := int(max(f32(0),draw.ship_bounds.x)/40)
            draw.ship_bounds.x = f32((column+waiting_slot)%columns)*40
            draw.ship_bounds.y = clamp(draw.ship_bounds.y-f32(waiting_slot/columns)*40,0,max(f32(0),height-32))
            waiting_slot += 1
        }
        if draw.ship_visible { append(&draws,draw) }
    }
    // Draw actual independent subject positions, never reconstruct a cohort from
    // mission totals. Group only draw submission by type, not behavior or identity.
    for definition in catalog.subjects {
        passengers := make([dynamic]c.Rect,context.temp_allocator)
        sprites := make([dynamic]string,context.temp_allocator)
        for subject in fleet.subjects {
            if subject.subject_id != definition.id || subject.activity != .Moving { continue }
            point := building_screen_bounds(camera,subject.position,{},width,height)
            rect := c.Rect{point.x-4.5,point.y-16,9,16}
            if rect.x+9 < 0 || rect.y+16 < 0 || rect.x > width || rect.y > height { continue }
            append(&passengers,rect)
            append(&sprites,subject_sprite(subject.roles, definition.roles, definition.sprite))
        }
        if len(passengers) > 0 { append(&draws,render.Landing_Draw{subject_color=definition.color,passengers=passengers[:],passenger_sprites=sprites[:]}) }
    }
    return draws[:]
}
