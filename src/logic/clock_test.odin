package logic

import "core:math"
import "core:testing"

@(test)
clock_advances_in_fixed_steps :: proc(t: ^testing.T) {
    clock: Clock
    testing.expect(t, clock_snapshot(clock) == {elapsed_hours=0, speed=1})
    // 64 frames of 1/64 s at 1x are one hour, even though no single frame completes a tick.
    total := 0
    for _ in 0..<64 { total += advance_clock(&clock, 1.0/64) }
    testing.expect(t, total == 60 && clock_snapshot(clock).elapsed_hours == 1)
    // Uneven frames accumulate fractional ticks instead of losing them.
    for _ in 0..<4 { advance_clock(&clock, 0.125) }
    testing.expect(t, clock.ticks == 90)
    testing.expect(t, advance_clock(&clock, 0) == 0)
    testing.expect(t, advance_clock(&clock, -1) == 0)
    testing.expect(t, advance_clock(&clock, math.nan_f64()) == 0)
    testing.expect(t, clock.ticks == 90)
}

@(test)
clock_speed_levels :: proc(t: ^testing.T) {
    clock: Clock
    testing.expect(t, !change_speed(&clock, .Slower) && clock_snapshot(clock).speed == 1)
    testing.expect(t, change_speed(&clock, .Faster) && clock_snapshot(clock).speed == 2)
    testing.expect(t, advance_clock(&clock, 0.25) == 30)
    for _ in 0..<10 { change_speed(&clock, .Faster) }
    testing.expect(t, clock_snapshot(clock).speed == 32)
    testing.expect(t, !change_speed(&clock, .Faster))
    testing.expect(t, advance_clock(&clock, 0.25) == 480)
    testing.expect(t, change_speed(&clock, .Slower) && clock_snapshot(clock).speed == 16)
}

@(test)
clock_drops_stalls :: proc(t: ^testing.T) {
    clock: Clock
    testing.expect(t, advance_clock(&clock, 100000) == 15)
    for _ in 0..<len(SPEEDS) { change_speed(&clock, .Faster) }
    testing.expect(t, advance_clock(&clock, math.inf_f64(1)) == 480)
    testing.expect(t, clock.pending_ticks == 0)
}

@(test)
reset_restarts_clock :: proc(t: ^testing.T) {
    definitions := [?]Building_Type{{id="control_unit"}}
    initial := [?]Building_Instance{{id="CU1",building_id="control_unit",health=1}}
    state := new_session(initial[:], definitions[:], context.allocator)
    defer destroy(&state, context.allocator)
    change_speed(&state.clock, .Faster)
    advance_clock(&state.clock, 0.2)
    reset(&state, initial[:])
    testing.expect(t, state.clock == Clock{})
}
