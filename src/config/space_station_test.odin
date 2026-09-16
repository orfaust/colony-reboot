package config

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"
import "../localization"
import "../logic"

ships_fixture :: string(`[{"id":"shuttle","code":"SH","color":{"r":80,"g":170,"b":240},"name_key":"ship_shuttle_name","type":"transport","width":2.5,"height":1.25,"max_speed":1200.5,"max_speed_hours":1.5,"units_per_hour":0.25,"subjects":[]}]`)
station_fixture :: string(`{
"id":"station_test",
"code":"ST",
"name_key":"station_test_name",
"resources":[{"resource_id":"water","capacity":20}],
"subjects":[{"subject_id":"human","capacity":8}],
"ships":[{"ship_id":"shuttle","units":2}]
}`)

@(test)
ships_and_station_decode :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := make(map[string]string,allocator)
    texts["ship_shuttle_name"] = "Colony Shuttle"
    texts["station_test_name"] = "Orbital Station"
    ships, ship_error := decode_ships(transmute([]byte)ships_fixture,nil,texts,allocator)
    testing.expect(t,ship_error == "",ship_error)
    if ship_error != "" { return }
    testing.expect(t,len(ships) == 1 && ships[0].id == "shuttle")
    testing.expect(t,ships[0].name == "Colony Shuttle" && ships[0].type == "transport")
    resources := [?]logic.Resource{{id="water"}}
    subjects := [?]logic.Subject_Type{{id="human"}}
    catalog := Catalog{resources=resources[:],subjects=subjects[:],ships=ships}
    station, error := decode_space_station(transmute([]byte)station_fixture,catalog,texts,allocator)
    testing.expect(t,error == "",error)
    if error != "" { return }
    testing.expect(t,station.name == "Orbital Station" && station.code == "ST")
    testing.expect(t,ships[0].max_speed == 1200.5 && ships[0].max_speed_hours == 1.5 && ships[0].units_per_hour == 0.25)
    testing.expect(t,ships[0].code == "SH" && ships[0].color.r == 80 && ships[0].color.g == 170 && ships[0].color.b == 240)
    testing.expect(t,len(station.resources) == 1 && station.resources[0].capacity == 20)
    testing.expect(t,len(station.subjects) == 1 && station.subjects[0].capacity == 8)
    testing.expect(t,len(station.ships) == 1 && station.ships[0].ship_id == "shuttle" && station.ships[0].units == 2)
}

@(test)
invalid_ships :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := make(map[string]string,allocator)
    texts["ship_shuttle_name"] = "Shuttle"
    changes := [?][2]string{
        {"\"max_speed\":1200.5,",""},
        {"\"max_speed_hours\":1.5,",""}, {"\"units_per_hour\":0.25,",""},
        {"\"max_speed_hours\":1.5","\"max_speed_hours\":-1"},
        {"\"max_speed_hours\":1.5","\"max_speed_hours\":null"},
        {"\"max_speed_hours\":1.5","\"max_speed_hours\":1e100"},
        {"\"units_per_hour\":0.25","\"units_per_hour\":-1"},
        {"\"units_per_hour\":0.25","\"units_per_hour\":null"},
        {"\"units_per_hour\":0.25","\"units_per_hour\":1e100"},
        {"1200.5","-1"}, {"1200.5","null"}, {"1200.5","\"fast\""}, {"1200.5","1e100"},
        {"\"id\":\"shuttle\"","\"id\":\"\""},
        {"\"code\":\"SH\",",""},
        {"\"code\":\"SH\"","\"code\":\"\""},
        {"\"r\":80","\"r\":256"},
        {"\"g\":170","\"g\":-1"},
        {"\"b\":240","\"b\":1.5"},
        {"\"color\":{\"r\":80,\"g\":170,\"b\":240},",""},
        {"\"type\":\"transport\"","\"type\":null"},
        {"\"type\":\"transport\"","\"type\":\"   \""},
        {"\"type\":\"transport\"","\"unknown\":\"transport\""},
        {"ship_shuttle_name","missing_translation"},
        {"\"name_key\":\"ship_shuttle_name\",",""},
    }
    for change in changes {
        data, _ := strings.replace_all(ships_fixture,change[0],change[1],allocator)
        _, error := decode_ships(transmute([]byte)data,nil,texts,allocator)
        testing.expect(t,error != "",change[1])
    }
    duplicate := "["+ships_fixture[1:len(ships_fixture)-1]+","+ships_fixture[1:len(ships_fixture)-1]+"]"
    _, duplicate_error := decode_ships(transmute([]byte)duplicate,nil,texts,allocator)
    testing.expect(t,strings.contains(duplicate_error,"duplicate ID"),duplicate_error)
    invalid_sources := [?]string{"{}","null","[",ships_fixture+" {}"}
    for data in invalid_sources {
        _, error := decode_ships(transmute([]byte)data,nil,texts,allocator)
        testing.expect(t,error != "",data)
    }
    empty := "[]"
    ships, error := decode_ships(transmute([]byte)empty,nil,texts,allocator)
    testing.expect(t,error == "" && len(ships) == 0)
}

