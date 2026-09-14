package logic

import "core:testing"

@(test)
initial_session_and_snapshot :: proc(t: ^testing.T) {
    initial := [?]Building_Instance{
        {id="CU1", building_id="control_unit", position={0,0}, health=0.5},
        {id="CU2", building_id="control_unit", position={2,3}, health=1, repairing=true},
    }
    definitions := [?]Building_Type{{id="control_unit"}}
    state := new_session(initial[:], definitions[:], context.allocator)
    defer destroy(&state, context.allocator)
    view := snapshot(&state,0)
    testing.expect(t, view.id == "CU1" && view.building_id == "control_unit" && view.active)
    testing.expect(t, view.health == 0.5 && !view.repairing)
    state.buildings[0].health = 0.1
    testing.expect(t, initial[0].health == 0.5)
    reset(&state,initial[:])
    testing.expect(t, state.buildings[0].health == 0.5)
    second := snapshot(&state,1)
    testing.expect(t, second.id == "CU2" && second.position.x == 2 && second.repairing)
}

@(test)
empty_session :: proc(t: ^testing.T) {
    state := new_session(nil,nil,context.allocator)
    defer destroy(&state,context.allocator)
    reset(&state,nil)
    testing.expect(t, len(state.buildings) == 0)
}

@(test)
invalid_instances :: proc(t: ^testing.T) {
    building := Building_Instance{id="CU1",building_id="control_unit",health=0.5}
    testing.expect(t, valid_instance(building))
    building.id = ""
    testing.expect(t, !valid_instance(building))
    building.id = "CU1"
    building.health = -0.1
    testing.expect(t, !valid_instance(building))
    building.health = 1.1
    testing.expect(t, !valid_instance(building))
    building.health = 0
    testing.expect(t, valid_instance(building))
    building.health = 1
    testing.expect(t, valid_instance(building))
    building.position.x = transmute(f32)u32(0x7f800000)
    testing.expect(t, !valid_instance(building))
    building.position.x = 0
    building.health = transmute(f32)u32(0x7fc00000)
    testing.expect(t, !valid_instance(building))
}
