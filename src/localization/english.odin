package localization

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

Text :: struct {
    entries: map[string]string,
    window_title, menu_title: string,
    power_output_format, power_need_format, power_available_format: string,
    hud_clock_format: string, // Requires {hours} and {speed}.
    notice_insufficient_power, notice_generator_required, notice_control_unit_locked, notice_always_on_locked: string,
    notice_insufficient_health: string,
    play, load, settings, exit_game: string,
    building_control_unit_name, building_control_unit_description: string,
    load_unavailable, settings_unavailable: string,
}

// All returned strings belong to allocator, including partial results on failure.
// The caller must release its localization arena after the window and UI shut down.
decode :: proc(data: []byte, allocator: mem.Allocator) -> (text: Text, ok: bool) {
    err := json.unmarshal(data, &text, allocator=allocator)
    if err != nil { fmt.eprintf("Localization: cannot decode text fields: %v.\n", err); return {}, false }
    // Keep additional named strings available to data-driven building/resource keys.
    if err := json.unmarshal(data, &text.entries, allocator=allocator); err != nil {
        fmt.eprintf("Localization: expected an object of string keys and string values: %v.\n", err)
        return {}, false
    }
    for key, value in text.entries {
        if strings.trim_space(value) == "" || strings.contains(value, "\x00") {
            fmt.eprintf("Localization: key %q must be nonempty and contain no NUL characters.\n", key)
            return {}, false
        }
    }
    for key in ([?]string{"transport_loading", "transport_waiting_landing", "transport_landing", "transport_unloading", "transport_taking_off", "transport_braking", "transport_returning", "transport_return_unloading", "transport_cancelled", "transport_eta_unknown", "transport_travelling", "transport_arrived", "transport_cargo_format", "transport_trip_format", "transport_speed_format", "transport_eta_format"}) {
        if strings.trim_space(text.entries[key]) == "" {
            fmt.eprintf("Localization: missing required key %q.\n",key)
            return {}, false
        }
    }
    for pair in ([?][2]string{
        {"transport_cargo_format","{units}"},{"transport_cargo_format","{name}"},{"transport_cargo_format","{destination}"},
        {"transport_trip_format","{remaining}"},{"transport_speed_format","{speed}"},{"transport_speed_format","{max_speed}"},
        {"transport_eta_format","{status}"},{"transport_eta_format","{hours}"},{"transport_hours_format","{value}"},
    }) {
        if !strings.contains(text.entries[pair[0]],pair[1]) {
            fmt.eprintf("Localization: %q must contain %s.\n",pair[0],pair[1])
            return {}, false
        }
    }
    for key in ([?]string{"station_resources", "station_subjects", "station_ships", "station_empty", "station_stock_format", "station_ship_format"}) {
        if strings.trim_space(text.entries[key]) == "" {
            fmt.eprintf("Localization: missing or empty required key %q.\n", key)
            return {}, false
        }
    }
    for token in ([?]string{"{name}", "{units}", "{capacity}", "{rate}"}) {
        if !strings.contains(text.entries["station_stock_format"], token) {
            fmt.eprintf("Localization: %q must contain %s.\n", "station_stock_format", token)
            return {}, false
        }
    }
    for token in ([?]string{"{name}", "{units}"}) {
        if !strings.contains(text.entries["station_ship_format"], token) {
            fmt.eprintf("Localization: %q must contain %s.\n", "station_ship_format", token)
            return {}, false
        }
    }
    for key in ([?]string{"building_info_health", "building_info_level", "building_info_active", "building_info_inactive", "building_info_close"}) {
        if strings.trim_space(text.entries[key]) == "" {
            fmt.eprintf("Localization: missing or empty required key %q.\n", key)
            return {}, false
        }
    }
    for key in ([?]string{"building_info_health", "building_info_level"}) {
        if !strings.contains(text.entries[key], "{value}") {
            fmt.eprintf("Localization: %q must contain %s.\n", key, "{value}")
            return {}, false
        }
    }
    for key in ([?]string{"power_output_format", "power_need_format", "power_available_format"}) {
        if !strings.contains(text.entries[key], "{value}") {
            fmt.eprintf("Localization: %q must contain %s.\n", key, "{value}")
            return {}, false
        }
    }
    for token in ([?]string{"{hours}", "{speed}"}) {
        if !strings.contains(text.hud_clock_format, token) {
            fmt.eprintf("Localization: %q must contain %s.\n", "hud_clock_format", token)
            return {}, false
        }
    }
    for key in ([?]string{"window_title", "menu_title", "play", "load", "settings", "exit_game",
        "notice_insufficient_power", "notice_generator_required", "notice_control_unit_locked", "notice_always_on_locked", "notice_insufficient_health",
        "building_control_unit_name", "building_control_unit_description", "load_unavailable", "settings_unavailable"}) {
        if strings.trim_space(text.entries[key]) == "" {
            fmt.eprintf("Localization: missing or empty required key %q.\n", key)
            return {}, false
        }
    }
    if !validate_inspector_text(text.entries) { return {}, false }
    return text, true
}

load_english :: proc(allocator: mem.Allocator) -> (Text, bool) {
    path :: "assets/localization/en.json"
    data, read_ok := os.read_entire_file(path)
    if !read_ok {
        fmt.eprintf("Cannot read %s. Start the game from the repository root.\n", path)
        return {}, false
    }
    defer delete(data)
    text, ok := decode(data, allocator)
    if !ok { fmt.eprintf("Invalid %s: fix the localization error reported above, then restart the game.\n", path) }
    return text, ok
}
