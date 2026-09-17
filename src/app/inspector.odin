package main

import c "../contracts"
import "../logic"
import "../localization"
import "../config"
import "core:fmt"
import "core:strings"

// Read-only inputs borrow session/catalog storage. Returned lines belong to the
// frame allocator; UI/render must consume them before it resets. No state changes.
//
// `coverages` is optional and, when supplied, is indexed by `Subject_Role` value
// order (worker, supervisor, repairer): `coverages[int(role)]`. The application
// builds it from `logic.staffing_coverage`, so the inspector reports physical
// coverage and reservations instead of assumed assignments. Passing nil keeps the
// function usable from narrow fixtures and reports zero coverage.
//
// `stock` is the selected building's borrowed runtime stock view
// (`logic.stock_snapshot`); nil lists no resources. Live amounts come only from it,
// never from the immutable level template. `block` is the live hourly-recipe
// evaluation (`logic.production_status`) and `rates` the resolved per-hour flow per
// stock entry (`logic.production_rates`), both read-only inputs.
building_info_lines :: proc(building: c.Building_Snapshot, definition: logic.Building_Type, text: localization.Text, instance: logic.Building_Instance, catalog: config.Catalog, subjects: []logic.Runtime_Subject, coverages: []c.Staffing_Coverage, stock: []c.Stock_Snapshot, block: c.Production_Block, rates: []c.Production_Rate) -> []string {
    lines := make([dynamic]string, 0, 16, context.temp_allocator)
    append(&lines, text.entries[definition.name_key])
    append(&lines, text.entries[definition.description_key])
    append(&lines, text.entries[building.active ? "building_info_active" : "building_info_inactive"])
    append(&lines, power_text(text.entries["building_info_health"], f64(building.health)*100))
    append(&lines, power_text(text.entries["building_info_level"], building.level*100))
    // Only rows that apply to this type are shown: a non-producer has no output row,
    // and a type with no resident slot has no Subjects section at all.
    if definition.power_output_kw > 0 {
        append(&lines, power_text(text.entries["building_info_power_output"], building.power_output_kw))
    }
    append(&lines, power_text(text.entries["building_info_power_need"], building.power_need_kw))
    if logic.hosts_residents(definition) {
        append(&lines, text.entries["building_info_subjects"])
        name: string
        for subject in catalog.subjects {
            if subject.id == definition.residents.type { name = text.entries[subject.name_key]; break }
        }
        amount, _ := instance.residents_amount.?
        append(&lines, inspector_format(text.entries["building_info_residents"], {{"{name}",name},{"{amount}",inspector_number(amount)},{"{capacity}",inspector_number(definition.residents.capacity)}}))
    }
    append_staffing_lines(&lines, definition, text, coverages)
    append_individual_lines(&lines, building.id, text, catalog, subjects)
    append_stock_lines(&lines, stock, catalog, text, rates)
    // A type with no recipe has no production state to report.
    if len(definition.needs) > 0 || len(definition.produces) > 0 {
        append(&lines, inspector_format(text.entries["building_info_production"], {{ "{value}",text.entries[production_block_key(block)] }}))
    }
    append(&lines, text.entries["building_info_needs"])
    if len(definition.needs) == 0 { append(&lines, text.entries["building_info_empty"]) }
    for need in definition.needs {
        key := "building_info_rate_hour"
        value := need.amount_per_hour
        if need.amount_per_unit > 0 { key = "building_info_rate_product"; value = need.amount_per_unit }
        inspector_resource_lines(&lines, need.resource_id, value, key, catalog, text)
    }
    append(&lines, text.entries["building_info_products"])
    if len(definition.produces) == 0 { append(&lines, text.entries["building_info_empty"]) }
    for product in definition.produces {
        inspector_resource_lines(&lines, product.resource_id, product.units_per_hour, "building_info_rate_hour", catalog, text)
    }
    append(&lines, text.entries["building_info_close"])
    return lines[:]
}

