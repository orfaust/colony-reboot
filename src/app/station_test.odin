package main

import "core:testing"
import "core:mem"
import "../config"
import "../logic"

@(test)
station_formats_stock_and_empty_sections :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    line := station_stock_text("{name}: {units}/{capacity} ({rate}/h)", "Water", 2, 10, -0.5, allocator)
    testing.expect(t, line == "Water: 2/10 (-0.5/h)")
    whole := station_stock_text("{name}: {units}/{capacity} ({rate}/h)", "Humans", 2, 10.5, 0.5, allocator, true)
    testing.expect(t, whole == "Humans: 2/10 (+0.5/h)")
    texts := make(map[string]string, allocator)
    texts["station_resources"] = "Resources"
    texts["station_subjects"] = "Subjects"
    texts["station_ships"] = "Ships"
    texts["station_empty"] = "None"
    catalog: config.Catalog
    stations := [?]logic.Space_Station{{id="first", name="Space Station"}, {id="second", name="Other Station"}}
    catalog.space_stations = stations[:1]
    instance := logic.Station_Instance{station_id="first"}
    lines := station_lines(catalog, instance, texts, allocator)
    testing.expect(t, len(lines) == 7)
    testing.expect(t, lines[0] == "Space Station")
    testing.expect(t, lines[2] == "None" && lines[4] == "None" && lines[6] == "None")
    catalog.space_stations = stations[:]
    instance.station_id = "second"
    selected := station_lines(catalog, instance, texts, allocator)
    testing.expect(t, len(selected) == 7 && selected[0] == "Other Station")
    definitions := [?]logic.Station_Resource{{resource_id="water", capacity=20}}
    stations[1].resources = definitions[:]
    resources := [?]logic.Resource{{id="water", name_key="water_name"}}
    catalog.resources = resources[:]
    stocks := [?]logic.Station_Resource_Stock{{resource_id="water", units=5, units_per_hour=-2}}
    instance.resources = stocks[:]
    texts["water_name"] = "Water"
    texts["station_stock_format"] = "{name}: {units}/{capacity} ({rate}/h)"
    stocked := station_lines(catalog, instance, texts, allocator)
    testing.expect(t, stocked[2] == "Water: 5/20 (-2/h)")
    testing.expect(t, definitions[0].capacity == 20 && stocks[0].units == 5)
}
