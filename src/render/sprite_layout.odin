package render

import c "../contracts"
import "core:math"

// Pixel alignment is presentation-only; authoritative positions and hit bounds
// remain unchanged. Empty bounds are culled before this procedure is called.
sprite_pixel_bounds :: proc(bounds: c.Rect) -> c.Rect {
    return {math.round(bounds.x), math.round(bounds.y),
        max(f32(1), math.round(bounds.width)), max(f32(1), math.round(bounds.height))}
}
