package logic

import "core:testing"

@(test)
shutdown_retains_energy_until_zero_and_reactivation_does_not_double_charge :: proc(t: ^testing.T) {
    run_ticks := proc(state: ^State, ticks: int) { for _ in 0..<ticks { step(state) } }
    definitions := [?]Building_Type{{id="control_unit",power_output_kw=10},{id="load",power_need_kw=10,warmup_time=1,cooldown_time=1}}
    initial := [?]Building_Instance{{id="CU",building_id="control_unit",health=1},{id="L",building_id="load",health=1,enable_at_start=true}}
    state := new_session(initial[:],definitions[:],context.allocator)
    defer destroy(&state,context.allocator)
    testing.expect(t,toggle(&state,{id="L"}) == .Applied)
    view := snapshot(&state,1)
    testing.expect(t,!view.active && view.energized && view.level == 1 && view.power_need_kw == 10)
    run_ticks(&state,30)
    view = snapshot(&state,1)
    testing.expect(t,view.level > 0 && view.level < 1 && view.energized && view.power_need_kw == 10)
    testing.expect(t,balance(&state).available_kw == 0)
    level := view.level
    testing.expect(t,toggle(&state,{id="L"}) == .Applied)
    testing.expect(t,state.level[1] == level && snapshot(&state,1).energized && balance(&state).consumed_kw == 10)
    run_ticks(&state,30)
    testing.expect(t,state.level[1] == 1)
    testing.expect(t,toggle(&state,{id="L"}) == .Applied)
    run_ticks(&state,59)
    testing.expect(t,snapshot(&state,1).energized && balance(&state).consumed_kw == 10)
    run_ticks(&state,1)
    view = snapshot(&state,1)
    testing.expect(t,!view.active && !view.energized && view.level == 0 && view.power_need_kw == 0)
    testing.expect(t,balance(&state).available_kw == 10)
    testing.expect(t,toggle(&state,{id="L"}) == .Applied)
    testing.expect(t,snapshot(&state,1).level == 0 && snapshot(&state,1).energized && balance(&state).consumed_kw == 10)
    // A command reversed before any warmup tick is already at zero.
    testing.expect(t,toggle(&state,{id="L"}) == .Applied)
    testing.expect(t,!snapshot(&state,1).energized && balance(&state).consumed_kw == 0)
    state.timing[1].warmup_hours = 0
    state.timing[1].cooldown_hours = 0
    testing.expect(t,toggle(&state,{id="L"}) == .Applied)
    testing.expect(t,toggle(&state,{id="L"}) == .Applied)
    testing.expect(t,state.level[1] == 0 && !snapshot(&state,1).energized && balance(&state).consumed_kw == 0)
}
