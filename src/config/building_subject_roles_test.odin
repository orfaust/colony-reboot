package config

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
building_subject_roles_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    for roles in ([?]string{`[]`, `[{"role_id":"worker","quantity":0,"required":true}]`, `[{"role_id":"repairer","quantity":0.5,"required":false}]`}) {
        replacement := fmt.aprintf("\"subject_roles\":%s", roles, allocator=allocator)
        data, _ := strings.replace_all(building_fixture, `"subject_roles":[]`, replacement, allocator)
        catalog, err := decode_catalog(transmute([]byte)data,resources,texts,allocator)
        testing.expect(t, err == "", err)
        if err == "" && len(catalog.buildings[0].subject_roles) > 0 {
            role := catalog.buildings[0].subject_roles[0]
            testing.expect(t, role.quantity == (role.required ? 0 : 0.5))
        }
    }
    for roles in ([?]string{`null`, `["worker"]`, `[{}]`, `[{"role_id":"farmer","quantity":1,"required":true}]`, `[{"role_id":"worker","quantity":-1,"required":true}]`, `[{"role_id":"worker","quantity":1e100,"required":true}]`, `[{"role_id":"worker","quantity":1}]`, `[{"role_id":"worker","required":true}]`, `[{"role_id":"worker","quantity":1,"required":"true"}]`, `[{"role_id":"worker","quantity":1,"required":null}]`, `[{"role_id":"worker","quantity":1,"required":true,"unknown":0}]`, `[{"role_id":"worker","quantity":1,"required":true},{"role_id":"worker","quantity":2,"required":false}]`}) {
        replacement := fmt.aprintf("\"subject_roles\":%s", roles, allocator=allocator)
        data, _ := strings.replace_all(building_fixture, `"subject_roles":[]`, replacement, allocator)
        _, err := decode_catalog(transmute([]byte)data,resources,texts,allocator)
        testing.expect(t, strings.contains(err,"subject_roles"), err)
    }
    legacy, _ := strings.replace_all(building_fixture, `"subject_roles":[]`, `"supervisors_required":0,"workers_required":0,"repairers_required":0`, allocator)
    _, err := decode_catalog(transmute([]byte)legacy,resources,texts,allocator)
    testing.expect(t, err != "")
}
