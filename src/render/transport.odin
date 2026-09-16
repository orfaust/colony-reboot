package render

import c "../contracts"
import rl "vendor:raylib"

// Text has the full card width; icons occupy a separate bottom strip. UI supplies
// measured variable heights and scroll offsets. Clip partial cards to their panel.
draw_transports :: proc(cards: []c.Transport_Card, viewport: c.Rect) {
    for card in cards {
        r := card.bounds
        clip := intersect_info_bounds(r,viewport)
        if clip.width <= 0 || clip.height <= 0 { continue }
        rl.BeginScissorMode(i32(clip.x),i32(clip.y),i32(clip.width),i32(clip.height))
        rl.DrawRectangleRec({r.x,r.y,r.width,r.height},{24,24,24,255})
        rl.DrawRectangleLinesEx({r.x,r.y,r.width,r.height},1,rl.GRAY)
        color := card.ship_color
        rl.DrawRectangleRec({r.x+8,r.y+r.height-32,24,24},{color.r,color.g,color.b,255})
        color = card.subject_color
        for i in 0..<min(card.passengers,int(max(f32(0),r.width-52)/13)) {
            draw_sprite_or_color({r.x+40+f32(i)*13,r.y+r.height-28,9,16},card.subject_sprite,color)
        }
        rl.EndScissorMode()
        draw_info_rows({r.x,r.y,r.width,r.height-40},card.rows,card.ship_color,clip)
    }
}