// One building's continuous staffing coverage plus any configured on-demand role
// quantities. Only physical occupants count as covered; scheduled replacements are
// reported separately, and the uncovered count is required minus covered.
append_staffing_lines :: proc(lines: ^[dynamic]string, definition: logic.Building_Type, text: localization.Text, coverages: []c.Staffing_Coverage) {
    append(lines, text.entries["building_info_staffing"])
    required_total, covered_total: int
    for role in logic.Subject_Role {
        coverage := coverage_for(coverages, role)
        required_total += coverage.required_slots
        covered_total += coverage.covered_slots
        if coverage.required_slots == 0 { continue }
        append(lines, inspector_format(text.entries[role_coverage_key(role)], {
            {"{covered}",inspector_number(f32(coverage.covered_slots))},
            {"{required}",inspector_number(f32(coverage.required_slots))},
        }))
        if coverage.reserved_slots > 0 {
            append(lines, inspector_format(text.entries["building_info_coverage_reserved"], {
                {"{role}",text.entries[role_name_key(role)]},
                {"{reserved}",inspector_number(f32(coverage.reserved_slots))},
            }))
        }
    }
    if required_total == 0 { append(lines, text.entries["building_info_no_staff"]) }
    if uncovered := required_total-covered_total; uncovered > 0 {
        append(lines, inspector_format(text.entries["building_info_uncovered"], {{"{count}",inspector_number(f32(uncovered))}}))
    }
    for role in logic.Subject_Role {
        quantity := configured_staffing_quantity(definition, role, .on_demand)
        if quantity == 0 { continue }
        append(lines, inspector_format(text.entries["building_info_coverage_ondemand"], {
            {"{role}",text.entries[role_name_key(role)]},
            {"{quantity}",inspector_number(f32(quantity))},
        }))
    }
}

// One fixed-size detail block per individual associated with the building
// (resident, physically assigned, or reserved). Blocks are appended in stable
// runtime subject order so scrolling content is deterministic.
append_individual_lines :: proc(lines: ^[dynamic]string, building_id: string, text: localization.Text, catalog: config.Catalog, subjects: []logic.Runtime_Subject) {
    append(lines, text.entries["building_info_individuals"])
    count := 0
    for &subject in subjects {
        if subject.activity == .Removed || !subject_belongs_to_building(subject, building_id) { continue }
        view := logic.subject_view_of(&subject)
        definition, found := find_subject_definition(catalog, view.subject_id)
        name := view.subject_id
        if found { name = text.entries[definition.name_key] }
        append(lines, ..subject_info_lines(view, subject.reservation, name, definition, text, catalog))
        count += 1
    }
    if count == 0 { append(lines, text.entries["building_info_no_individuals"]) }
}

// Readable, fixed-shape detail block for one individual: identity, health, phase,
// role, assignment, timers, medical status and per-need fulfillment/shortage. The
// snapshot omits the reservation, so the caller forwards the authoritative value
// separately (nil when the subject has no scheduled replacement). The result lives
// in the frame allocator and contains no authoritative pointers.
subject_info_lines :: proc(view: c.Subject_Snapshot, reservation: Maybe(c.Shift_Assignment), name: string, definition: logic.Subject_Type, text: localization.Text, catalog: config.Catalog) -> []string {
    lines := make([dynamic]string, 0, 12, context.temp_allocator)
    append(&lines, inspector_format(text.entries["subject_info_identity"], {
        {"{name}",name},
        {"{id}",fmt.aprintf("%d",u64(view.id),allocator=context.temp_allocator)},
    }))
    append(&lines, power_text(text.entries["subject_info_health"], f64(view.health)*100))
    append(&lines, inspector_format(text.entries["subject_info_phase"], {{"{value}",text.entries[work_phase_key(view.work_phase)]}}))
    role_value := subject_role_value(view.assignment,reservation,text)
    assignment_value := text.entries["subject_info_unassigned"]
    if value, ok := active_shift(view.assignment,reservation).?; ok {
        assignment_value = slot_text(text, value.building_id, value.slot_index)
    }
    append(&lines, inspector_format(text.entries["subject_info_role"], {{"{value}",role_value}}))
    append(&lines, inspector_format(text.entries["subject_info_assignment"], {{"{value}",assignment_value}}))
    append(&lines, inspector_format(text.entries["subject_info_timers"], {
        {"{work}",info_number(view.work_hours)},
        {"{max_work}",info_number(f64(definition.work_time))},
        {"{rest}",info_number(view.rest_hours)},
        {"{max_rest}",info_number(f64(definition.rest_time))},
        {"{idle}",info_number(view.idle_hours)},
    }))
    append(&lines, inspector_format(text.entries["subject_info_medical"], {{"{value}",text.entries[medical_status_key(view.medical)]}}))
    append(&lines, text.entries["subject_info_needs"])
    if view.need_count == 0 { append(&lines, text.entries["subject_info_no_needs"]) }
    for i in 0..<view.need_count {
        need := view.needs[i]
        key := need.shortage_hours > 0 ? "subject_info_need_short" : "subject_info_need_ok"
        append(&lines, inspector_format(text.entries[key], {
            {"{name}",resource_name(catalog, text, need.resource_id)},
            {"{value}",info_number(f64(need.fulfillment)*100)},
            {"{hours}",info_number(need.shortage_hours)},
        }))
    }
    return lines[:]
}

