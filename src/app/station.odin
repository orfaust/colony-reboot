package main

import "../config"
import "../logic"
import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"

// Output belongs to the supplied allocator. Optional live ship counts override the template.
station_lines :: proc(catalog: config.Catalog, instance: logic.Station_Instance, texts: map[string]string, allocator: mem.Allocator, available: []logic.Station_Ship = nil) -> []string {
    lines := make([dynamic]string, allocator)
    station, found := config.find_station(catalog, instance.station_id)
    if !found { return lines[:] } // Invalid references are rejected before startup.
    {
        append(&lines, station.name, texts["station_resources"])
        if len(station.resources) == 0 { append(&lines, texts["station_empty"]) }
        for stock in instance.resources {
            capacity: f32
            for definition in station.resources { if definition.resource_id == stock.resource_id { capacity = definition.capacity; break } }
            for resource in catalog.resources {
                if resource.id == stock.resource_id {
                    append(&lines, station_stock_text(texts["station_stock_format"], texts[resource.name_key], stock.units, capacity, stock.units_per_hour, allocator))
                }
            }
        }
        append(&lines, texts["station_subjects"])
        if len(station.subjects) == 0 { append(&lines, texts["station_empty"]) }
        for stock in instance.subjects {
            capacity: f32
            for definition in station.subjects { if definition.subject_id == stock.subject_id { capacity = definition.capacity; break } }
            for subject in catalog.subjects {
                if subject.id == stock.subject_id {
                    append(&lines, station_stock_text(texts["station_stock_format"], texts[subject.name_key], stock.units, capacity, stock.units_per_hour, allocator, true))
                }
            }
        }
        append(&lines, texts["station_ships"])
        if len(station.ships) == 0 { append(&lines, texts["station_empty"]) }
        ships := station.ships
        if available != nil { ships = available }
        for stock in ships {
            for ship in catalog.ships {
                if ship.id == stock.ship_id {
                    line, _ := strings.replace_all(texts["station_ship_format"], "{name}", ship.name, allocator)
                    line, _ = strings.replace_all(line, "{units}", fmt.aprintf("%d", stock.units, allocator=allocator), allocator)
                    append(&lines, line)
                }
            }
        }
    }
    return lines[:]
}

station_stock_text :: proc(template, name: string, units, capacity, rate: f32, allocator: mem.Allocator, whole_subjects: bool = false) -> string {
    result := template
    values := [?]string{name, info_number(f64(units), allocator=allocator), info_number(f64(capacity), allocator=allocator), info_number(f64(rate), 3, allocator, signed=true)}
    if whole_subjects {
        values[1] = fmt.aprintf("%.0f", units, allocator=allocator)
        values[2] = fmt.aprintf("%.0f", math.floor(f64(capacity)), allocator=allocator)
    }
    for token, i in ([?]string{"{name}", "{units}", "{capacity}", "{rate}"}) {
        result, _ = strings.replace_all(result, token, values[i], allocator)
    }
    return result
}
