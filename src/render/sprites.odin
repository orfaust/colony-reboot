package render

import c "../contracts"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// Graphics-thread-only cache. Keys borrow the application's startup arena; GPU
// handles never leave render. Replacement is transactional on the graphics thread:
// failed staging unloads only new textures; success releases the old cache.
@(private)
sprite_textures: map[string]rl.Texture2D

init_sprites :: proc(paths: []string) -> bool {
    staged := make(map[string]rl.Texture2D)
    committed := false
    defer {
        if !committed {
            for _, texture in staged { rl.UnloadTexture(texture) }
            delete(staged)
        }
    }
    for path in paths {
        if path == "" { continue }
        if _, loaded := staged[path]; loaded { continue }
        filename := strings.clone_to_cstring(path)
        texture := rl.LoadTexture(filename)
        delete(filename)
        if !rl.IsTextureValid(texture) || texture.width <= 0 || texture.height <= 0 {
            if texture.id != 0 { rl.UnloadTexture(texture) }
            fmt.eprintf("Cannot load sprite %q. Run python tools/build.py; deploy assets with the executable and run from the repository root.\n", path)
            return false
        }
        // Original sprites are pixel art. No mipmaps; nearest-neighbor magnification.
        rl.SetTextureFilter(texture, .POINT)
        staged[path] = texture
    }
    destroy_sprites()
    sprite_textures = staged
    committed = true
    return true
}

@(private)
destroy_sprites :: proc() {
    for _, texture in sprite_textures { rl.UnloadTexture(texture) }
    delete(sprite_textures)
    sprite_textures = nil
}

// Full static PNG, top-left pivot, stretched to existing presentation bounds.
// Straight-alpha white tint preserves image colors. Only empty paths use fallback.
// A nonempty uncached path is a programmer error, never a per-frame disk load.
draw_sprite_or_color :: proc(bounds: c.Rect, sprite: string, color: c.RGB) {
    if bounds.width <= 0 || bounds.height <= 0 { return }
    if sprite == "" {
        rl.DrawRectangleRec({bounds.x,bounds.y,bounds.width,bounds.height},{color.r,color.g,color.b,255})
        return
    }
    texture, found := sprite_textures[sprite]
    assert(found, "sprite must be preloaded before drawing")
    destination := sprite_pixel_bounds(bounds)
    rl.DrawTexturePro(texture, {0,0,f32(texture.width),f32(texture.height)},
        {destination.x,destination.y,destination.width,destination.height}, {0,0}, 0, rl.WHITE)
}
