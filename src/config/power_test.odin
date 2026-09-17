package config

import "core:mem"
import "core:testing"
import "../logic"

@(test)
array_ids_drive_power_and_reset :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    catalog, error := decode_catalog(transmute([]byte)building_fixture,resources,texts,allocator)
    testing.expect(t,error == "",error)
    if error != "" { return }
    initial := [?]logic.Building_Instance{
        {id="CU1",building_id="control_unit",health=1},
        {id="P1",building_id="test_producer",health=1},
    }
    // Warmup rules are covered in logic; start instantly so the producer powers itself.
    // Staffing coverage has dedicated logic tests, so this fixture clears the
    // continuous slots and isolates the decoded power network from the staffing gate.
    for &definition in catalog.buildings { definition.warmup_time = 0; definition.subject_roles = nil }
    state := logic.new_session(initial[:],catalog.buildings,allocator)
    testing.expect(t,state.active[0] && !state.active[1])
    testing.expect(t,logic.toggle(&state,{id="P1"}) == .Applied)
    testing.expect(t,logic.balance(&state).available_kw == 16)
    testing.expect(t,logic.toggle(&state,{id="CU1"}) == .Control_Unit_Locked)
    logic.reset(&state,initial[:])
    testing.expect(t,state.active[0] && !state.active[1])
}
