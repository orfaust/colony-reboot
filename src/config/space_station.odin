package config

import "core:fmt"
import "core:mem"
import "core:os"
import "../logic"
import c "../contracts"

// Wire names are localization keys; public logic structures carry the resolved name.
@(private)
Ship_Data :: struct {
    id, code, name_key, type: string,
    color: c.RGB,
    sprite: string `config:"optional"`,
    width, height: f32,
    max_speed, max_speed_hours, units_per_hour: f32,
    subjects: []logic.Ship_Subject,
}
@(private)
Station_Data :: struct {
    id, code, name_key: string,
    resources: []logic.Station_Resource,
    subjects: []logic.Station_Subject,
    ships: []logic.Station_Ship,
}

// Like other decoders, strings/arrays (including partial results on failure) belong
// to allocator. Resolved names borrow texts, which must outlive the returned data.
decode_ships :: proc(data: []byte, subjects: []logic.Subject_Type, texts: map[string]string, allocator: mem.Allocator) -> (ships: []logic.Ship, error: string) {
    definitions: []Ship_Data
    error = parse_typed(data, &definitions, allocator)
    if error != "" { return }
    ships = make([]logic.Ship, len(definitions), allocator)
    for definition, i in definitions {
        for previous in definitions[:i] {
            if previous.id == definition.id {
                return nil, fmt.aprintf("ships[%d]: duplicate ID %q", i, definition.id, allocator=allocator)
            }
        }
        if err := text_error(definition.name_key, texts, allocator); err != "" { return nil, err }
        if definition.width <= 0 || definition.height <= 0 {
            return nil, fmt.aprintf("ships[%d]: width and height must be positive pixel dimensions", i, allocator=allocator)
        }
        if definition.sprite != "" && !valid_sprite_path(definition.sprite) {
            return nil, fmt.aprintf("ships[%d].sprite: expected a normalized assets/.../*.png path", i, allocator=allocator)
        }
        if !logic.valid_ship_type(definition.type) {
            return nil, fmt.aprintf("ships[%d].type: expected one of: %s, %s", i, logic.Ship_Type_Transport, logic.Ship_Type_Emergency, allocator=allocator)
        }
        if definition.max_speed < 0 {
            return nil, fmt.aprintf("ships[%d]: max_speed must be nonnegative (km/h)", i, allocator=allocator)
        }
        if definition.max_speed_hours < 0 {
            return nil, fmt.aprintf("ships[%d]: max_speed_hours must be nonnegative (hours)", i, allocator=allocator)
        }
        if definition.units_per_hour < 0 {
            return nil, fmt.aprintf("ships[%d]: units_per_hour must be nonnegative (cargo units per simulated hour; zero disables dispatch)", i, allocator=allocator)
        }
        for passenger, j in definition.subjects {
            found := false
            for subject in subjects { if subject.id == passenger.subject_id { found = true; break } }
            if !found {
                return nil, fmt.aprintf("ships[%d].subjects[%d]: unknown subject_id %q; define it in subjects.json", i, j, passenger.subject_id, allocator=allocator)
            }
            if passenger.capacity < 0 {
                return nil, fmt.aprintf("ships[%d].subjects[%d]: capacity must be nonnegative", i, j, allocator=allocator)
            }
            for previous in definition.subjects[:j] {
                if previous.subject_id == passenger.subject_id {
                    return nil, fmt.aprintf("ships[%d].subjects[%d]: duplicate subject_id %q", i, j, passenger.subject_id, allocator=allocator)
                }
            }
        }
        ships[i] = {id=definition.id, code=definition.code, color=definition.color, name=texts[definition.name_key], type=definition.type, sprite=definition.sprite, width=definition.width, height=definition.height, max_speed=definition.max_speed, max_speed_hours=definition.max_speed_hours, units_per_hour=definition.units_per_hour, subjects=definition.subjects}
    }
    return
}

decode_space_station :: proc(data: []byte, catalog: Catalog, texts: map[string]string, allocator: mem.Allocator) -> (station: logic.Space_Station, error: string) {
    definition: Station_Data
    error = parse_typed(data, &definition, allocator)
    if error != "" { return }
    return resolve_station(definition, catalog, texts, allocator)
}

