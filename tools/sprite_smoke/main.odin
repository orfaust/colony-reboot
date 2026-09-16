package main

import "../../src/render"
import "core:fmt"

main :: proc() {
    render.sprite_gpu_smoke()
    fmt.println("Sprite GPU smoke checks passed.")
}
