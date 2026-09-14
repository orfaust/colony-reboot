package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../localization"
import "../logic"

catalog_source :: #load("../../assets/config/buildings.json")
resource_source :: #load("../../assets/config/resources.json")
shipped_level_source :: #load("../../assets/levels/level_0.json")
text_source :: #load("../../assets/localization/en.json")

// Fixed mutation fixtures do not assume user-editable file contents or formatting.
level_source :: string(`{"version":1,"level":0,"buildings":[
  {"id":"CU1","building_id":"control_unit","position":{"x":0,"y":0},"health":0.5,"repairing":false}
]}`)
resource_fixture :: string(`[{"id":"water","name_key":"resource_water_name",
"description_key":"resource_water_description","unit_type_key":"unit_l","color":{"r":0,"g":179,"b":255}}]`)
building_fixture :: string(`[
{"id":"control_unit","name_key":"building_control_unit_name","description_key":"building_control_unit_description",
"code":"CU","width":1.5,"height":1.5,"color":{"r":0,"g":86,"b":179},"power_need_kw":0,"power_output_kw":0,"needs":[],"produces":[]},
{"id":"test_producer","name_key":"building_water_collector_name","description_key":"building_water_collector_description",
"code":"CUSTOM","width":2,"height":0.5,"color":{"r":20,"g":30,"b":40},"power_need_kw":3,"power_output_kw":16,
"needs":[{"resource_id":"water","amount_per_unit":2}],"produces":[{"resource_id":"water","time_per_unit":0.02}]}
]`)

test_texts :: proc(allocator: mem.Allocator) -> map[string]string {
    text, _ := localization.decode(transmute([]byte)text_source,allocator)
    return text.entries
}

@(test)
shipped_configuration :: proc(t: ^testing.T) {
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
    level, level_error := decode_level(transmute([]byte)shipped_level_source,catalog,allocator)
    testing.expect(t,level_error == "",level_error)
    if level_error != "" { return }
    state := logic.new_session(level.buildings,catalog.buildings,allocator)
    for initial, i in level.buildings {
        view := logic.snapshot(&state,i)
        testing.expect(t,view.id == initial.id && view.building_id == initial.building_id)
        testing.expect(t,view.position == initial.position && view.health == initial.health)
        testing.expect(t,view.active == (initial.building_id == "control_unit"))
    }
}

@(test)
array_catalog_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    catalog, error := decode_catalog(transmute([]byte)building_fixture,resources,texts,allocator)
    testing.expect(t,error == "",error)
    if error != "" { return }
    testing.expect(t,len(catalog.buildings) == 2 && catalog.buildings[0].id == "control_unit")
    definition, found := find_building(catalog,"test_producer")
    testing.expect(t,found && definition.code == "CUSTOM" && texts["CUSTOM"] == "")
    testing.expect(t,definition.width == 2 && definition.height == 0.5)
    testing.expect(t,definition.needs[0].amount_per_unit == 2 && definition.produces[0].time_per_unit == 0.02)
    changes := [?][2]string{
        {"\"id\":\"test_producer\"","\"id\":\"control_unit\""},
        {"\"code\":\"CUSTOM\"","\"code\":\"CU\""},
        {"\"id\":\"control_unit\"","\"kind\":\"control_unit\""},
        {"\"id\":\"control_unit\"","\"id\":\"\""},
        {"\"width\":2","\"width\":0"}, {"\"height\":0.5","\"height\":-1"},
        {"\"height\":0.5,",""}, {"\"width\":2","\"width\":null"},
        {"\"b\":179","\"b\":256"}, {"\"b\":179","\"b\":-1"},
        {"\"b\":179","\"b\":1.5"}, {"\"b\":179","\"b\":179,\"b\":0"},
        {"\"power_need_kw\":3","\"power_need_kw\":-1"},
        {"\"power_output_kw\":16","\"power_output_kw\":1e100"},
        {"building_control_unit_name","missing_translation"},
        {"\"resource_id\":\"water\"","\"resource_id\":\"Water\""},
        {"\"amount_per_unit\":2","\"amount_per_unit\":0"},
        {"\"amount_per_unit\":2","\"amount\":2"},
        {"\"time_per_unit\":0.02","\"time_per_unit\":0"},
        {"\"time_per_unit\":0.02","\"time_per_unit\":null"},
        {"\"time_per_unit\":0.02","\"production_time_seconds\":72"},
        {"\"time_per_unit\":0.02","\"hours_per_unit\":0.02"},
    }
    for change in changes {
        modified, _ := strings.replace_all(building_fixture,change[0],change[1],allocator)
        _, invalid := decode_catalog(transmute([]byte)modified,resources,texts,allocator)
        testing.expect(t,invalid != "",change[1])
    }
    invalid_documents := [?]string{"{","{}","null","[]",building_fixture+" {}",`{"version":1,"control_unit":{},"resources":[]}`}
    for source in invalid_documents {
        _, invalid := decode_catalog(transmute([]byte)source,resources,texts,allocator)
        testing.expect(t,invalid != "",source)
    }
    _, missing_resource := decode_catalog(transmute([]byte)building_fixture,nil,texts,allocator)
    testing.expect(t,strings.contains(missing_resource,"resource_id"))
}

