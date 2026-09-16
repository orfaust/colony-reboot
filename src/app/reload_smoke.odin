package main

import "core:fmt"
import "../render"

// Explicit opt-in integration check for the documented odin run development mode.
// Opens and closes the real backend; no watcher or production command is installed.
when DEVELOPMENT_RELOAD {
    reload_smoke :: proc() -> bool {
        old := load_reload_data(INITIAL_LEVEL_PATH)
        if old == nil { return false }
        defer destroy_reload_data(old)
        if !render.open(old.text.window_title) { return false }
        defer render.close()
        if !render.init_sprites(sprite_paths(old.catalog)) { return false }
        next := prepare_reload(INITIAL_LEVEL_PATH,render.init_sprites)
        if next == nil { return false }
        // Cache borrows next's keys until close; release it before next's arena.
        defer destroy_reload_data(next)
        defer render.init_sprites(nil)
        render.set_title(next.text.window_title)
        render.finish_reload_frame()
        fmt.println("Development reload smoke: JSON validation, fresh arena, texture replacement and frame barrier passed.")
        return true
    }
}
