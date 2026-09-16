package main

import c "../contracts"
import "../render"

// Dim as soon as shutdown is requested, even while cooldown still consumes power.
// Electrical eligibility and transition progress remain authoritative in logic.
apply_building_activity :: proc(draw: ^render.Building_Draw, building: c.Building_Snapshot) {
    draw.illuminated = building.active && building.energized
    draw.level = f32(building.level)
}
