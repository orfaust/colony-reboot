package logic

import "core:testing"

@(private="file")
run_ticks :: proc(state: ^State, ticks: int) {
    for _ in 0..<ticks { step(state) }
}

@(test)
warmup_ramps_output_while_need_stays_constant :: proc(t: ^testing.T) {
    definitions := [?]Building_Type{
        {id="control_unit"}, {id="generator",power_output_kw=16,warmup_time=2,cooldown_time=4},
        {id="consumer",power_need_kw=8,warmup_time=6,cooldown_time=18},
    }
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1}, {id="G1",building_id="generator",health=1},
        {id="C1",building_id="consumer",health=1},
    }
    state := new_session(initial[:], definitions[:], context.allocator)
    defer destroy(&state, context.allocator)
    testing.expect(t, toggle(&state, {id="G1"}) == .Applied)
    testing.expect(t, snapshot(&state,1).active && snapshot(&state,1).power_output_kw == 0)
    // The lock uses configured output, even at zero actual output during warmup.
    before := snapshot(&state,1)
    testing.expect(t, toggle(&state, {id="G1"}) == .Generator_Required)
    testing.expect(t, snapshot(&state,1) == before)
    run_ticks(&state, 90) // 1.5 of 2 warmup hours.
    testing.expect(t, abs(snapshot(&state,1).level-0.75) < 1e-9)
    testing.expect(t, abs(snapshot(&state,1).power_output_kw-12) < 1e-9)
    // Consumption is full from the click, although the consumer's own startup is slow.
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    consumer := snapshot(&state,2)
    testing.expect(t, consumer.power_need_kw == 8 && consumer.level == 0)
    run_ticks(&state, 30)
    testing.expect(t, snapshot(&state,1).power_output_kw == 16 && balance(&state).available_kw == 8)
    run_ticks(&state, 150)
    consumer = snapshot(&state,2)
    testing.expect(t, abs(consumer.level-0.5) < 1e-9 && consumer.power_need_kw == 8)
    // Shutdown retains full consumption while the startup level falls.
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    testing.expect(t, snapshot(&state,2).power_need_kw == 8 && balance(&state).consumed_kw == 8)
    run_ticks(&state, 1)
    testing.expect(t, snapshot(&state,2).level < 0.5)
    // The generator still cannot enter cooldown.
    testing.expect(t, toggle(&state, {id="G1"}) == .Generator_Required)
    run_ticks(&state, 120)
    // Consumer cooldown can still reverse without resetting its progress.
    consumer_level := state.level[2]
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    testing.expect(t, state.level[2] == consumer_level)
    run_ticks(&state, 60)
    testing.expect(t, state.level[2] > consumer_level)
    testing.expect(t, snapshot(&state,1).level == 1 && snapshot(&state,1).power_output_kw == 16)
    reset(&state, initial[:])
    testing.expect(t, state.level[0] == 1 && state.level[1] == 0 && state.level[2] == 0)
}

@(test)
ramps_never_create_a_deficit :: proc(t: ^testing.T) {
    definitions := [?]Building_Type{
        {id="control_unit"}, {id="generator",power_output_kw=10,warmup_time=1,cooldown_time=1},
        {id="consumer",power_need_kw=10,cooldown_time=2}, {id="other",power_need_kw=10},
    }
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1}, {id="G1",building_id="generator",health=1},
        {id="C1",building_id="consumer",health=1}, {id="O1",building_id="other",health=1},
    }
    state := new_session(initial[:], definitions[:], context.allocator)
    defer destroy(&state, context.allocator)
    // A cold generator offers nothing until it has warmed up.
    testing.expect(t, toggle(&state, {id="G1"}) == .Applied)
    testing.expect(t, toggle(&state, {id="C1"}) == .Insufficient_Power)
    run_ticks(&state, 60)
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    testing.expect(t, toggle(&state, {id="G1"}) == .Generator_Required)
    // A cooling consumer retains its budget until completion.
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    testing.expect(t, toggle(&state, {id="O1"}) == .Insufficient_Power)
    testing.expect(t, toggle(&state, {id="G1"}) == .Generator_Required)
    testing.expect(t, state.active[1] && state.level[1] == 1)
    for _ in 0..<60 {
        step(&state)
        testing.expect(t, balance(&state).available_kw >= 0)
    }
    testing.expect(t, toggle(&state, {id="O1"}) == .Insufficient_Power)
    run_ticks(&state,60)
    testing.expect(t, toggle(&state, {id="O1"}) == .Applied)
}
