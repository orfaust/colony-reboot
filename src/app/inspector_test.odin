package main

import c "../contracts"
import "../logic"
import "../localization"
import "core:strings"
import "core:testing"

@(test)
inspector_formats_snapshot :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    text: localization.Text
    text.entries = make(map[string]string, context.temp_allocator)
    text.entries["test_name"] = "Solar Panel"
    text.entries["test_description"] = "Generates power"
    text.entries["building_info_active"] = "Active"
    text.entries["building_info_inactive"] = "Inactive"
    text.entries["building_info_health"] = "Health: {value}%"
    text.entries["building_info_level"] = "Activity: {value}%"
    text.entries["building_info_close"] = "Escape to close"
    text.entries["building_info_production"] = "Production: {value}"
    text.entries["production_state_operational"] = "Operational"
    text.entries["production_state_inactive"] = "Inactive"
    text.power_output_format = "+{value} kW"
    text.entries["building_info_power_output"] = "Power produced: {value} kW"
    text.entries["building_info_power_need"] = "Power used: {value} kW"
    text.power_need_format = "-{value} kW"
    definition := logic.Building_Type{name_key="test_name", description_key="test_description", power_output_kw=10}
    building := c.Building_Snapshot{active=true, health=0.5, level=0.25, power_output_kw=4}
    lines := building_info_lines(building, definition, text, {}, {}, nil, nil, nil, .None, nil)
    testing.expect(t, lines[0] == "Solar Panel" && lines[1] == "Generates power")
    testing.expect(t, lines[2] == "Active" && lines[3] == "Health: 50%")
    testing.expect(t, lines[4] == "Activity: 25%" && lines[5] == "Power produced: 4 kW")
    // A type that cannot produce power never shows an output row.
    definition.power_output_kw = 0
    for line in building_info_lines(building, definition, text, {}, {}, nil, nil, nil, .None, nil) {
        testing.expect(t, !strings.contains(line, "Power produced"))
    }
    building.active = false
    testing.expect(t, building_info_lines(building, definition, text, {}, {}, nil, nil, nil, .None, nil)[2] == "Inactive")
}
