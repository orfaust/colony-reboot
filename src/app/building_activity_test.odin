package main

import "core:testing"
import c "../contracts"
import "../render"

@(test)
shutdown_dims_immediately_without_changing_progress :: proc(t: ^testing.T) {
    draw: render.Building_Draw
    apply_building_activity(&draw,c.Building_Snapshot{active=false,energized=true,level=0.5})
    testing.expect(t,!draw.illuminated && draw.level == 0.5)
    // Reversing shutdown restores brightness without resetting the level.
    apply_building_activity(&draw,c.Building_Snapshot{active=true,energized=true,level=0.5})
    testing.expect(t,draw.illuminated && draw.level == 0.5)
    apply_building_activity(&draw,c.Building_Snapshot{active=false,energized=false,level=0})
    testing.expect(t,!draw.illuminated && draw.level == 0)
    apply_building_activity(&draw,c.Building_Snapshot{active=true,energized=true,level=0})
    testing.expect(t,draw.illuminated && draw.level == 0)
    apply_building_activity(&draw,c.Building_Snapshot{active=false,energized=true,level=1})
    testing.expect(t,!draw.illuminated && draw.level == 1)
    apply_building_activity(&draw,c.Building_Snapshot{active=true,energized=false,level=0})
    testing.expect(t,!draw.illuminated)
}
