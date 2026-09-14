package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../logic"

@(test)
shipped_references_and_localization :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, resource_error := decode_resources(transmute([]byte)resource_source,texts,allocator)
    testing.expect(t,resource_error == "",resource_error)
    catalog, error := decode_catalog(transmute([]byte)catalog_source,resources,texts,allocator)
    testing.expect(t,error == "",error)
    if error != "" { return }
    for definition in catalog.buildings {
        testing.expect(t,texts[definition.name_key] != "" && texts[definition.description_key] != "")
        for need in definition.needs { testing.expect(t,resource_exists(resources,need.resource_id)) }
        for product in definition.produces { testing.expect(t,resource_exists(resources,product.resource_id)) }
    }
    cu, found := find_building(catalog,"control_unit")
    testing.expect(t,found)
    if !found { return }
    original := texts[cu.name_key]
    texts[cu.name_key] = ""
    _, missing := decode_catalog(transmute([]byte)catalog_source,resources,texts,allocator)
    testing.expect(t,strings.contains(missing,cu.name_key))
    texts[cu.name_key] = original
    initial := [?]logic.Building_Instance{{id="CU1",building_id="control_unit",health=1}}
    state := logic.new_session(initial[:],catalog.buildings,allocator)
    testing.expect(t,logic.snapshot(&state,0).active)
    testing.expect(t,logic.toggle(&state,{id="CU1"}) == .Control_Unit_Locked)
}
