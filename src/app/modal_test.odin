package main

import "../config"
import "../logic"
import c "../contracts"
import "core:strings"
import "core:testing"

// Overview grids are built from the shipped level: localized columns, one row per
// element and no uncomposed placeholder in any cell. Rendering is not initialized.
@(test)
building_and_subject_grids_expose_relevant_cells :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    data := load_reload_data(INITIAL_LEVEL_PATH)
    testing.expect(t, data != nil)
    if data == nil { return }
    defer destroy_reload_data(data)
    game, fleet := new_level_runtime(data)
    defer logic.destroy_transports(&fleet,context.allocator)

    columns := building_grid_columns(data.text)
    testing.expect(t, len(columns) == 12)
    testing.expect(t, columns[0] == data.text.entries["grid_building_code"])
    testing.expect(t, columns[9] == data.text.entries["grid_building_needs"])
    testing.expect(t, columns[10] == data.text.entries["grid_building_products"])
    testing.expect(t, columns[11] == data.text.entries["grid_building_storage"])
    rows := building_grid_rows(&game,data.catalog,data.text)
    testing.expect(t, len(rows) == len(game.buildings))
    for row, i in rows {
        testing.expect(t, len(row.cells) == len(columns))
        // Every shipped instance shows its configured color as a swatch.
        definition, found := config.find_building(data.catalog,game.buildings[i].building_id)
        testing.expect(t, found && row.has_swatch && row.swatch == definition.color)
        for cell in row.cells {
            testing.expect(t, cell != "" && !strings.contains(cell,"{"))
        }
        // Needs/products/storage cells are qty/capacity pairs or the empty value.
        for col in 9..<12 {
            testing.expect(t, row.cells[col] == data.text.entries["modal_none"] || strings.contains(row.cells[col],"/"))
        }
    }
    // A non-resident type reports the localized empty value instead of a fake count.
    for instance, i in game.buildings {
        definition, found := config.find_building(data.catalog,instance.building_id)
        if !found || logic.hosts_residents(definition) { continue }
        testing.expect(t, rows[i].cells[7] == data.text.entries["modal_none"])
    }

    subject_columns := subject_grid_columns(data.text)
    testing.expect(t, len(subject_columns) == 9)
    testing.expect(t, subject_columns[0] == data.text.entries["grid_subject_id"])
    testing.expect(t, subject_columns[5] == data.text.entries["grid_subject_occupation"])
    subject_rows := subject_grid_rows(&game,&fleet,data.catalog,data.text)
    live := 0
    for subject in fleet.subjects { if subject.activity != .Removed { live += 1 } }
    testing.expect(t, len(subject_rows) == live)
    for row in subject_rows {
        testing.expect(t, len(row.cells) == len(subject_columns))
        testing.expect(t, row.has_swatch) // Subject types are configured with a color.
        for cell in row.cells {
            testing.expect(t, cell != "" && !strings.contains(cell,"{"))
        }
    }
}

// The subjects grid's occupation column names the assigned workplace by its
// displayed catalog code, never the level instance id.
@(test)
subject_grid_shows_occupation_building_code :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    data := load_reload_data(INITIAL_LEVEL_PATH)
    testing.expect(t, data != nil)
    if data == nil { return }
    defer destroy_reload_data(data)
    game, fleet := new_level_runtime(data)
    defer logic.destroy_transports(&fleet,context.allocator)
    building := data.level.buildings[0]
    definition, found := config.find_building(data.catalog,building.building_id)
    testing.expect(t, found)
    testing.expect(t, len(data.catalog.subjects) > 0)
    if !found || len(data.catalog.subjects) == 0 { return }
    assignment := c.Shift_Assignment{building_id=building.id, role_id=.worker, slot_index=0}
    append(&fleet.subjects,logic.Runtime_Subject{
        id=c.Subject_ID(999),subject_id=data.catalog.subjects[0].id,residence=building.id,occupation=building.id,
        activity=.Inside,phase=.Working,health=1,assignment=assignment,
    })
    rows := subject_grid_rows(&game,&fleet,data.catalog,data.text)
    last := rows[len(rows)-1]
    testing.expect(t, last.cells[5] == definition.code)
    testing.expect(t, last.cells[4] == building.id) // Residence keeps the instance id.
    // Unassigned individuals show the localized empty value.
    fleet.subjects[len(fleet.subjects)-1].occupation = ""
    fleet.subjects[len(fleet.subjects)-1].assignment = nil
    rows = subject_grid_rows(&game,&fleet,data.catalog,data.text)
    testing.expect(t, rows[len(rows)-1].cells[5] == data.text.entries["modal_none"])
}
