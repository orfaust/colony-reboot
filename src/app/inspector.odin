package main

import c "../contracts"
import "../logic"
import "../localization"
import "../config"
import "core:strings"

// Read-only inputs borrow session/catalog storage. Returned lines belong to the
// frame allocator; UI/render must consume them before it resets. No state changes.
building_info_lines :: proc(building: c.Building_Snapshot, definition: logic.Building_Type, text: localization.Text, instance: logic.Building_Instance, catalog: config.Catalog, subjects: []logic.Runtime_Subject) -> []string {
    lines := make([dynamic]string, 8, context.temp_allocator)
    lines[0] = text.entries[definition.name_key]
    lines[1] = text.entries[definition.description_key]
    lines[2] = text.entries[building.active ? "building_info_active" : "building_info_inactive"]
    lines[3] = power_text(text.entries["building_info_health"], f64(building.health)*100)
    lines[4] = power_text(text.entries["building_info_level"], building.level*100)
    lines[5] = power_text(text.entries["building_info_power_output"], building.power_output_kw)
    lines[6] = power_text(text.entries["building_info_power_need"], building.power_need_kw)
    lines[7] = text.entries["building_info_subjects"]
    if logic.hosts_residents(definition) {
        name: string
        for subject in catalog.subjects {
            if subject.id == definition.residents.type { name = text.entries[subject.name_key]; break }
        }
        amount, _ := instance.residents_amount.?
        append(&lines, inspector_format(text.entries["building_info_residents"], {{"{name}",name},{"{amount}",inspector_number(amount)},{"{capacity}",inspector_number(definition.residents.capacity)}}))
    } else {
        append(&lines, text.entries["building_info_no_residents"])
    }
    // Count assigned role-capable individuals, not assumed workers physically inside.
    assigned: [logic.Subject_Role]int
    for subject in subjects {
        if subject.occupation != building.id || subject.activity == .Removed { continue }
        for role in subject.roles { assigned[role] += 1 }
    }
    has_staff := false
    for role in logic.Subject_Role {
        key: string
        required: f32
        for staffing in definition.subject_roles { if staffing.role_id == role { required = staffing.quantity; break } }
        switch role {
        case .worker: key = "building_info_workers"
        case .supervisor: key = "building_info_supervisors"
        case .repairer: key = "building_info_repairers"
        }
        if required == 0 && assigned[role] == 0 { continue }
        has_staff = true
        append(&lines, inspector_format(text.entries[key], {{"{assigned}",inspector_number(f32(assigned[role]))},{"{required}",inspector_number(required)}}))
    }
    if !has_staff { append(&lines,text.entries["building_info_no_staff"]) }
    append(&lines, text.entries["building_info_needs"])
    if len(definition.needs) == 0 { append(&lines, text.entries["building_info_empty"]) }
    for need in definition.needs {
        key := "building_info_rate_hour"
        value := need.amount_per_hour
        if need.amount_per_unit > 0 { key = "building_info_rate_product"; value = need.amount_per_unit }
        if need.amount_per_resident > 0 { key = "building_info_rate_resident"; value = need.amount_per_resident }
        inspector_resource_lines(&lines, need.resource_id, need.capacity, value, key, instance, catalog, text)
    }
    append(&lines, text.entries["building_info_products"])
    if len(definition.produces) == 0 { append(&lines, text.entries["building_info_empty"]) }
    for product in definition.produces {
        key := "building_info_rate_hour"
        value := product.units_per_hour
        if product.amount_per_resident > 0 { key = "building_info_rate_resident"; value = product.amount_per_resident }
        inspector_resource_lines(&lines, product.resource_id, product.capacity, value, key, instance, catalog, text)
    }
    append(&lines, text.entries["building_info_close"])
    return lines[:]
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
// Stock is current instance data; rates are configured coefficients, not simulated flow.
inspector_resource_lines :: proc(lines: ^[dynamic]string, id: string, capacity, rate: f32, rate_key: string, instance: logic.Building_Instance, catalog: config.Catalog, text: localization.Text) {
    name, unit: string
    for resource in catalog.resources {
        if resource.id == id {
            name, unit = text.entries[resource.name_key], text.entries[resource.unit_type_key]
            break
        }
    }
    amount: f32
    for stock in instance.stored { if stock.resource_id == id { amount = stock.amount; break } }
    append(lines, inspector_format(text.entries["building_info_stock"], {{"{name}",name},{"{unit}",unit},{"{amount}",inspector_number(amount)},{"{capacity}",inspector_number(capacity)}}))
    append(lines, inspector_format(text.entries[rate_key], {{"{value}",info_number(f64(rate), 3)},{"{unit}",unit}}))
}
