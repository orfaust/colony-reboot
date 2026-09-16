package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../logic"

subject_fixture :: string(`[{"id":"human","width":0.5,"height":1.25,"name_key":"resource_water_name","color":{"r":1,"g":2,"b":3},"needs":[{"resource_id":"water","amount_per_hour":0.5,"shortage_alert_time":12,"shortage_max_time":6}],
"rest_time":8,"work_time":10,"roles":[{"role_id":"worker","sprite":""},{"role_id":"repairer","sprite":""}],"produces":[{"resource_id":"water","units_per_hour":2}]}]`)
subject_level_fixture :: string(`{"version":1,"level":0,"space_station":{"station_id":"test_station","distance":0,"resources":[],"subjects":[]},"buildings":[
  {"id":"CU1","building_id":"control_unit","position":{"x":0,"y":0},"health":1,"repairing":false,"enable_at_start":true,"stored":[],"residents_amount":null},
  {"id":"WP1","building_id":"test_producer","position":{"x":2,"y":0},"health":1,"repairing":false,"enable_at_start":false,"stored":[{"resource_id":"water","amount":0}],"residents_amount":2}
],"subjects":[
  {"id":"H1","subject_id":"human","residence":"WP1","occupation":"WP1","roles":["worker","supervisor"],"speed":1},
  {"id":"H2","subject_id":"human","residence":"WP1","occupation":null,"roles":["repairer"],"speed":0.75}
]}`)

@(test)
subject_types_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    subjects, error := decode_subjects(transmute([]byte)subject_fixture,resources,texts,allocator)
    testing.expect(t,error == "" && len(subjects) == 1,error)
    if error != "" { return }
    testing.expect(t,subjects[0].id == "human" && subjects[0].needs[0].amount_per_hour == 0.5 && subjects[0].needs[0].shortage_alert_time == 12 && subjects[0].needs[0].shortage_max_time == 6)
    testing.expect(t,subjects[0].color == {1,2,3})
    testing.expect(t,subjects[0].rest_time == 8 && subjects[0].work_time == 10)
    testing.expect(t,len(subjects[0].roles) == 2 && subjects[0].roles[0].role_id == .worker && subjects[0].roles[1].role_id == .repairer)
    for roles in ([?]string{"null","[]"}) {
        without, _ := strings.replace_all(subject_fixture,`[{"role_id":"worker","sprite":""},{"role_id":"repairer","sprite":""}]`,roles,allocator)
        no_roles, no_roles_error := decode_subjects(transmute([]byte)without,resources,texts,allocator)
        testing.expect(t,no_roles_error == "" && len(no_roles[0].roles) == 0,no_roles_error)
    }
    testing.expect(t,len(subjects[0].produces) == 1 && subjects[0].produces[0].resource_id == "water" && subjects[0].produces[0].units_per_hour == 2)
    empty := "[]"
    none, empty_error := decode_subjects(transmute([]byte)empty,resources,texts,allocator)
    testing.expect(t,empty_error == "" && len(none) == 0)
    changes := [?][2]string{
        {"\"id\":\"human\"","\"id\":\"\""},
        {"resource_water_name","missing_translation"},
        {"\"name_key\"","\"name\""},
        {"\"b\":3","\"b\":256"},
        {"\"rest_time\":8","\"rest_time\":-1"},
        {"\"work_time\":10","\"work_time\":-1"},
        {"\"rest_time\":8,",""},
        {`,"roles":[{"role_id":"worker","sprite":""},{"role_id":"repairer","sprite":""}]`, ""},
        {`"role_id":"repairer"`, `"role_id":"worker"`},
        {`"role_id":"worker"`, `"role_id":"farmer"`},
        {`{"role_id":"worker","sprite":""}`, `"worker"`},
        {"\"units_per_hour\":2","\"units_per_hour\":0"},
        {"\"units_per_hour\":2","\"time_per_unit\":0.5"}, // Legacy field is rejected.
        // Subject products no longer accept capacity or stored.
        {"\"units_per_hour\":2}","\"units_per_hour\":2,\"capacity\":5}"},
        {"\"units_per_hour\":2}","\"units_per_hour\":2,\"stored\":1}"},
        {",\"produces\":[{\"resource_id\":\"water\",\"units_per_hour\":2}]",""},
        {"\"color\":{\"r\":1,\"g\":2,\"b\":3},",""},
        {"\"amount_per_hour\":0.5","\"amount_per_hour\":0"},
        {"\"amount_per_hour\":0.5","\"amount_per_hour\":-1"},
        {"\"amount_per_hour\":0.5","\"amount_per_unit\":0.5"},
        {"\"resource_id\":\"water\"","\"resource_id\":\"Water\""},
        {",\"needs\":[{\"resource_id\":\"water\",\"amount_per_hour\":0.5,\"shortage_alert_time\":12,\"shortage_max_time\":6}]",""},
        {"\"shortage_max_time\":6","\"shortage_max_time\":-1"},
        {"\"shortage_max_time\":6","\"shortage_max_time\":null"},
        {",\"shortage_max_time\":6",""},
        {"\"shortage_max_time\":6","\"starving_max_time\":6"}, // Legacy name is rejected.
        {"\"shortage_max_time\":6","\"shortage_max_time\":6,\"starving_max_time\":6"},
        {"\"shortage_alert_time\":12","\"shortage_alert_time\":-1"},
        {"\"shortage_alert_time\":12","\"shortage_alert_time\":null"},
        {",\"shortage_alert_time\":12",""},
        {"\"shortage_alert_time\":12","\"alert_time\":12"}, // Legacy name is rejected.
        {"\"shortage_alert_time\":12","\"shortage_alert_time\":12,\"alert_time\":12"},
        {"\"shortage_alert_time\":12","\"shortage_alert_time\":\"12\""},
        {"\"shortage_alert_time\":12","\"shortage_alert_time\":1e100"},
        // The former field name is rejected.
        {"\"shortage_alert_time\":12","\"autonomy_time\":12"},
    }
    for change in changes {
        modified, _ := strings.replace_all(subject_fixture,change[0],change[1],allocator)
        _, invalid := decode_subjects(transmute([]byte)modified,resources,texts,allocator)
        testing.expect(t,invalid != "",change[1])
    }
    duplicate := "["+subject_fixture[1:len(subject_fixture)-1]+","+subject_fixture[1:len(subject_fixture)-1]+"]"
    _, duplicate_error := decode_subjects(transmute([]byte)duplicate,resources,texts,allocator)
    testing.expect(t,strings.contains(duplicate_error,"duplicate ID"))
}