@(test)
separate_resources_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, error := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    testing.expect(t,error == "" && len(resources) == 1,error)
    empty := "[]"
    resources, error = decode_resources(transmute([]byte)empty,texts,allocator)
    testing.expect(t,error == "" && len(resources) == 0)
    changes := [?][2]string{
        {"\"id\":\"water\"","\"id\":\"\""},
        {"unit_l","missing_unit"}, {"resource_water_name","missing_name"},
        {"\"b\":255","\"b\":256"}, {"\"color\"","\"unknown\""},
    }
    for change in changes {
        modified, _ := strings.replace_all(resource_fixture,change[0],change[1],allocator)
        _, invalid := decode_resources(transmute([]byte)modified,texts,allocator)
        testing.expect(t,invalid != "",change[1])
    }
    duplicate := "["+resource_fixture[1:len(resource_fixture)-1]+","+resource_fixture[1:len(resource_fixture)-1]+"]"
    _, duplicate_error := decode_resources(transmute([]byte)duplicate,texts,allocator)
    testing.expect(t,strings.contains(duplicate_error,"duplicate ID"))
    old_format := `{"resources":[]}`
    _, old_error := decode_resources(transmute([]byte)old_format,texts,allocator)
    testing.expect(t,old_error != "")
}

@(test)
level_references_and_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    catalog, _ := decode_catalog(transmute([]byte)building_fixture,resources,texts,allocator)
    level, error := decode_level(transmute([]byte)level_source,catalog,allocator)
    testing.expect(t,error == "" && level.buildings[0].id == "CU1",error)
    changes := [?][2]string{
        {"\"building_id\":\"control_unit\"","\"building_id\":\"unknown\""},
        {"\"building_id\":\"control_unit\"","\"building_id\":\"Control_Unit\""},
        {"\"building_id\"","\"kind\""}, {"\"id\":\"CU1\"","\"id\":\"\""},
        {"\"version\":1","\"version\":2"}, {"\"level\":0","\"level\":1"},
        {"\"health\":0.5","\"health\":-0.1"}, {"\"health\":0.5","\"health\":1.1"},
        {"\"x\":0","\"x\":1e100"}, {"\"repairing\":false","\"repairing\":null"},
    }
    for change in changes {
        modified, _ := strings.replace_all(level_source,change[0],change[1],allocator)
        _, invalid := decode_level(transmute([]byte)modified,catalog,allocator)
        testing.expect(t,invalid != "",change[1])
    }
    for &definition in catalog.buildings { if definition.id == "control_unit" { definition.power_need_kw = 1 } }
    _, deficit := decode_level(transmute([]byte)level_source,catalog,allocator)
    testing.expect(t,strings.contains(deficit,"initial Control Unit"))
}
