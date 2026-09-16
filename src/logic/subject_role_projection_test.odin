package logic

import "core:testing"

@(test)
subject_role_projection_lifetime :: proc(t: ^testing.T) {
    roles := [?]Subject_Role_Definition{{role_id=.repairer,sprite="assets/custom.png"},{role_id=.worker}}
    types := [?]Subject_Type{{id="human",roles=roles[:]}}
    state := new_transports({}, {}, nil, nil, nil, context.allocator, nil, types[:])
    defer destroy_transports(&state, context.allocator)
    for _ in 0..<2 {
        index := add_runtime_subject(&state,{subject_id="human"})
        testing.expect(t, index >= 0)
        actual := state.subjects[index].roles
        testing.expect(t, len(actual) == 2 && actual[0] == .repairer && actual[1] == .worker)
        reset_transports(&state, {}, nil, nil)
    }
}
