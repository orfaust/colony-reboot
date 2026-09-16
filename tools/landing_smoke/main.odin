package viewport_smoke
// Real-backend contact sheet: arrival, touchdown, takeoff and independent holding.
// Run from repository root; output is ignored under build/.
import app "../../src/app"
import "../../src/render"
import "../../src/config"
import "../../src/logic"
import c "../../src/contracts"
import rl "vendor:raylib"
main :: proc() {
    rl.SetConfigFlags({.WINDOW_HIDDEN})
    assert(render.open("Viewport travel developer smoke"))
    defer render.close()
    target := rl.LoadRenderTexture(1920,240)
    defer rl.UnloadRenderTexture(target)
    phases := [?]logic.Transport_Phase{.Landing,.Landing,.Unloading,.Taking_Off,.Taking_Off,.Waiting_Landing}
    progress := [?]f64{0.15,0.5,1,0.5,0.15,0}
    ships := [?]logic.Ship{{id="test",color={240,170,40}}}
    fleet := logic.Transport_State{count=1}
    pad := app.building_screen_bounds(app.DEFAULT_CAMERA,{0,1},{1,0.5},320,240)
    targets := [?]c.Building_Target{{id="LP",bounds=pad}}
    rl.BeginTextureMode(target)
    rl.ClearBackground({20,25,35,255})
    for phase, i in phases {
        fleet.missions[0] = {ship_id="test",phase=phase,platform_id="LP",holding_platform_id="LP",landing_progress=progress[i]}
        draws := app.landing_draws(&fleet,config.Catalog{ships=ships[:]},targets[:],app.DEFAULT_CAMERA,320,240)
        for &draw in draws { draw.ship_bounds.x += f32(i)*320 }
        rl.DrawRectangleRec({pad.x+f32(i)*320,pad.y,pad.width,pad.height},{70,130,160,255})
        render.draw_landings(draws)
        rl.DrawRectangleLines(i32(i)*320,0,320,240,{100,100,100,255})
    }
    rl.EndTextureMode()
    image := rl.LoadImageFromTexture(target.texture)
    defer rl.UnloadImage(image)
    rl.ImageFlipVertical(&image)
    assert(rl.ExportImage(image,"build/viewport-travel-smoke.png"))
}