@(test)
level_subject_references :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
    catalog, _ := decode_catalog(transmute([]byte)building_fixture,resources,texts,allocator)
    catalog.subjects, _ = decode_subjects(transmute([]byte)subject_fixture,resources,texts,allocator)
    // test_producer (buildings[1]) hosts "human" residents in the building fixture.
    testing.expect(t,validate_residents(catalog,allocator) == "")
    catalog.buildings[1].residents.type = "robot"
    testing.expect(t,strings.contains(validate_residents(catalog,allocator),"subjects.json"))
    catalog.buildings[1].residents.type = "human"
    // The level fixture uses every role.
    catalog.subjects[0].roles = []logic.Subject_Role_Definition{{role_id=.worker},{role_id=.supervisor},{role_id=.repairer}}
    stations := [?]logic.Space_Station{{id="test_station"}}
    catalog.space_stations = stations[:]
    level, error := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
    testing.expect(t,error == "" && len(level.subjects) == 2,error)
    if error != "" { return }
    worker, repairer := level.subjects[0], level.subjects[1]
    testing.expect(t,len(worker.roles) == 2 && worker.roles[0] == .worker && worker.roles[1] == .supervisor)
    testing.expect(t,worker.residence == "WP1" && worker.occupation == "WP1" && worker.speed == 1)
    testing.expect(t,len(repairer.roles) == 1 && repairer.roles[0] == .repairer && repairer.occupation == "" && repairer.speed == 0.75)
    changes := [?][2]string{
        {"\"subject_id\":\"human\"","\"subject_id\":\"robot\""},
        {"\"id\":\"H2\"","\"id\":\"H1\""},
        {"\"residents_amount\":2","\"residents_amount\":1.5"},
        {"\"residence\":\"WP1\"","\"residence\":\"XX\""},
        {"\"residence\":\"WP1\"","\"residence\":\"test_producer\""},
        {"\"residence\":\"WP1\"","\"residence\":null"},
        // The Control Unit type hosts no subjects.
        {"\"residence\":\"WP1\"","\"residence\":\"CU1\""},
        {"\"occupation\":\"WP1\"","\"occupation\":\"XX\""},
        {"\"occupation\":\"WP1\"","\"occupation\":\"\""},
        {",\"occupation\":null",""},
        {"[\"worker\",\"supervisor\"]","[]"},
        {"[\"worker\",\"supervisor\"]","[\"worker\",\"worker\"]"},
        {"[\"worker\",\"supervisor\"]","[\"Worker\",\"supervisor\"]"},
        {"[\"worker\",\"supervisor\"]","[\"farmer\"]"},
        {"[\"worker\",\"supervisor\"]","[\"worker\",1]"},
        {"[\"worker\",\"supervisor\"]","\"worker\""},
        {"[\"worker\",\"supervisor\"]","null"},
        {"\"roles\":[\"repairer\"]","\"role\":\"repairer\""},
        {"\"speed\":1}","\"speed\":0}"},
        {"\"speed\":0.75","\"speed\":-1"},
        {"\"speed\":1}","\"speed\":null}"},
        {"\"subjects\":[","\"people\":["},
    }
    for change in changes {
        modified, _ := strings.replace_all(subject_level_fixture,change[0],change[1],allocator)
        _, invalid := decode_level(transmute([]byte)modified,catalog,allocator)
        testing.expect(t,invalid != "",change[1])
    }
    // Two resident subjects of WP1: residents.capacity is a float. residents_amount 0 keeps
    // the instance check out of the way, so the subject check reports the overflow.
    no_amount, _ := strings.replace_all(subject_level_fixture,"\"residents_amount\":2","\"residents_amount\":0",allocator)
    catalog.buildings[1].residents.capacity = 1.5
    _, crowded := decode_level(transmute([]byte)no_amount,catalog,allocator)
    testing.expect(t,strings.contains(crowded,"subjects[1]: residence"),crowded)
    catalog.buildings[1].residents.capacity = 2
    _, full := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
    testing.expect(t,full == "",full)
    // Instance roles must belong to the subject type's roles; a type with null roles takes none.
    catalog.subjects[0].roles = []logic.Subject_Role_Definition{{role_id=.worker},{role_id=.repairer}}
    _, not_allowed := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
    testing.expect(t,strings.contains(not_allowed,"subjects[0]: role supervisor"),not_allowed)
    catalog.subjects[0].roles = nil
    _, typeless := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
    testing.expect(t,strings.contains(typeless,"is not in the roles"),typeless)
    without_roles, _ := strings.replace_all(subject_level_fixture,"[\"worker\",\"supervisor\"]","[]",allocator)
    without_roles, _ = strings.replace_all(without_roles,"[\"repairer\"]","[]",allocator)
    _, none := decode_level(transmute([]byte)without_roles,catalog,allocator)
    testing.expect(t,none == "",none)
    catalog.subjects[0].roles = []logic.Subject_Role_Definition{{role_id=.repairer}}
    _, missing := decode_level(transmute([]byte)without_roles,catalog,allocator)
    testing.expect(t,strings.contains(missing,"at least one role"),missing)
    // Without residents the instance needs a null residents_amount; the subject is then not hosted.
    catalog.buildings[1].residents = {}
    null_amount, _ := strings.replace_all(subject_level_fixture,"\"residents_amount\":2","\"residents_amount\":null",allocator)
    _, not_hosted := decode_level(transmute([]byte)null_amount,catalog,allocator)
    testing.expect(t,strings.contains(not_hosted,"residents.type"),not_hosted)
    catalog.buildings[1].residents = {type="human", capacity=4}
    catalog.subjects = nil
    _, missing_type := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
    testing.expect(t,strings.contains(missing_type,"subject_id"))
}
