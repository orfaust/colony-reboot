package config

import "core:fmt"
import "core:mem"
import "core:math"
import "../logic"

find_station :: proc(catalog: Catalog, id: string) -> (logic.Space_Station, bool) {
    for station in catalog.space_stations { if station.id == id { return station, true } }
    return {}, false
}

// Each template resource/subject requires exactly one level stock entry. No implicit
// zeroes or extra stock: editing template membership requires updating its levels.
validate_station_instance :: proc(instance: logic.Station_Instance, catalog: Catalog, allocator: mem.Allocator) -> string {
    if !logic.valid_station_stock(0, instance.distance, 0) { return "space_station.distance: must be finite and nonnegative (km)" }
    station, found := find_station(catalog, instance.station_id)
    if !found { return fmt.aprintf("space_station.station_id: unknown ID %q; define it in assets/config/space_stations.json", instance.station_id, allocator=allocator) }
    for stock, i in instance.resources {
        capacity: f32
        exists := false
        for definition in station.resources {
            if definition.resource_id == stock.resource_id { capacity = definition.capacity; exists = true; break }
        }
        if !exists { return fmt.aprintf("space_station.resources[%d]: resource_id %q is not in station %q", i, stock.resource_id, station.id, allocator=allocator) }
        if !logic.valid_station_stock(stock.units, capacity, stock.units_per_hour) {
            return fmt.aprintf("space_station.resources[%d]: units must be in [0, capacity] (%v), with finite units_per_hour", i, capacity, allocator=allocator)
        }
        for previous in instance.resources[:i] {
            if previous.resource_id == stock.resource_id { return fmt.aprintf("space_station.resources[%d]: duplicate resource_id %q", i, stock.resource_id, allocator=allocator) }
        }
    }
    if len(instance.resources) != len(station.resources) { return "space_station.resources: provide exactly one stock entry per station resource" }
    for stock, i in instance.subjects {
        capacity: f32
        exists := false
        for definition in station.subjects {
            if definition.subject_id == stock.subject_id { capacity = definition.capacity; exists = true; break }
        }
        if !exists { return fmt.aprintf("space_station.subjects[%d]: subject_id %q is not in station %q", i, stock.subject_id, station.id, allocator=allocator) }
        if !logic.valid_station_stock(stock.units, capacity, stock.units_per_hour) {
            return fmt.aprintf("space_station.subjects[%d]: units must be in [0, capacity] (%v), with finite units_per_hour", i, capacity, allocator=allocator)
        }
        if f64(stock.units) != math.floor(f64(stock.units)) {
            return fmt.aprintf("space_station.subjects[%d].units: must be a whole number of subjects", i, allocator=allocator)
        }
        for previous in instance.subjects[:i] {
            if previous.subject_id == stock.subject_id { return fmt.aprintf("space_station.subjects[%d]: duplicate subject_id %q", i, stock.subject_id, allocator=allocator) }
        }
    }
    if len(instance.subjects) != len(station.subjects) { return "space_station.subjects: provide exactly one stock entry per station subject" }
    return ""
}