@(test)
invalid_station_entries :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := make(map[string]string,allocator)
    texts["station_test_name"] = "Station"
    resources := [?]logic.Resource{{id="water"}}
    subjects := [?]logic.Subject_Type{{id="human"}}
    ships := [?]logic.Ship{{id="shuttle",name="Shuttle",type="transport"}}
    catalog := Catalog{resources=resources[:],subjects=subjects[:],ships=ships[:]}
    changes := [?][2]string{
        {"\"code\":\"ST\"","\"code\":\"ST\",\"distance\":0"},
        {"station_test_name","missing_name"},
        {"\"code\":\"ST\",",""},
        {"\"code\":\"ST\"","\"code\":\" \""},
        {"\"resource_id\":\"water\"","\"resource_id\":\"Water\""},
        {"\"subject_id\":\"human\"","\"subject_id\":\"unknown\""},
        {"\"ship_id\":\"shuttle\"","\"ship_id\":\"unknown\""},
        {"\"capacity\":20","\"capacity\":-1"}, {"\"capacity\":20","\"capacity\":1e100"},
        {"\"capacity\":8","\"capacity\":-1"},
        {"\"capacity\":20","\"capacity\":20,\"units\":0"},
        {"\"capacity\":8","\"capacity\":8,\"units_per_hour\":0"},
        {"\"units\":2}","\"units\":-1}"}, {"\"units\":2}","\"units\":1.5}"},
        {"\"ships\":[{\"ship_id\":\"shuttle\",\"units\":2}]","\"ships\":null"},
        {"\"resources\"","\"unknown\""},
    }
    for change in changes {
        data, _ := strings.replace_all(station_fixture,change[0],change[1],allocator)
        _, error := decode_space_station(transmute([]byte)data,catalog,texts,allocator)
        testing.expect(t,error != "",change[1])
    }
    rows := [?]string{
        `{"resource_id":"water","capacity":20}`,
        `{"subject_id":"human","capacity":8}`,
        `{"ship_id":"shuttle","units":2}`,
    }
    for row in rows {
        repeated := fmt.aprintf("%s,%s",row,row,allocator=allocator)
        duplicate, _ := strings.replace_all(station_fixture,row,repeated,allocator)
        _, error := decode_space_station(transmute([]byte)duplicate,catalog,texts,allocator)
        testing.expect(t,strings.contains(error,"duplicate"),error)
    }
}

@(test)
shipped_station_loads :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    text_data :: #load("../../assets/localization/en.json")
    text, text_ok := localization.decode(transmute([]byte)text_data,allocator)
    testing.expect(t,text_ok)
    // Exercises both new file paths through the production startup adapter.
    catalog, _, ok := load(text.entries,allocator)
    testing.expect(t,ok)
    testing.expect(t,len(catalog.space_stations) > 0)
    if len(catalog.space_stations) > 0 { testing.expect(t,catalog.space_stations[0].name != "") }
}
