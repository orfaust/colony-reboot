package render

import rl "vendor:raylib"

// Opt-in GPU integration checks, compiled only for tools/sprite_smoke. No test
// runner/CRT dependencies are added to the normal renderer or headless tests.
when #config(SPRITE_GPU_TEST, false) {
    sprite_gpu_smoke :: proc() {
        rl.SetConfigFlags({.WINDOW_HIDDEN})
        assert(open("Sprite renderer integration test"), "graphics context unavailable")
        defer close()
        paths := [?]string{"assets/sprites/buildings/control_unit.png", "", "assets/sprites/buildings/control_unit.png"}
        assert(init_sprites(paths[:]))
        assert(len(sprite_textures) == 1, "duplicate textures must be cached")
        target := rl.LoadRenderTexture(32,32)
        defer rl.UnloadRenderTexture(target)
        rl.BeginTextureMode(target)
        rl.ClearBackground({10,20,30,255})
        draw_sprite_or_color({0,0,32,32}, paths[0], {255,0,0})
        rl.EndTextureMode()
        image := rl.LoadImageFromTexture(target.texture)
        corner := rl.GetImageColor(image,0,0)
        center := rl.GetImageColor(image,16,16)
        assert(corner.r == 10 && corner.g == 20 && corner.b == 30, "transparent pixels must preserve background")
        assert(center.r != 255 || center.g != 0 || center.b != 0, "sprite must replace color")
        assert(center.r != 10 || center.g != 20 || center.b != 30, "sprite must be visible")
        // Render-texture readback is vertically inverted; normalize the visual artifact.
        rl.ImageFlipVertical(&image)
        // Reproducible readback image for visual inspection; ignored build output.
        assert(rl.ExportImage(image, "build/sprite-smoke.png"))
        rl.UnloadImage(image)
        rl.BeginTextureMode(target)
        draw_sprite_or_color({0,0,32,32}, "", {12,34,56})
        rl.EndTextureMode()
        image = rl.LoadImageFromTexture(target.texture)
        color := rl.GetImageColor(image,16,16)
        assert(color.r == 12 && color.g == 34 && color.b == 56, "empty sprite must preserve color fallback")
        rl.UnloadImage(image)
        bad := [?]string{paths[0], "assets/sprites/deliberately-missing-test.png"}
        assert(!init_sprites(bad[:]), "missing asset must fail startup")
        assert(len(sprite_textures) == 1, "failed staging must preserve the playable cache")
        assert(rl.IsTextureValid(sprite_textures[paths[0]]))
        assert(init_sprites(paths[:]))
        destroy_sprites()
        assert(len(sprite_textures) == 0)
    }
}
