package render

import c "../contracts"
import rl "vendor:raylib"

// Frame-owned 2D presentation only. App projects the stable platform ID and
// simulation progress; renderer never selects a platform or delivers passengers.
Landing_Draw :: struct {
    ship_bounds: c.Rect,
    ship_visible: bool,
    ship_color, subject_color: c.RGB,
    passengers: []c.Rect,
    passenger_sprites: []string, // Optional parallel borrowed paths; nil keeps color placeholders.
}
draw_landings :: proc(landings: []Landing_Draw) {
    for landing in landings {
        if landing.ship_visible {
            r := landing.ship_bounds
            color := landing.ship_color
            rl.DrawRectangleRec({r.x,r.y,r.width,r.height},{color.r,color.g,color.b,255})
        }
        color := landing.subject_color
        for r, i in landing.passengers {
            sprite := ""
            if i < len(landing.passenger_sprites) { sprite = landing.passenger_sprites[i] }
            draw_sprite_or_color(r, sprite, color)
        }
    }
}
