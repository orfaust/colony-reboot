package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../localization"
import "../logic"

catalog_source :: #load("../../assets/config/buildings.json")
resource_source :: #load("../../assets/config/resources.json")
subject_source :: #load("../../assets/config/subjects.json")
shipped_level_source :: #load("../../assets/levels/level_0.json")
text_source :: #load("../../assets/localization/en.json")

// Fixed mutation fixtures do not assume user-editable file contents or formatting.
level_source :: string(`{"version":1,"level":0,"space_station":{"station_id":"test_station","distance":0,"resources":[],"subjects":[]},"buildings":[
  {"id":"CU1","building_id":"control_unit","position":{"x":0,"y":0},"health":0.5,"repairing":false,"enable_at_start":true,"stored":[],"residents_amount":null}
],"subjects":[]}`)
enabled_level_fixture :: string(`{"version":1,"level":0,"space_station":{"station_id":"test_station","distance":0,"resources":[],"subjects":[]},"buildings":[
  {"id":"CU1","building_id":"control_unit","position":{"x":0,"y":0},"health":1,"repairing":false,"enable_at_start":true,"stored":[],"residents_amount":null},
  {"id":"P1","building_id":"test_producer","position":{"x":2,"y":0},"health":0.6,"repairing":false,"enable_at_start":true,"stored":[{"resource_id":"water","amount":25}],"residents_amount":1}
],"subjects":[]}`)
resource_fixture :: string(`[{"id":"water","name_key":"resource_water_name",
"description_key":"resource_water_description","unit_type_key":"unit_l","color":{"r":0,"g":179,"b":255}}]`)
building_fixture :: string(`[
{"id":"control_unit","name_key":"building_control_unit_name","description_key":"building_control_unit_description",
"code":"CU","sprite":"assets/sprites/buildings/control_unit.png","width":1.5,"height":1.5,"color":{"r":0,"g":86,"b":179},"power_need_kw":0,"power_output_kw":0,"always_on":true,"warmup_time":0,"cooldown_time":0,"min_operative_health":0,"materials_amount":0,
"subject_roles":[],"residents":null,"needs":[],"produces":[],"storage":[]},
{"id":"test_producer","name_key":"building_water_collector_name","description_key":"building_water_collector_description",
"code":"CUSTOM","sprite":"assets/sprites/buildings/custom.png","width":2,"height":0.5,"color":{"r":20,"g":30,"b":40},"power_need_kw":3,"power_output_kw":16,"always_on":false,"warmup_time":0.5,"cooldown_time":1.25,
"min_operative_health":0.6,"materials_amount":40,"subject_roles":[{"role_id":"supervisor","quantity":1,"required":true},{"role_id":"worker","quantity":2.5,"required":true},{"role_id":"repairer","quantity":0.5,"required":false}],
"residents":{"type":"human","capacity":4},
"needs":[{"resource_id":"water","amount_per_unit":2,"capacity":10}],"produces":[{"resource_id":"water","units_per_hour":50,"capacity":100}],"storage":[]}
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
    subjects, subject_error := decode_subjects(transmute([]byte)subject_source,resources,texts,allocator)
    testing.expect(t,subject_error == "",subject_error)
    catalog.subjects = subjects
    residents_error := validate_residents(catalog,allocator)
    testing.expect(t,residents_error == "",residents_error)
    testing.expect(t,load_space_stations(&catalog,texts,allocator))
    level, level_error := decode_level(transmute([]byte)shipped_level_source,catalog,allocator)
    testing.expect(t,level_error == "",level_error)
    if level_error != "" { return }
    state := logic.new_session(level.buildings,catalog.buildings,allocator)
    for initial, i in level.buildings {
        view := logic.snapshot(&state,i)
        testing.expect(t,view.id == initial.id && view.building_id == initial.building_id)
        testing.expect(t,view.position == initial.position && view.health == initial.health)
        testing.expect(t,view.active == logic.starts_active(initial))
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
    testing.expect(t,definition.warmup_time == 0.5 && definition.cooldown_time == 1.25)
    testing.expect(t,!definition.always_on && catalog.buildings[0].always_on)
    testing.expect(t,definition.min_operative_health == 0.6 && definition.materials_amount == 40)
    testing.expect(t,len(definition.subject_roles) == 3 && definition.subject_roles[0].quantity == 1 && definition.subject_roles[1].quantity == 2.5 && definition.subject_roles[2].quantity == 0.5 && !definition.subject_roles[2].required)
    testing.expect(t,definition.produces[0].capacity == 100 && definition.needs[0].capacity == 10)
    testing.expect(t,definition.residents.type == "human" && definition.residents.capacity == 4 && logic.hosts_residents(definition))
    testing.expect(t,!logic.hosts_residents(catalog.buildings[0]))
    testing.expect(t,definition.needs[0].amount_per_unit == 2 && definition.produces[0].units_per_hour == 50)
    hourly, _ := strings.replace_all(building_fixture,"\"amount_per_unit\":2","\"amount_per_hour\":4",allocator)
    hourly_catalog, hourly_error := decode_catalog(transmute([]byte)hourly,resources,texts,allocator)
    testing.expect(t,hourly_error == "",hourly_error)
    if hourly_error == "" {
        need := hourly_catalog.buildings[1].needs[0]
        testing.expect(t,need.amount_per_hour == 4 && need.amount_per_unit == 0)
    }
    per_resident, _ := strings.replace_all(building_fixture,"\"amount_per_unit\":2","\"amount_per_resident\":0.5",allocator)
    resident_catalog, resident_error := decode_catalog(transmute([]byte)per_resident,resources,texts,allocator)
    testing.expect(t,resident_error == "",resident_error)
    if resident_error == "" {
        need := resident_catalog.buildings[1].needs[0]
        testing.expect(t,need.amount_per_resident == 0.5 && need.amount_per_unit == 0 && need.amount_per_hour == 0)
    }
    // amount_per_resident is only allowed on buildings with residents.
    no_residents, _ := strings.replace_all(per_resident,"\"residents\":{\"type\":\"human\",\"capacity\":4}","\"residents\":null",allocator)
    _, resident_need_error := decode_catalog(transmute([]byte)no_residents,resources,texts,allocator)
    testing.expect(t,strings.contains(resident_need_error,"requires residents"),resident_need_error)
    // Products may use amount_per_resident instead of units_per_hour, again only with residents.
    resident_product, _ := strings.replace_all(building_fixture,"\"units_per_hour\":50","\"amount_per_resident\":0.25",allocator)
    product_catalog, product_error := decode_catalog(transmute([]byte)resident_product,resources,texts,allocator)
    testing.expect(t,product_error == "",product_error)
    if product_error == "" {
        product := product_catalog.buildings[1].produces[0]
        testing.expect(t,product.amount_per_resident == 0.25 && product.units_per_hour == 0)
    }
    unhosted_product, _ := strings.replace_all(resident_product,"\"residents\":{\"type\":\"human\",\"capacity\":4}","\"residents\":null",allocator)
    _, unhosted_error := decode_catalog(transmute([]byte)unhosted_product,resources,texts,allocator)
    testing.expect(t,strings.contains(unhosted_error,"produces[0]: amount_per_resident requires residents"),unhosted_error)
    // storage lists extra resources a building can hold.
    stocked, _ := strings.replace_all(building_fixture,"\"storage\":[]","\"storage\":[{\"resource_id\":\"water\",\"capacity\":5}]",allocator)
    storage_catalog, storage_error := decode_catalog(transmute([]byte)stocked,resources,texts,allocator)
    testing.expect(t,storage_error == "",storage_error)
    if storage_error == "" {
        testing.expect(t,len(storage_catalog.buildings[0].storage) == 1 && storage_catalog.buildings[0].storage[0].resource_id == "water" && storage_catalog.buildings[0].storage[0].capacity == 5)
    }
    storage_mutations := [?][2]string{
        {"\"capacity\":5}", "\"capacity\":-1}"},
        {"\"capacity\":5}", "\"capacity\":null}"},
        {",\"capacity\":5}", "}"},
        {"{\"resource_id\":\"water\",\"capacity\":5}", "{\"resource_id\":\"Water\",\"capacity\":5}"},
        {"{\"resource_id\":\"water\",\"capacity\":5}", "{\"resource_id\":\"water\",\"capacity\":5},{\"resource_id\":\"water\",\"capacity\":1}"},
        {"{\"resource_id\":\"water\",\"capacity\":5}", "{\"resource_id\":\"water\",\"capacity\":5,\"amount\":1}"},
    }
    for change in storage_mutations {
        modified, _ := strings.replace_all(stocked,change[0],change[1],allocator)
        _, invalid := decode_catalog(transmute([]byte)modified,resources,texts,allocator)
        testing.expect(t,invalid != "",change[1])
    }
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
        {"\"warmup_time\":0.5","\"warmup_time\":-1"},
        {"\"cooldown_time\":1.25","\"cooldown_time\":-0.5"},
        {"\"warmup_time\":0.5,",""}, {"\"cooldown_time\":1.25,",""},
        {"\"warmup_time\":0.5","\"warmup_time\":null"},
        {"\"always_on\":false","\"always_on\":null"},
        {"\"always_on\":false","\"always_on\":0"},
        {"\"always_on\":false","\"always_on\":\"false\""},
        {"\"always_on\":false,",""},
        {",\"storage\":[]",""},
        {"\"storage\":[]","\"storage\":null"},
        {"\"min_operative_health\":0.6","\"min_operative_health\":1.5"},
        {"\"min_operative_health\":0.6","\"min_operative_health\":-0.1"},
        {"\"min_operative_health\":0.6,",""},
        {"\"materials_amount\":40","\"materials_amount\":-1"},
        {`"quantity":1`, `"quantity":-1`},
        {`"quantity":2.5`, `"quantity":null`},
        {`"quantity":0.5`, `"quantity":-0.5`},
        {`"subject_roles":[],`, ""},
        {"\"capacity\":100","\"capacity\":-1"},
        {"\"capacity\":10}","\"capacity\":-1}"},
        {",\"capacity\":10}","}"},
        {"\"capacity\":10}","\"capacity\":null}"},
        {"\"capacity\":4}","\"capacity\":0}"},
        {"\"capacity\":4}","\"capacity\":-1}"},
        {"\"capacity\":4}","\"capacity\":null}"},
        {",\"capacity\":4}","}"},
        {"\"type\":\"human\"","\"type\":\"\""},
        {"\"type\":\"human\",",""},
        {"{\"type\":\"human\",\"capacity\":4}","[\"human\"]"},
        {"\"residents\":{\"type\":\"human\",\"capacity\":4},",""},
        {"\"residents\":{\"type\":\"human\",\"capacity\":4}","\"host_type\":[\"human\"],\"host_amount\":4"},
        {"\"capacity\":100","\"capacity\":100,\"stored\":25"},
        {"building_control_unit_name","missing_translation"},
        {"\"resource_id\":\"water\"","\"resource_id\":\"Water\""},
        {"\"amount_per_unit\":2","\"amount_per_unit\":0"},
        {"\"amount_per_unit\":2","\"amount\":2"},
        {",\"amount_per_unit\":2",""},
        {"\"amount_per_unit\":2","\"amount_per_hour\":0"},
        {"\"amount_per_unit\":2","\"amount_per_hour\":-1"},
        {"\"amount_per_unit\":2","\"amount_per_unit\":2,\"amount_per_hour\":1"},
        {"\"amount_per_unit\":2","\"amount_per_resident\":0"},
        {"\"amount_per_unit\":2","\"amount_per_resident\":-1"},
        {"\"amount_per_unit\":2","\"amount_per_resident\":null"},
        {"\"amount_per_unit\":2","\"amount_per_unit\":2,\"amount_per_resident\":1"},
        {"\"amount_per_unit\":2","\"amount_per_hour\":1,\"amount_per_resident\":1"},
        {"\"units_per_hour\":50","\"units_per_hour\":0"},
        {"\"units_per_hour\":50","\"units_per_hour\":-1"},
        {"\"units_per_hour\":50","\"units_per_hour\":null"},
        // The former hours-per-unit field is rejected on building products.
        {"\"units_per_hour\":50","\"time_per_unit\":0.02"},
        {"\"units_per_hour\":50","\"production_time_seconds\":72"},
        {"\"units_per_hour\":50","\"amount_per_resident\":0"},
        {"\"units_per_hour\":50","\"amount_per_resident\":-1"},
        {"\"units_per_hour\":50","\"amount_per_resident\":null"},
        {"\"units_per_hour\":50","\"units_per_hour\":50,\"amount_per_resident\":1"},
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
    stations := [?]logic.Space_Station{{id="test_station"}}
    catalog.space_stations = stations[:]
    level, error := decode_level(transmute([]byte)level_source,catalog,allocator)
    testing.expect(t,error == "" && level.buildings[0].id == "CU1",error)
    changes := [?][2]string{
        {"\"building_id\":\"control_unit\"","\"building_id\":\"unknown\""},
        {"\"building_id\":\"control_unit\"","\"building_id\":\"Control_Unit\""},
        {"\"building_id\"","\"kind\""}, {"\"id\":\"CU1\"","\"id\":\"\""},
        {"\"version\":1","\"version\":2"}, {"\"level\":0","\"level\":1"},
        {"\"health\":0.5","\"health\":-0.1"}, {"\"health\":0.5","\"health\":1.1"},
        {"\"x\":0","\"x\":1e100"}, {"\"repairing\":false","\"repairing\":null"},
        {"\"enable_at_start\":true","\"enable_at_start\":null"}, {",\"enable_at_start\":true",""},
        // The control_unit fixture type is always_on.
        {"\"enable_at_start\":true","\"enable_at_start\":false"},
    }
    for change in changes {
        modified, _ := strings.replace_all(level_source,change[0],change[1],allocator)
        _, invalid := decode_level(transmute([]byte)modified,catalog,allocator)
        testing.expect(t,invalid != "",change[1])
    }
    enabled, enabled_error := decode_level(transmute([]byte)enabled_level_fixture,catalog,allocator)
    testing.expect(t,enabled_error == "",enabled_error)
    if enabled_error == "" {
        state := logic.new_session(enabled.buildings,catalog.buildings,allocator)
        testing.expect(t,state.active[0] && state.active[1])
        testing.expect(t,state.buildings[1].stored[0].amount == 25)
        amount, has_amount := enabled.buildings[1].residents_amount.?
        testing.expect(t,has_amount && amount == 1)
        _, control_unit_amount := enabled.buildings[0].residents_amount.?
        testing.expect(t,!control_unit_amount)
    }
    storage_changes := [?][2]string{
        {",\"stored\":[]", ""},
        {"\"amount\":25", "\"amount\":-1"},
        {"\"amount\":25", "\"amount\":101"},
        {"\"amount\":25", "\"amount\":null"},
        {"\"amount\":25", "\"amount\":1e100"},
        {"\"resource_id\":\"water\"", "\"resource_id\":\"unknown\""},
        {"[{\"resource_id\":\"water\",\"amount\":25}]", "[]"},
        {"[{\"resource_id\":\"water\",\"amount\":25}]", "[{\"resource_id\":\"water\",\"amount\":0},{\"resource_id\":\"water\",\"amount\":25}]"},
    }
    for change in storage_changes {
        modified, _ := strings.replace_all(enabled_level_fixture,change[0],change[1],allocator)
        _, invalid := decode_level(transmute([]byte)modified,catalog,allocator)
        testing.expect(t,strings.contains(invalid,"stored"),invalid)
    }
    // test_producer hosts up to 4 residents; the Control Unit has none.
    residents_changes := [?][2]string{
        {"\"residents_amount\":1", "\"residents_amount\":null"},
        {"\"residents_amount\":1", "\"residents_amount\":4.5"},
        {"\"residents_amount\":1", "\"residents_amount\":-1"},
        {"\"residents_amount\":1", "\"residents_amount\":\"1\""},
        {",\"residents_amount\":1", ""},
        {"\"stored\":[],\"residents_amount\":null", "\"stored\":[],\"residents_amount\":0"},
    }
    for change in residents_changes {
        modified, _ := strings.replace_all(enabled_level_fixture,change[0],change[1],allocator)
        _, invalid := decode_level(transmute([]byte)modified,catalog,allocator)
        testing.expect(t,strings.contains(invalid,"residents_amount"),invalid)
    }
    residents_bounds := [?]string{"\"residents_amount\":0", "\"residents_amount\":4"}
    for bound in residents_bounds {
        modified, _ := strings.replace_all(enabled_level_fixture,"\"residents_amount\":1",bound,allocator)
        _, valid := decode_level(transmute([]byte)modified,catalog,allocator)
        testing.expect(t,valid == "",valid)
    }
    // test_producer needs (capacity 10) and produces (capacity 100) water: one entry, larger bound.
    boundary_amounts := [?]string{"\"amount\":0", "\"amount\":100"}
    for amount in boundary_amounts {
        modified, _ := strings.replace_all(enabled_level_fixture,"\"amount\":25",amount,allocator)
        _, valid := decode_level(transmute([]byte)modified,catalog,allocator)
        testing.expect(t,valid == "",valid)
    }
    // Without products, water is stored only as a need, bounded by the need capacity.
    products := catalog.buildings[1].produces
    catalog.buildings[1].produces = nil
    _, need_overflow := decode_level(transmute([]byte)enabled_level_fixture,catalog,allocator)
    testing.expect(t,strings.contains(need_overflow,"capacity"),need_overflow)
    need_full, _ := strings.replace_all(enabled_level_fixture,"\"amount\":25","\"amount\":10",allocator)
    _, need_valid := decode_level(transmute([]byte)need_full,catalog,allocator)
    testing.expect(t,need_valid == "",need_valid)
    need_missing, _ := strings.replace_all(enabled_level_fixture,"[{\"resource_id\":\"water\",\"amount\":25}]","[]",allocator)
    _, missing_need := decode_level(transmute([]byte)need_missing,catalog,allocator)
    testing.expect(t,strings.contains(missing_need,"needed resource"),missing_need)
    catalog.buildings[1].produces = products
    // A resource the type only lists in storage still needs a stored entry, within its capacity.
    catalog.buildings[0].storage = []logic.Storage{{resource_id="water", capacity=5}}
    _, missing_storage := decode_level(transmute([]byte)enabled_level_fixture,catalog,allocator)
    testing.expect(t,strings.contains(missing_storage,"missing entry for stored resource"),missing_storage)
    stocked_level, _ := strings.replace_all(enabled_level_fixture,"\"enable_at_start\":true,\"stored\":[],","\"enable_at_start\":true,\"stored\":[{\"resource_id\":\"water\",\"amount\":5}],",allocator)
    _, stocked_valid := decode_level(transmute([]byte)stocked_level,catalog,allocator)
    testing.expect(t,stocked_valid == "",stocked_valid)
    overfull, _ := strings.replace_all(stocked_level,"\"amount\":5}","\"amount\":6}",allocator)
    _, overfull_error := decode_level(transmute([]byte)overfull,catalog,allocator)
    testing.expect(t,strings.contains(overfull_error,"capacity"),overfull_error)
    catalog.buildings[0].storage = nil
    // Instances of an always_on type must start enabled.
    catalog.buildings[1].always_on = true
    _, always_on_valid := decode_level(transmute([]byte)enabled_level_fixture,catalog,allocator)
    testing.expect(t,always_on_valid == "",always_on_valid)
    switched_off, _ := strings.replace_all(enabled_level_fixture,"\"health\":0.6,\"repairing\":false,\"enable_at_start\":true","\"health\":0.6,\"repairing\":false,\"enable_at_start\":false",allocator)
    _, always_on_error := decode_level(transmute([]byte)switched_off,catalog,allocator)
    testing.expect(t,strings.contains(always_on_error,"is always_on"),always_on_error)
    catalog.buildings[1].always_on = false
    _, regular_off := decode_level(transmute([]byte)switched_off,catalog,allocator)
    testing.expect(t,regular_off == "",regular_off)
    damaged, _ := strings.replace_all(enabled_level_fixture,"\"health\":0.6","\"health\":0.59",allocator)
    _, damaged_error := decode_level(transmute([]byte)damaged,catalog,allocator)
    testing.expect(t,strings.contains(damaged_error,"min_operative_health"))
    // A damaged building may still be placed inactive.
    inactive, _ := strings.replace_all(damaged,"\"health\":0.59,\"repairing\":false,\"enable_at_start\":true","\"health\":0.59,\"repairing\":false,\"enable_at_start\":false",allocator)
    _, inactive_error := decode_level(transmute([]byte)inactive,catalog,allocator)
    testing.expect(t,inactive_error == "",inactive_error)
    for &definition in catalog.buildings { if definition.id == "test_producer" { definition.power_output_kw = 0 } }
    _, enabled_deficit := decode_level(transmute([]byte)enabled_level_fixture,catalog,allocator)
    testing.expect(t,strings.contains(enabled_deficit,"initial power demand"))
    for &definition in catalog.buildings { if definition.id == "test_producer" { definition.power_output_kw = 16 } }
    for &definition in catalog.buildings { if definition.id == "control_unit" { definition.power_need_kw = 1 } }
    _, deficit := decode_level(transmute([]byte)level_source,catalog,allocator)
    testing.expect(t,strings.contains(deficit,"initial power demand"))
}
