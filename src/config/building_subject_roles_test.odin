package config

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:testing"
import "../logic"

@(test)
building_subject_roles_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    for roles in ([?]string{
        `[]`,
        `[{"role_id":"worker","quantity":0,"staffing_mode":"continuous"}]`,
        `[{"role_id":"repairer","quantity":1,"staffing_mode":"on_demand"}]`,
    }) {
        replacement := fmt.aprintf("\"subject_roles\":%s", roles, allocator=allocator)
        data, _ := strings.replace_all(building_fixture, `"subject_roles":[]`, replacement, allocator)
        catalog, err := decode_catalog(transmute([]byte)data,resources,texts,allocator)
        testing.expect(t, err == "", err)
        if err == "" && len(catalog.buildings[0].subject_roles) > 0 {
            role := catalog.buildings[0].subject_roles[0]
            testing.expect(t, role.staffing_mode == (role.role_id == .repairer ? logic.Staffing_Mode.on_demand : logic.Staffing_Mode.continuous))
            testing.expect(t, role.quantity == (role.role_id == .repairer ? 1 : 0))
        }
    }
    // Fractional quantities are rejected: a slot count is an individual integer.
    for roles in ([?]string{
        `null`,
        `["worker"]`,
        `[{}]`,
        `[{"role_id":"farmer","quantity":1,"staffing_mode":"continuous"}]`,
        `[{"role_id":"worker","quantity":-1,"staffing_mode":"continuous"}]`,
        `[{"role_id":"worker","quantity":1.5,"staffing_mode":"continuous"}]`,
        `[{"role_id":"worker","quantity":1e100,"staffing_mode":"continuous"}]`,
        `[{"role_id":"worker","quantity":1}]`,
        `[{"role_id":"worker","staffing_mode":"continuous"}]`,
        `[{"role_id":"worker","quantity":1,"required":true}]`, // legacy `required` is rejected
        `[{"role_id":"worker","quantity":1,"staffing_mode":"continuous","required":true}]`,
        `[{"role_id":"worker","quantity":1,"staffing_mode":"sometimes"}]`,
        `[{"role_id":"worker","quantity":1,"staffing_mode":null}]`,
        `[{"role_id":"worker","quantity":1,"staffing_mode":"continuous","unknown":0}]`,
        `[{"role_id":"worker","quantity":1,"staffing_mode":"continuous"},{"role_id":"worker","quantity":2,"staffing_mode":"continuous"}]`,
    }) {
        replacement := fmt.aprintf("\"subject_roles\":%s", roles, allocator=allocator)
        data, _ := strings.replace_all(building_fixture, `"subject_roles":[]`, replacement, allocator)
        _, err := decode_catalog(transmute([]byte)data,resources,texts,allocator)
        testing.expect(t, strings.contains(err,"subject_roles"), err)
    }
    // The error path stays actionable for a fractional quantity.
    fractional, _ := strings.replace_all(building_fixture, `"subject_roles":[]`, `"subject_roles":[{"role_id":"worker","quantity":1.5,"staffing_mode":"continuous"}]`, allocator)
    _, err := decode_catalog(transmute([]byte)fractional,resources,texts,allocator)
    testing.expect(t, strings.contains(err,"subject_roles[0].quantity"), err)
    legacy, _ := strings.replace_all(building_fixture, `"subject_roles":[]`, `"supervisors_required":0,"workers_required":0,"repairers_required":0`, allocator)
    _, legacy_err := decode_catalog(transmute([]byte)legacy,resources,texts,allocator)
    testing.expect(t, legacy_err != "")
}
