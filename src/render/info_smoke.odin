package render

import c "../contracts"
import "core:strings"
import rl "vendor:raylib"

// Developer-only offscreen integration support; graphics APIs stay in render.
when #config(INFO_BOX_SMOKE, false) {
    open_info_smoke :: proc(title: string) -> bool {
        rl.SetConfigFlags({.WINDOW_HIDDEN})
        return open(title)
    }

    capture_info_smoke :: proc(hud: c.Hud_View, notice: c.Notice_View, width, height: i32, path: string) -> bool {
        return capture_smoke(hud,notice,nil,width,height,path)
    }

    // World capture: buildings with no text drawn over them.
    capture_world_smoke :: proc(buildings: []Building_Draw, width, height: i32, path: string) -> bool {
        return capture_smoke({},{},buildings,width,height,path)
    }

    capture_smoke :: proc(hud: c.Hud_View, notice: c.Notice_View, buildings: []Building_Draw, width, height: i32, path: string) -> bool {
        target := rl.LoadRenderTexture(width,height)
        if !rl.IsRenderTextureValid(target) { return false }
        defer rl.UnloadRenderTexture(target)
        rl.BeginTextureMode(target)
        rl.ClearBackground({12,14,20,255})
        draw_buildings(buildings)
        draw_scene_overlays(notice,hud)
        rl.EndTextureMode()
        image := rl.LoadImageFromTexture(target.texture)
        defer rl.UnloadImage(image)
        rl.ImageFlipVertical(&image)
        filename := strings.clone_to_cstring(path,context.temp_allocator)
        return rl.ExportImage(image,filename)
    }
}
