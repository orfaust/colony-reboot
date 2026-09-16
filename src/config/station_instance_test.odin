package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../logic"

@(test)
level_station_stocks :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    resources := [?]logic.Station_Resource{{resource_id="water", capacity=20}}
    subjects := [?]logic.Station_Subject{{subject_id="human", capacity=8}}
    stations := [?]logic.Space_Station{{id="station", resources=resources[:], subjects=subjects[:]}}
    catalog := Catalog{space_stations=stations[:]}
    fixture := `{"version":1,"level":0,"buildings":[],"subjects":[],"space_station":{"station_id":"station","distance":35000.25,"resources":[{"resource_id":"water","units":10,"units_per_hour":2.5}],"subjects":[{"subject_id":"human","units":3,"units_per_hour":-0.5}]}}`
    level, error := decode_level(transmute([]byte)fixture, catalog, allocator)
    testing.expect(t, error == "", error)
    if error != "" { return }
    testing.expect(t, level.space_station.resources[0].units == 10)
    testing.expect(t, level.space_station.subjects[0].units_per_hour == -0.5)
    testing.expect(t, level.space_station.distance == 35000.25)
    changes := [?][2]string{
        {`"distance":35000.25,`, ``},
        {`35000.25`, `-1`}, {`35000.25`, `null`}, {`35000.25`, `"far"`}, {`35000.25`, `1e100`},
        {`"station_id":"station"`, `"station_id":"missing"`},
        {`"station_id":"station"`, `"station_id":""`},
        {`"units":10`, `"units":21`}, {`"units":10`, `"units":-1`},
        {`"units":3`, `"units":3.5`},
        {`"units":3`, `"units":9`}, {`"units":3`, `"units":-1`},
        {`"units":3`, `"units":null`}, {`"units":3`, `"units":3,"capacity":8`},
        {`"units_per_hour":2.5`, `"units_per_hour":1e100`},
        {`"units_per_hour":-0.5`, `"units_per_hour":null`},
        {`"resource_id":"water"`, `"resource_id":"other"`},
        {`"subject_id":"human"`, `"subject_id":"other"`},
        {`[{"resource_id":"water","units":10,"units_per_hour":2.5}]`, `[]`},
        {`[{"subject_id":"human","units":3,"units_per_hour":-0.5}]`, `[]`},
        {`"space_station"`, `"unknown"`},
    }
    for change in changes {
        data, _ := strings.replace_all(fixture, change[0], change[1], allocator)
        _, err := decode_level(transmute([]byte)data, catalog, allocator)
        testing.expect(t, err != "", change[1])
    }
    for row in ([?]string{`{"resource_id":"water","units":10,"units_per_hour":2.5}`, `{"subject_id":"human","units":3,"units_per_hour":-0.5}`}) {
        repeated := strings.concatenate({row, ",", row}, allocator)
        data, _ := strings.replace_all(fixture, row, repeated, allocator)
        _, err := decode_level(transmute([]byte)data, catalog, allocator)
        testing.expect(t, strings.contains(err, "duplicate"), err)
    }
    other, _ := strings.replace_all(fixture, `"units":10`, `"units":2`, allocator)
    second, second_error := decode_level(transmute([]byte)other, catalog, allocator)
    testing.expect(t, second_error == "", second_error)
    testing.expect(t, second.space_station.resources[0].units == 2 && level.space_station.resources[0].units == 10)
    testing.expect(t, catalog.space_stations[0].resources[0].capacity == 20)
    colocated, _ := strings.replace_all(fixture, `35000.25`, `0`, allocator)
    third, third_error := decode_level(transmute([]byte)colocated, catalog, allocator)
    testing.expect(t, third_error == "", third_error)
    testing.expect(t, third.space_station.distance == 0 && level.space_station.distance == 35000.25)
    subjects[0].capacity = 20000
    oversized, _ := strings.replace_all(fixture, `"units":3`, `"units":20000`, allocator)
    _, limit_error := decode_level(transmute([]byte)oversized,catalog,allocator)
    testing.expect(t,strings.contains(limit_error,"runtime limit"),limit_error)
}
