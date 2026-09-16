package logic

import "core:testing"

@(test)
activation_and_power_guards :: proc(t: ^testing.T) {
    definitions := [?]Building_Type{
        {id="control_unit"}, {id="solar_panel",power_output_kw=16},
        {id="robots_warehouse",power_need_kw=7}, {id="water_collector",power_need_kw=3},
        {id="green_house",power_need_kw=8},
    }
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1}, {id="SP1",building_id="solar_panel",health=1},
        {id="SP2",building_id="solar_panel",health=1}, {id="RW1",building_id="robots_warehouse",health=1},
        {id="WC1",building_id="water_collector",health=1}, {id="GH1",building_id="green_house",health=1},
    }
    state := new_session(initial[:], definitions[:], context.allocator)
    defer destroy(&state, context.allocator)
    for active, i in state.active { testing.expect(t, active == (i == 0)) }
    testing.expect(t, balance(&state).available_kw == 0)
    testing.expect(t, toggle(&state, {id="CU1"}) == .Control_Unit_Locked)
    testing.expect(t, toggle(&state, {id="unknown"}) == .Unknown_Building)
    testing.expect(t, toggle(&state, {id="RW1"}) == .Insufficient_Power)
    testing.expect(t, !snapshot(&state,3).active && snapshot(&state,3).power_need_kw == 0)
    testing.expect(t, toggle(&state, {id="SP1"}) == .Applied)
    testing.expect(t, snapshot(&state,1).power_output_kw == 16)
    testing.expect(t, toggle(&state, {id="RW1"}) == .Applied)
    testing.expect(t, toggle(&state, {id="WC1"}) == .Applied)
    testing.expect(t, balance(&state).available_kw == 6)
    testing.expect(t, toggle(&state, {id="GH1"}) == .Insufficient_Power)
    testing.expect(t, !state.active[5] && balance(&state).available_kw == 6)
    testing.expect(t, toggle(&state, {id="SP1"}) == .Generator_Required)
    testing.expect(t, state.active[1] && balance(&state).available_kw == 6)
    testing.expect(t, toggle(&state, {id="SP2"}) == .Applied)
    testing.expect(t, toggle(&state, {id="GH1"}) == .Applied)
    testing.expect(t, balance(&state).produced_kw == 32 && balance(&state).consumed_kw == 18)
    testing.expect(t, toggle(&state, {id="SP1"}) == .Generator_Required)
    testing.expect(t, toggle(&state, {id="WC1"}) == .Applied)
    testing.expect(t, toggle(&state, {id="SP1"}) == .Generator_Required)
    testing.expect(t, balance(&state).available_kw == 17)
    testing.expect(t, snapshot(&state,1).power_output_kw == 16)
    testing.expect(t, toggle(&state, {id="CU1"}) == .Control_Unit_Locked)
    reset(&state, initial[:])
    for active, i in state.active { testing.expect(t, active == (i == 0)) }
    testing.expect(t, balance(&state).available_kw == 0)
}

@(test)
combined_producer_consumer_and_exact_capacity :: proc(t: ^testing.T) {
    definitions := [?]Building_Type{
        {id="control_unit",power_need_kw=1,power_output_kw=1},
        {id="combined",power_output_kw=5,power_need_kw=3},
        {id="consumer",power_need_kw=2},
    }
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1},
        {id="P1",building_id="combined",health=1}, {id="C1",building_id="consumer",health=1},
    }
    state := new_session(initial[:], definitions[:], context.allocator)
    defer destroy(&state, context.allocator)
    testing.expect(t, toggle(&state, {id="P1"}) == .Applied)
    testing.expect(t, balance(&state).available_kw == 2)
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    testing.expect(t, balance(&state).available_kw == 0)
    testing.expect(t, toggle(&state, {id="P1"}) == .Generator_Required)
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    testing.expect(t, toggle(&state, {id="P1"}) == .Generator_Required)
    testing.expect(t, state.active[1] && balance(&state).available_kw == 2)
    testing.expect(t, initial_balance(initial[:], definitions[:]) == 0)
    definitions[0].power_need_kw = 2
    testing.expect(t, initial_balance(initial[:], definitions[:]) < 0)
}

@(test)
start_activity_and_operative_health :: proc(t: ^testing.T) {
    definitions := [?]Building_Type{
        {id="control_unit"}, {id="solar_panel",power_output_kw=16,min_operative_health=0.5},
        {id="consumer",power_need_kw=4,min_operative_health=0.8},
    }
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=0.1},
        {id="SP1",building_id="solar_panel",health=0.5,enable_at_start=true},
        {id="C1",building_id="consumer",health=0.7},
    }
    state := new_session(initial[:], definitions[:], context.allocator)
    defer destroy(&state, context.allocator)
    testing.expect(t, state.active[0] && state.active[1] && !state.active[2])
    testing.expect(t, balance(&state).available_kw == 16)
    testing.expect(t, initial_balance(initial[:], definitions[:]) == 16)
    testing.expect(t, toggle(&state, {id="C1"}) == .Insufficient_Health)
    testing.expect(t, !state.active[2])
    state.buildings[2].health = 0.8
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    // Consumers may shut down when damaged; generators remain locked.
    state.buildings[1].health = 0
    state.buildings[2].health = 0
    testing.expect(t, toggle(&state, {id="SP1"}) == .Generator_Required)
    testing.expect(t, toggle(&state, {id="C1"}) == .Applied)
    testing.expect(t, toggle(&state, {id="SP1"}) == .Generator_Required)
    testing.expect(t, state.active[1] && balance(&state).available_kw == 16)
    testing.expect(t, toggle(&state, {id="C1"}) == .Insufficient_Health)
    reset(&state, initial[:])
    testing.expect(t, state.active[0] && state.active[1] && !state.active[2] && state.buildings[2].health == 0.7)
}

@(test)
fractional_power_rounding :: proc(t: ^testing.T) {
    testing.expect(t, !power_shortage(f64(f32(0.1))+f64(f32(0.2)), f64(f32(0.3))))
    testing.expect(t, power_shortage(0, 1e-12))
    testing.expect(t, power_shortage(16, 16.01))
}
