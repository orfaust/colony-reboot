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
    notice_insufficient_power, notice_generator_required, notice_control_unit_locked: string,
    play, load, settings, exit_game: string,
    building_control_unit_name, building_control_unit_description: string,
    load_unavailable, settings_unavailable: string,
}

// All returned strings belong to allocator, including partial results on failure.
// The caller must release its localization arena after the window and UI shut down.
decode :: proc(data: []byte, allocator: mem.Allocator) -> (text: Text, ok: bool) {
    err := json.unmarshal(data, &text, allocator=allocator)
    if err != nil { return {}, false }
    // Keep additional named strings available to data-driven building/resource keys.
    if err := json.unmarshal(data, &text.entries, allocator=allocator); err != nil { return {}, false }
    for _, value in text.entries {
        if strings.trim_space(value) == "" || strings.contains(value, "\x00") { return {}, false }
    }
    formats := [?]string{text.power_output_format, text.power_need_format, text.power_available_format}
    for format in formats { if !strings.contains(format, "{value}") { return {}, false } }
    values := [?]string{text.window_title, text.menu_title, text.play, text.load, text.settings,
                        text.notice_insufficient_power, text.notice_generator_required, text.notice_control_unit_locked,
                        text.exit_game, text.building_control_unit_name,
                        text.building_control_unit_description, text.load_unavailable,
                        text.settings_unavailable}
    for value in values {
        if strings.trim_space(value) == "" || strings.contains(value, "\x00") {
            return {}, false
        }
    }
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
    if !ok { fmt.eprintf("Invalid %s: expected JSON with all required nonempty text fields and {value} in each power format.\n", path) }
    return text, ok
}
