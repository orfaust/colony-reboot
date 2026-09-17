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
        // Reserve the approval button's strip so cargo icons never draw beneath it.
        icon_edge := card.approve_id != 0 ? f32(92) : f32(52)
        color = card.subject_color
        for i in 0..<min(card.passengers,int(max(f32(0),r.width-icon_edge)/13)) {
            draw_sprite_or_color({r.x+40+f32(i)*13,r.y+r.height-28,9,16},card.subject_sprite,color)
        }
        draw_approval_button(card)
        rl.EndScissorMode()
        draw_info_rows({r.x,r.y,r.width,r.height-40},card.rows,card.ship_color,clip)
    }
}

// Icon-only affordance meaning "approve this launch"; the card status line carries
// the localized wording, so no untranslated literal is drawn here.
@(private)
draw_approval_button :: proc(card: c.Transport_Card) {
    if card.approve_id == 0 || card.approve_bounds.width <= 0 { return }
    b := card.approve_bounds
    rl.DrawRectangleRec({b.x,b.y,b.width,b.height},{48,72,112,255})
    rl.DrawRectangleLinesEx({b.x,b.y,b.width,b.height},1,rl.WHITE)
    draw_rocket_icon({b.x+6,b.y+5,b.width-12,b.height-10},rl.WHITE,{48,72,112,255})
}

// Procedural rocket so the approval button needs no extra font glyph or image asset.
@(private)
draw_rocket_icon :: proc(bounds: c.Rect, ink, window: rl.Color) {
    if bounds.width <= 0 || bounds.height <= 0 { return }
    width := min(bounds.width,bounds.height)
    height := bounds.height
    cx := bounds.x+bounds.width/2
    half := width*0.20
    shoulder_y := bounds.y+height*0.28
    tail_y := bounds.y+height*0.66
    rl.DrawTriangle({cx,bounds.y},{cx-half,shoulder_y},{cx+half,shoulder_y},ink)
    rl.DrawRectangleRec({cx-half,shoulder_y,half*2,tail_y-shoulder_y},ink)
    rl.DrawTriangle({cx-half,tail_y-height*0.16},{cx-width*0.48,tail_y},{cx-half,tail_y},ink)
    rl.DrawTriangle({cx+half,tail_y-height*0.16},{cx+width*0.48,tail_y},{cx+half,tail_y},ink)
    rl.DrawCircleV({cx,shoulder_y+height*0.11},width*0.11,window)
    rl.DrawTriangle({cx-half*0.6,tail_y},{cx+half*0.6,tail_y},{cx,bounds.y+height*0.94},{255,170,60,255})
}
