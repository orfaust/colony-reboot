package logic

import "core:math"
import c "../contracts"

// IDs and type are stable data identifiers. Names are resolved localization strings.
// Strings and slices borrow immutable startup storage unless a caller explicitly
// clones them into session-owned memory. Transport_State owns live transport data.
Ship :: struct {
    id, code: string,
    color: c.RGB,
    name: string,
    type: string,
    sprite: string, // Optional repository-relative PNG path; borrowed catalog metadata.
    width, height: f32, // Positive world-unit dimensions; presentation metadata.
    max_speed: f32, // Maximum speed in km per simulated hour; zero means stationary.
    max_speed_hours: f32, // Hours to accelerate from rest to max_speed; also used to brake.
    units_per_hour: f32, // Cargo throughput per simulated hour, shared by loading and unloading; zero cannot dispatch.
    subjects: []Ship_Subject,
}
// Transport capacity by subject type, not the current passenger manifest.
Ship_Subject :: struct {
    subject_id: string,
    capacity: f32,
}

Station_Resource :: struct {
    resource_id: string,
    capacity: f32, // Template capacity; quantities and rates belong to the level instance.
}
Station_Subject :: struct {
    subject_id: string,
    capacity: f32,
}
Station_Ship :: struct {
    ship_id: string,
    units: int, // Whole, nonnegative number of ships.
}
Space_Station :: struct {
    id, code, name: string,
    resources: []Station_Resource,
    subjects: []Station_Subject,
    ships: []Station_Ship,
}

// One instance per level. Strings and slices borrow immutable level startup storage.
// Transport_State clones subject stock before changing it; resource rates remain metadata.
Station_Instance :: struct {
    station_id: string,
    distance: f32, // Level-specific distance from the colony in km.
    resources: []Station_Resource_Stock,
    subjects: []Station_Subject_Stock,
}
Station_Resource_Stock :: struct {
    resource_id: string,
    units, units_per_hour: f32,
}
Station_Subject_Stock :: struct {
    subject_id: string,
    units, units_per_hour: f32, // Units must be whole; signed fractional rates accrue privately.
}

// Stock and capacity are finite and nonnegative; signed finite rates are allowed.
// Resource rates remain metadata. Subject integration additionally enforces whole counts.
valid_station_stock :: proc(units, capacity, units_per_hour: f32) -> bool {
    return !math.is_nan(units) && !math.is_inf(units) &&
        !math.is_nan(capacity) && !math.is_inf(capacity) &&
        !math.is_nan(units_per_hour) && !math.is_inf(units_per_hour) &&
        units >= 0 && capacity >= 0 && units <= capacity
}