// Resolves already shape-checked definitions without copying borrowed strings.
@(private)
resolve_station :: proc(definition: Station_Data, catalog: Catalog, texts: map[string]string, allocator: mem.Allocator) -> (logic.Space_Station, string) {
    if err := text_error(definition.name_key, texts, allocator); err != "" { return {}, err }
    for stock, i in definition.resources {
        if !resource_exists(catalog.resources, stock.resource_id) {
            return {}, fmt.aprintf("resources[%d]: unknown resource_id %q; define it in resources.json", i, stock.resource_id, allocator=allocator)
        }
        if !logic.valid_station_stock(0, stock.capacity, 0) {
            return {}, fmt.aprintf("resources[%d]: capacity must be finite and nonnegative", i, allocator=allocator)
        }
        for previous in definition.resources[:i] {
            if previous.resource_id == stock.resource_id {
                return {}, fmt.aprintf("resources[%d]: duplicate resource_id %q", i, stock.resource_id, allocator=allocator)
            }
        }
    }
    for stock, i in definition.subjects {
        found := false
        for subject in catalog.subjects { if subject.id == stock.subject_id { found = true; break } }
        if !found {
            return {}, fmt.aprintf("subjects[%d]: unknown subject_id %q; define it in subjects.json", i, stock.subject_id, allocator=allocator)
        }
        if !logic.valid_station_stock(0, stock.capacity, 0) {
            return {}, fmt.aprintf("subjects[%d]: capacity must be finite and nonnegative", i, allocator=allocator)
        }
        for previous in definition.subjects[:i] {
            if previous.subject_id == stock.subject_id {
                return {}, fmt.aprintf("subjects[%d]: duplicate subject_id %q", i, stock.subject_id, allocator=allocator)
            }
        }
    }
    for stock, i in definition.ships {
        found := false
        for ship in catalog.ships { if ship.id == stock.ship_id { found = true; break } }
        if !found {
            return {}, fmt.aprintf("ships[%d]: unknown ship_id %q; define it in ships.json", i, stock.ship_id, allocator=allocator)
        }
        if stock.units < 0 { return {}, fmt.aprintf("ships[%d]: units must be a nonnegative integer", i, allocator=allocator) }
        for previous in definition.ships[:i] {
            if previous.ship_id == stock.ship_id {
                return {}, fmt.aprintf("ships[%d]: duplicate ship_id %q", i, stock.ship_id, allocator=allocator)
            }
        }
    }
    return {
        id=definition.id, code=definition.code, name=texts[definition.name_key], resources=definition.resources,
        subjects=definition.subjects, ships=definition.ships,
    }, ""
}

// Ordered immutable templates belong to allocator; names borrow texts. Empty lists
// are valid. No partial catalog is published if any definition fails validation.
decode_space_stations :: proc(data: []byte, catalog: Catalog, texts: map[string]string, allocator: mem.Allocator) -> (stations: []logic.Space_Station, error: string) {
    definitions: []Station_Data
    error = parse_typed(data, &definitions, allocator)
    if error != "" { return }
    stations = make([]logic.Space_Station, len(definitions), allocator)
    for definition, i in definitions {
        for previous in definitions[:i] {
            if previous.id == definition.id {
                return nil, fmt.aprintf("space_stations[%d]: duplicate ID %q", i, definition.id, allocator=allocator)
            }
        }
        station, err := resolve_station(definition, catalog, texts, allocator)
        if err != "" { return nil, fmt.aprintf("space_stations[%d]: %s", i, err, allocator=allocator) }
        stations[i] = station
    }
    return
}

@(private)
load_space_stations :: proc(catalog: ^Catalog, texts: map[string]string, allocator: mem.Allocator, profile: Profile) -> bool {
    ships_path := profile_path(profile, "ships.json", allocator)
    data, ok := os.read_entire_file(ships_path)
    if !ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", ships_path); return false }
    defer delete(data)
    ships, error := decode_ships(data, catalog.subjects, texts, allocator)
    if error != "" { fmt.eprintf("Invalid %s: %s\n", ships_path, error); return false }
    catalog.ships = ships
    station_path := profile_path(profile, "space_stations.json", allocator)
    station_data, station_ok := os.read_entire_file(station_path)
    if !station_ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", station_path); return false }
    defer delete(station_data)
    stations, station_error := decode_space_stations(station_data, catalog^, texts, allocator)
    if station_error != "" { fmt.eprintf("Invalid %s: %s\n", station_path, station_error); return false }
    catalog.space_stations = stations
    return true
}
