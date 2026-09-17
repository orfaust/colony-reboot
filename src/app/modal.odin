package main

import "core:fmt"
import "core:strings"
import c "../contracts"
import "../config"
import "../logic"
import "../localization"

// Overview grids for the bottom-right toggles. The application builds localized
// columns and one row per element; UI paginates and render draws. Every cell is
// frame-owned text and no authoritative state is mutated.
building_grid_columns :: proc(text: localization.Text) -> []string {
    keys := [?]string{
        "grid_building_code", "grid_building_name", "grid_building_state", "grid_building_health",
        "grid_building_activity", "grid_building_power_out", "grid_building_power_need",
        "grid_building_residents", "grid_building_staffing",
        "grid_building_needs", "grid_building_products", "grid_building_storage",
    }
    columns := make([]string,len(keys),context.temp_allocator)
    for key, i in keys { columns[i] = text.entries[key] }
    return columns
}

// One configured resource slot with its capacity; needs, products and storage share
// this view for the compact `<name> <qty>/<capacity>` grid cell. Live amounts come
// from the building's borrowed runtime stock view, never from the level template.
Resource_Entry :: struct { resource_id: string, capacity: f32 }

@(private)
resource_amount :: proc(stock: []c.Stock_Snapshot, resource_id: string) -> f64 {
    for entry in stock { if entry.resource_id == resource_id { return entry.amount } }
    return 0
}

@(private)
resource_stocks_text :: proc(entries: []Resource_Entry, stock: []c.Stock_Snapshot, text: localization.Text) -> string {
    if len(entries) == 0 { return text.entries["modal_none"] }
    builder := strings.builder_make(context.temp_allocator)
    for entry, i in entries {
        if i > 0 { strings.write_string(&builder,"; ") }
        strings.write_string(&builder,info_number(resource_amount(stock,entry.resource_id)))
        strings.write_byte(&builder,'/')
        strings.write_string(&builder,inspector_number(entry.capacity))
    }
    return strings.to_string(builder)
}

building_grid_rows :: proc(game: ^logic.State, catalog: config.Catalog, text: localization.Text) -> []c.Modal_Row {
    rows := make([]c.Modal_Row,len(game.buildings),context.temp_allocator)
    for i in 0..<len(game.buildings) {
        view := logic.snapshot(game,i)
        definition, found := config.find_building(catalog,view.building_id)
        cells := make([]string,12,context.temp_allocator)
        cells[0] = definition.code
        cells[1] = text.entries[definition.name_key]
        cells[2] = text.entries[view.active ? "building_info_active" : "building_info_inactive"]
        cells[3] = inspector_number(f32(view.health*100))
        cells[4] = inspector_number(f32(view.level*100))
        cells[5] = info_number(view.power_output_kw)
        cells[6] = info_number(view.power_need_kw)
        if logic.hosts_residents(definition) {
            amount, _ := game.buildings[i].residents_amount.?
            cells[7] = fmt.tprintf("%s/%s",inspector_number(amount),inspector_number(definition.residents.capacity))
        } else {
            cells[7] = text.entries["modal_none"]
        }
        covered, required: int
        for role in logic.Subject_Role {
            coverage := logic.staffing_coverage(game,i,role)
            covered += coverage.covered_slots
            required += coverage.required_slots
        }
        cells[8] = fmt.tprintf("%s/%s",inspector_number(f32(covered)),inspector_number(f32(required)))
        stock := logic.stock_snapshot(game,i)
        needs := make([]Resource_Entry,len(definition.needs),context.temp_allocator)
        for need, n in definition.needs { needs[n] = {need.resource_id,need.capacity} }
        cells[9] = resource_stocks_text(needs,stock,text)
        products := make([]Resource_Entry,len(definition.produces),context.temp_allocator)
        for product, p in definition.produces { products[p] = {product.resource_id,product.capacity} }
        cells[10] = resource_stocks_text(products,stock,text)
        storage := make([]Resource_Entry,len(definition.storage),context.temp_allocator)
        for entry, s in definition.storage { storage[s] = {entry.resource_id,entry.capacity} }
        cells[11] = resource_stocks_text(storage,stock,text)
        rows[i] = {cells=cells,swatch=definition.color,has_swatch=found}
    }
    return rows
}

subject_grid_columns :: proc(text: localization.Text) -> []string {
    keys := [?]string{
        "grid_subject_id", "grid_subject_name", "grid_subject_health", "grid_subject_phase",
        "grid_subject_residence", "grid_subject_occupation", "grid_subject_role", "grid_subject_medical", "grid_subject_timers",
    }
    columns := make([]string,len(keys),context.temp_allocator)
    for key, i in keys { columns[i] = text.entries[key] }
    return columns
}

// Workplace the subject currently occupies; mirrors the staffing assignment with a
// scheduled reservation as fallback.
@(private)
subject_occupation_building :: proc(subject: logic.Runtime_Subject) -> string {
    if subject.occupation != "" { return subject.occupation }
    if assignment, ok := subject.assignment.?; ok { return assignment.building_id }
    if reservation, ok := subject.reservation.?; ok { return reservation.building_id }
    return ""
}

// Displayed code of a building instance, never its level id.
@(private)
building_code_for :: proc(game: ^logic.State, catalog: config.Catalog, building_id: string) -> string {
    if building_id == "" { return "" }
    for building in game.buildings {
        if building.id != building_id { continue }
        definition, found := config.find_building(catalog,building.building_id)
        if found { return definition.code }
        break
    }
    return ""
}

subject_grid_rows :: proc(game: ^logic.State, fleet: ^logic.Transport_State, catalog: config.Catalog, text: localization.Text) -> []c.Modal_Row {
    rows := make([dynamic]c.Modal_Row,0,len(fleet.subjects),context.temp_allocator)
    for &subject in fleet.subjects {
        if subject.activity == .Removed { continue }
        view := logic.subject_view_of(&subject)
        definition, found := find_subject_definition(catalog,view.subject_id)
        name := view.subject_id
        if found { name = text.entries[definition.name_key] }
        cells := make([]string,9,context.temp_allocator)
        cells[0] = fmt.aprintf("%d",u64(view.id),allocator=context.temp_allocator)
        cells[1] = name
        cells[2] = inspector_number(f32(view.health*100))
        cells[3] = text.entries[work_phase_key(view.work_phase)]
        cells[4] = subject.residence != "" ? subject.residence : text.entries["modal_none"]
        occupation := building_code_for(game,catalog,subject_occupation_building(subject))
        cells[5] = occupation != "" ? occupation : text.entries["modal_none"]
        cells[6] = subject_role_value(subject.assignment,subject.reservation,text)
        cells[7] = text.entries[medical_status_key(view.medical)]
        work_time := found ? f64(definition.work_time) : 0
        cells[8] = fmt.tprintf("%s/%s",info_number(view.work_hours),info_number(work_time))
        swatch: c.RGB
        if found { swatch = definition.color }
        append(&rows,c.Modal_Row{cells=cells,swatch=swatch,has_swatch=found})
    }
    return rows[:]
}
