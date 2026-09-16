package main

import "core:testing"
import "../logic"
import "../config"
import c "../contracts"

@(test)
waiting_ships_are_visible_separate_and_read_only :: proc(t: ^testing.T) {
    fleet := logic.Transport_State{count=3}
    fleet.missions[0] = {phase=.Unloading,platform_id="LP",landing_progress=1}
    fleet.missions[1] = {phase=.Waiting_Landing,holding_platform_id="LP",landing_ticket=1}
    fleet.missions[2] = {phase=.Waiting_Landing,holding_platform_id="LP",landing_ticket=2}
    targets := [?]c.Building_Target{{id="LP",bounds={400,300,80,40}}}
    draws := landing_draws(&fleet,config.Catalog{},targets[:])
    testing.expect(t,len(draws) == 3)
    if len(draws) != 3 { return }
    for draw in draws { testing.expect(t,draw.ship_visible && draw.ship_bounds.width == 32 && draw.ship_bounds.height == 32) }
    testing.expect(t,draws[1].ship_bounds.y >= 0 && draws[1].ship_bounds.y+32 < draws[0].ship_bounds.y)
    testing.expect(t,draws[1].ship_bounds.x != draws[2].ship_bounds.x)
    testing.expect(t,fleet.missions[1].phase == .Waiting_Landing && fleet.missions[1].platform_id == "")
    // Resizing/projection cannot clear the platform or advance waiting cargo.
    resized := landing_draws(&fleet,config.Catalog{},targets[:],{},320,240)
    testing.expect(t,len(resized) == 3 && resized[1].ship_bounds.x+32 <= 320)
    testing.expect(t,fleet.missions[2].phase == .Waiting_Landing && fleet.missions[2].delivered == 0)
}
