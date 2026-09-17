package main

import "core:testing"
import "../logic"
import "../config"
import c "../contracts"

@(test)
landing_crosses_current_viewport_and_takeoff_reverses :: proc(t: ^testing.T) {
    for viewport in ([?]c.Vector2{{640,360},{1280,720},{1920,1200}}) {
        for zoom in ([?]f32{MIN_ZOOM,1,MAX_ZOOM}) {
            camera := Camera{center={2,-1},zoom=zoom}
            // Nonzero camera/position exercises the actual world-to-screen adapter.
            pad := building_screen_bounds(camera,{2.5,0},{128,64},viewport.x,viewport.y)
            start := landing_ship_bounds(pad,0)
            end := landing_ship_bounds(pad,1)
            middle := landing_ship_bounds(pad,0.5)
            testing.expect(t,start.y+start.height == 0)
            testing.expect(t,start.x+16 == pad.x+pad.width/2)
            testing.expect(t,end.y+16 == pad.y+pad.height/2)
            testing.expect(t,middle.y == (start.y+end.y)/2)
            last := start.y
            for i in 1..=20 {
                rect := landing_ship_bounds(pad,f64(i)/20)
                testing.expect(t,rect.y >= last && rect.width == 32 && rect.height == 32)
                last = rect.y
            }
            last = end.y
            for i in 1..=20 {
                rect := landing_ship_bounds(pad,1-f64(i)/20)
                testing.expect(t,rect.y <= last)
                last = rect.y
            }
            testing.expect(t,landing_ship_bounds(pad,-1) == start && landing_ship_bounds(pad,2) == end)
        }
    }
}

@(test)
landing_phase_projection_preserves_holding_and_cancel_continuity :: proc(t: ^testing.T) {
    fleet := logic.Transport_State{count=3}
    fleet.missions[0] = {phase=.Landing,platform_id="LP",landing_progress=0.4,loaded=5,landing_ticket=1}
    fleet.missions[1] = {phase=.Waiting_Landing,holding_platform_id="LP",loaded=5,landing_ticket=2}
    fleet.missions[2] = {phase=.Waiting_Landing,holding_platform_id="LP",loaded=5,landing_ticket=3}
    targets := [?]c.Building_Target{{id="LP",bounds={400,500,80,40}}}
    before := landing_draws(&fleet,config.Catalog{},targets[:])
    testing.expect(t,len(before) == 3)
    if len(before) != 3 { return }
    testing.expect(t,before[1].ship_bounds.y == 404 && before[2].ship_bounds.y == 404)
    testing.expect(t,before[1].ship_bounds.x != before[2].ship_bounds.x)
    fleet.missions[0].phase = .Taking_Off
    cancelled := landing_draws(&fleet,config.Catalog{},targets[:])
    testing.expect(t,cancelled[0].ship_bounds == before[0].ship_bounds)
    // Reprojection after resize/pan/zoom uses new pad bounds, never a cached Y.
    targets[0].bounds = building_screen_bounds({center={1,1},zoom=2},{2,3},{128,64},900,600)
    resized := landing_draws(&fleet,config.Catalog{},targets[:],{},900,600)
    testing.expect(t,resized[0].ship_bounds == landing_ship_bounds(targets[0].bounds,0.4))
    testing.expect(t,fleet.missions[0].landing_progress == 0.4 && fleet.missions[0].loaded == 5)
    testing.expect(t,fleet.missions[1].phase == .Waiting_Landing && fleet.missions[1].landing_ticket == 2)
    fleet.missions[0].landing_progress = 0
    departed := landing_draws(&fleet,config.Catalog{},targets[:],{},900,600)
    testing.expect(t,departed[0].ship_bounds.y+32 == 0)
    fleet.missions[0].phase = .Returning
    testing.expect(t,len(landing_draws(&fleet,config.Catalog{},targets[:])) == 2)
}
