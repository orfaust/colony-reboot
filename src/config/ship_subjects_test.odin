package config

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"
import "../logic"

@(test)
ship_subject_capacities :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := make(map[string]string,allocator)
    texts["ship_test_name"] = "Test transport"
    subjects := [?]logic.Subject_Type{{id="human"},{id="robot"}}
    source :: string(`[{"id":"transport","code":"TR","color":{"r":200,"g":200,"b":200},"name_key":"ship_test_name","type":"transport","width":1,"height":1,"max_speed":0,"max_speed_hours":0,"units_per_hour":0,"subjects":[
        {"subject_id":"human","capacity":100},{"subject_id":"robot","capacity":50}
    ]}]`)
    ships, error := decode_ships(transmute([]byte)source,subjects[:],texts,allocator)
    testing.expect(t,error == "",error)
    if error != "" { return }
    testing.expect(t,len(ships[0].subjects) == 2)
    testing.expect(t,ships[0].subjects[0].subject_id == "human" && ships[0].subjects[0].capacity == 100)
    testing.expect(t,ships[0].subjects[1].subject_id == "robot" && ships[0].subjects[1].capacity == 50)
    changes := [?][2]string{
        {"\"subject_id\":\"human\"","\"resource_id\":\"human\""},
        {"\"subject_id\":\"human\"","\"subject_id\":\"humans\""},
        {"\"subject_id\":\"robot\"","\"subject_id\":\"human\""},
        {"\"capacity\":100","\"capacity\":-1"},
        {"\"capacity\":100","\"capacity\":null"},
        {"\"capacity\":100","\"capacity\":1e100"},
        {"\"capacity\":100","\"units\":100"},
        {"\"subjects\"","\"passengers\""},
    }
    for change in changes {
        invalid, _ := strings.replace_all(source,change[0],change[1],allocator)
        _, invalid_error := decode_ships(transmute([]byte)invalid,subjects[:],texts,allocator)
        testing.expect(t,invalid_error != "",change[1])
    }
    empty :: string(`[{"id":"transport","code":"TR","color":{"r":200,"g":200,"b":200},"name_key":"ship_test_name","type":"transport","width":1,"height":1,"max_speed":0,"max_speed_hours":0,"units_per_hour":0,"subjects":[]}]`)
    ships, error = decode_ships(transmute([]byte)empty,nil,texts,allocator)
    testing.expect(t,error == "" && len(ships[0].subjects) == 0,error)
    null_subjects, _ := strings.replace_all(empty,"\"subjects\":[]","\"subjects\":null",allocator)
    _, error = decode_ships(transmute([]byte)null_subjects,subjects[:],texts,allocator)
    testing.expect(t,error != "")
    missing_subjects, _ := strings.replace_all(empty,",\"subjects\":[]","",allocator)
    _, error = decode_ships(transmute([]byte)missing_subjects,subjects[:],texts,allocator)
    testing.expect(t,error != "")
    zero_capacity, _ := strings.replace_all(source,"\"capacity\":100","\"capacity\":0",allocator)
    _, error = decode_ships(transmute([]byte)zero_capacity,subjects[:],texts,allocator)
    testing.expect(t,error == "",error)
    // `emergency` is a validated ship type; unknown categories are rejected with a field path.
    emergency, _ := strings.replace_all(source,"\"type\":\"transport\"","\"type\":\"emergency\"",allocator)
    emergency_ships, emergency_error := decode_ships(transmute([]byte)emergency,subjects[:],texts,allocator)
    testing.expect(t,emergency_error == "" && emergency_ships[0].type == "emergency",emergency_error)
    for kind in ([?]string{`"unknown"`, `null`, `""`, `42`}) {
        invalid, _ := strings.replace_all(source,"\"type\":\"transport\"",fmt.aprintf("\"type\":%s",kind,allocator=allocator),allocator)
        _, invalid_error := decode_ships(transmute([]byte)invalid,subjects[:],texts,allocator)
        testing.expect(t,invalid_error != "",kind)
        testing.expect(t,strings.contains(invalid_error,".type"),invalid_error)
    }
}