// A physical assignment outranks a scheduled replacement; a subject holds at most
// one of the two, so the first set value is the active shift.
active_shift :: proc(assignment, reservation: Maybe(c.Shift_Assignment)) -> Maybe(c.Shift_Assignment) {
    if _, ok := assignment.?; ok { return assignment }
    return reservation
}

// Role label for an individual, from its physical assignment or its scheduled
// replacement; unassigned when neither exists. Shared by inspector and grid.
subject_role_value :: proc(assignment, reservation: Maybe(c.Shift_Assignment), text: localization.Text) -> string {
    if value, ok := active_shift(assignment,reservation).?; ok { return text.entries[role_name_key(value.role_id)] }
    return text.entries["subject_info_unassigned"]
}

// A level instance ID is stable session data; the slot index disambiguates
// replacements sharing a role.
slot_text :: proc(text: localization.Text, building_id: string, slot_index: int) -> string {
    return inspector_format(text.entries["subject_info_slot"], {
        {"{building}",building_id},
        {"{slot}",fmt.aprintf("%d",slot_index,allocator=context.temp_allocator)},
    })
}

// Coverage is supplied in `Subject_Role` order; a shorter or absent slice reports
// zero coverage instead of inventing slots.
coverage_for :: proc(coverages: []c.Staffing_Coverage, role: logic.Subject_Role) -> c.Staffing_Coverage {
    if int(role) < len(coverages) { return coverages[int(role)] }
    return {role_id=role}
}

// An individual is listed under a building when it lives there or holds a physical
// assignment or a scheduled reservation for it.
subject_belongs_to_building :: proc(subject: logic.Runtime_Subject, building_id: string) -> bool {
    if building_id == "" { return false }
    if subject.residence == building_id { return true }
    if assignment, ok := subject.assignment.?; ok && assignment.building_id == building_id { return true }
    if reservation, ok := subject.reservation.?; ok && reservation.building_id == building_id { return true }
    return false
}

configured_staffing_quantity :: proc(definition: logic.Building_Type, role: logic.Subject_Role, mode: logic.Staffing_Mode) -> int {
    for entry in definition.subject_roles {
        if entry.role_id == role && entry.staffing_mode == mode { return max(0,entry.quantity) }
    }
    return 0
}

find_subject_definition :: proc(catalog: config.Catalog, id: string) -> (logic.Subject_Type, bool) {
    for subject in catalog.subjects { if subject.id == id { return subject, true } }
    return {}, false
}

resource_name :: proc(catalog: config.Catalog, text: localization.Text, id: string) -> string {
    for resource in catalog.resources { if resource.id == id { return text.entries[resource.name_key] } }
    return id
}

role_coverage_key :: proc(role: logic.Subject_Role) -> string {
    switch role {
    case .worker: return "building_info_workers"
    case .supervisor: return "building_info_supervisors"
    case .repairer: return "building_info_repairers"
    }
    return ""
}

