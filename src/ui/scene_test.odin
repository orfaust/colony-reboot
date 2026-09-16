package ui

import "core:testing"
import c "../contracts"

@(test)
scene_click_consumption :: proc(t: ^testing.T) {
    targets := [?]c.Building_Target{
        {id="lower",bounds={100,100,96,96}}, {id="upper",bounds={120,120,96,96}},
    }
    state: Scene_State
    notice := notice_view(&state,640,360)
    hud := hud_view(640,360)
    input := c.Input{focused=true,click=true,mouse_x=130,mouse_y=130}
    command, ok := scene_command(input, targets[:], notice, hud)
    testing.expect(t, ok && command.id == "upper")
    input.focused = false
    _, ok = scene_command(input, targets[:], notice, hud)
    testing.expect(t, !ok)
    input.focused = true
    input.back = true
    _, ok = scene_command(input, targets[:], notice, hud)
    testing.expect(t, !ok)
    input.back = false
    input.mouse_x, input.mouse_y = notice.bounds.x+1, notice.bounds.y+1
    targets[1].bounds = notice.bounds
    _, ok = scene_command(input, targets[:], notice, hud)
    testing.expect(t, !ok)
    input.mouse_x, input.mouse_y = 600, 300
    _, ok = scene_command(input, targets[:], notice, hud)
    testing.expect(t, !ok)
    input.click = false
    input.mouse_x, input.mouse_y = 110,110
    _, ok = scene_command(input, targets[:], notice, hud)
    testing.expect(t, !ok)
    // The clock panel consumes clicks on buildings drawn beneath it.
    input.click = true
    input.mouse_x, input.mouse_y = hud.bounds.x+1, hud.bounds.y+1
    targets[1].bounds = hud.bounds
    _, ok = scene_command(input, targets[:], notice, hud)
    testing.expect(t, !ok)
}

@(test)
hud_stays_top_left_on_resize :: proc(t: ^testing.T) {
    sizes := [?][2]f32{{640,360},{1280,720},{1920,1080}}
    for size in sizes {
        hud := hud_view(size[0],size[1])
        testing.expect(t, hud.bounds == c.Rect{16,16,HUD_WIDTH,HUD_HEIGHT})
    }
    tiny := hud_view(20,10)
    testing.expect(t, tiny.bounds.width >= 0 && tiny.bounds.height >= 0)
}

@(test)
speed_commands :: proc(t: ^testing.T) {
    input := c.Input{focused=true,speed_up=true}
    change, ok := speed_command(input)
    testing.expect(t, ok && change == .Faster)
    input = {focused=true,slow_down=true}
    change, ok = speed_command(input)
    testing.expect(t, ok && change == .Slower)
    rejected := [?]c.Input{
        {focused=true}, {focused=true,speed_up=true,slow_down=true},
        {speed_up=true}, {focused=true,back=true,slow_down=true},
    }
    for input in rejected {
        _, ok = speed_command(input)
        testing.expect(t, !ok)
    }
}

@(test)
notices_expire_independently :: proc(t: ^testing.T) {
    state: Scene_State
    show_notice(&state,"first")
    advance_notice(&state,9.5)
    show_notice(&state,"second")
    testing.expect(t, state.notice_count == 2)
    testing.expect(t, state.notices[0].remaining == 0.5 && state.notices[1].remaining == 10)
    advance_notice(&state,-1)
    testing.expect(t, state.notices[1].remaining == 10)
    before := notice_view(&state,640,360)
    advance_notice(&state,0.5)
    testing.expect(t, state.notice_count == 1 && state.notices[0].text == "second")
    testing.expect(t, state.notices[0].remaining == 9.5)
    testing.expect(t, before.count == 2 && before.lines[0].text == "first")
    advance_notice(&state,9.5)
    testing.expect(t, state.notice_count == 0 && state.notices[0].text == "")
    show_notice(&state,"third")
    advance_notice(&state,100000)
    testing.expect(t, state.notice_count == 0)
}

@(test)
notice_log_scrolls_and_bounds_storage :: proc(t: ^testing.T) {
    state: Scene_State
    show_notice(&state,"")
    testing.expect(t, state.notice_count == 0)
    messages := [?]string{"first","second","third","fourth","fifth"}
    for message in messages { show_notice(&state,message) }
    view := notice_view(&state,640,360)
    testing.expect(t, view.count == 4 && view.lines[0].text == "second" && view.lines[3].text == "fifth")
    for i in 1..<view.count { testing.expect(t, view.lines[i].bounds.y > view.lines[i-1].bounds.y) }
    for state.notice_count < NOTICE_CAPACITY { show_notice(&state,"queued") }
    show_notice(&state,"latest")
    testing.expect(t, state.notice_count == NOTICE_CAPACITY && state.notices[0].text == "second")
    view = notice_view(&state,640,360)
    testing.expect(t, view.lines[view.count-1].text == "latest")
    advance_notice(&state,10)
    testing.expect(t, state.notice_count == 0)
}

@(test)
notice_panel_stays_at_bottom_on_resize :: proc(t: ^testing.T) {
    state: Scene_State
    show_notice(&state,"first")
    show_notice(&state,"second")
    sizes := [?][2]f32{{640,360},{1280,720},{1920,1080}}
    for size in sizes {
        view := notice_view(&state,size[0],size[1])
        testing.expect(t, view.bounds.y+view.bounds.height == size[1]-16)
        testing.expect(t, view.bounds.x == 16 && view.bounds.width == size[0]-32)
        for line in view.lines[:view.count] {
            testing.expect(t, line.bounds.y >= view.bounds.y)
            testing.expect(t, line.bounds.y+line.bounds.height <= view.bounds.y+view.bounds.height)
            testing.expect(t, line.bounds.x >= view.bounds.x)
            testing.expect(t, line.bounds.x+line.bounds.width <= view.bounds.x+view.bounds.width)
        }
    }
}
