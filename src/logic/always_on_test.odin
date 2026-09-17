package logic

import "core:testing"

@(test)
always_on_prevents_shutdown_for_every_instance_and_survives_reset :: proc(t: ^testing.T) {
    // always_on requires power_need_kw == 0 at startup because such a building can
    // never be stopped; the fixture keeps a companion generator so the network has
    // real output and an ordinary consumer for the power comparison.
    definitions := [?]Building_Type{
        {id="control_unit",power_output_kw=10},
        {id="landing_platform",always_on=true,cooldown_time=1,min_operative_health=0.5},
        {id="ordinary",power_need_kw=1},
    }
    initial := [?]Building_Instance{
        {id="CU",building_id="control_unit",health=1},
        {id="LP1",building_id="landing_platform",enable_at_start=true,health=1},
        {id="LP2",building_id="landing_platform",enable_at_start=true,health=0.1},
        {id="O",building_id="ordinary",enable_at_start=true,health=1},
    }
    state := new_session(initial[:],definitions[:],context.allocator)
    defer destroy(&state,context.allocator)
    for _ in 0..<2 {
        for i in 1..<3 {
            before := snapshot(&state,i)
            testing.expect(t,toggle(&state,{id=initial[i].id}) == .Always_On_Locked)
            step(&state)
            after := snapshot(&state,i)
            testing.expect(t,after.active && after.energized && after.level == before.level)
            testing.expect(t,after.power_need_kw == before.power_need_kw)
        }
        testing.expect(t,balance(&state).consumed_kw == 1)
        testing.expect(t,toggle(&state,{id="O"}) == .Applied)
        testing.expect(t,toggle(&state,{id="CU"}) == .Control_Unit_Locked)
        reset(&state,initial[:])
    }
    // A fresh session/reload must use the new catalog, not the previous lock flags.
    definitions[1].always_on = false
    fresh := new_session(initial[:],definitions[:],context.allocator)
    defer destroy(&fresh,context.allocator)
    testing.expect(t,toggle(&fresh,{id="LP1"}) == .Applied)
    testing.expect(t,toggle(&state,{id="LP1"}) == .Always_On_Locked)
}