role_name_key :: proc(role: logic.Subject_Role) -> string {
    switch role {
    case .worker: return "subject_role_worker_name"
    case .supervisor: return "subject_role_supervisor_name"
    case .repairer: return "subject_role_repairer_name"
    }
    return ""
}

work_phase_key :: proc(phase: c.Work_Phase) -> string {
    switch phase {
    case .Idle: return "work_phase_idle"
    case .Resting: return "work_phase_resting"
    case .Reserved: return "work_phase_reserved"
    case .Moving_To_Work: return "work_phase_moving_to_work"
    case .Working: return "work_phase_working"
    case .Extra_Working: return "work_phase_extra_working"
    }
    return ""
}

medical_status_key :: proc(status: c.Medical_Status) -> string {
    switch status {
    case .None: return "medical_status_none"
    case .Pending_Evacuation: return "medical_status_pending_evacuation"
    case .Evacuating: return "medical_status_evacuating"
    case .Hospitalized: return "medical_status_hospitalized"
    case .Returning: return "medical_status_returning"
    }
    return ""
}

inspector_number :: proc(value: f32) -> string { return info_number(f64(value)) }

inspector_format :: proc(template: string, replacements: [][2]string) -> string {
    result := template
    for pair in replacements {
        result, _ = strings.replace_all(result, pair[0], pair[1], context.temp_allocator)
    }
    return result
}

// Validated resource references and stock entries are guaranteed by config loading.
// The stock list shows live runtime amounts and capacities for every resolved
// resource (including storage-only ones), plus the resolved hourly flow when the
// recipe consumes or produces that resource; needs and products keep their
// configured rate too, so one resource never repeats an amount line.
append_stock_lines :: proc(lines: ^[dynamic]string, stock: []c.Stock_Snapshot, catalog: config.Catalog, text: localization.Text, rates: []c.Production_Rate) {
    append(lines, text.entries["building_info_stock_header"])
    if len(stock) == 0 { append(lines, text.entries["building_info_empty"]); return }
    for entry in stock {
        name, unit: string
        for resource in catalog.resources {
            if resource.id == entry.resource_id {
                name, unit = text.entries[resource.name_key], text.entries[resource.unit_type_key]
                break
            }
        }
        append(lines, inspector_format(text.entries["building_info_stock"], {
            {"{name}",name},
            {"{unit}",unit},
            {"{amount}",info_number(entry.amount)},
            {"{capacity}",info_number(entry.capacity)},
        }))
        for rate in rates {
            if rate.resource_id != entry.resource_id { continue }
            if rate.consumed_per_hour == 0 && rate.produced_per_hour == 0 { break }
            append(lines, inspector_format(text.entries["building_info_stock_flow"], {
                {"{name}",name},
                {"{unit}",unit},
                {"{consumed}",info_number(rate.consumed_per_hour,3)},
                {"{produced}",info_number(rate.produced_per_hour,3)},
            }))
            break
        }
    }
}

// Localized status text for the live recipe evaluation. A building that would run
// at the next hour boundary is "operational"; every other value is the blocking
// reason.
production_block_key :: proc(block: c.Production_Block) -> string {
    switch block {
    case .None: return "production_state_operational"
    case .Inactive: return "production_state_inactive"
    case .Warming_Up: return "production_state_warming_up"
    case .Unstaffed: return "production_state_unstaffed"
    case .Missing_Input: return "production_state_missing_input"
    case .Output_Full: return "production_state_output_full"
    }
    return ""
}

// Configured coefficient for one need or product; rates are metadata, not simulated
// flow yet. Live amounts are shown only by the stock list above.
inspector_resource_lines :: proc(lines: ^[dynamic]string, id: string, rate: f32, rate_key: string, catalog: config.Catalog, text: localization.Text) {
    unit: string
    for resource in catalog.resources {
        if resource.id == id { unit = text.entries[resource.unit_type_key]; break }
    }
    append(lines, inspector_format(text.entries[rate_key], {{"{value}",info_number(f64(rate), 3)},{"{unit}",unit}}))
}
