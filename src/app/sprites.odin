package main

import "../config"
import "../logic"

// Startup/reload collection only. Paths borrow the candidate catalog; renderer
// deduplicates and stages them. No backend handles enter simulation or UI state.
sprite_paths :: proc(catalog: config.Catalog) -> []string {
    paths := make([dynamic]string, context.temp_allocator)
    for building in catalog.buildings { if building.sprite != "" { append(&paths, building.sprite) } }
    for role in catalog.subject_roles { if role.sprite != "" { append(&paths, role.sprite) } }
    for subject in catalog.subjects {
        for role in subject.roles { if role.sprite != "" { append(&paths, role.sprite) } }
    }
    return paths[:]
}

// Subject-type sprite paths are currently metadata only. The first declared role with a sprite supplies
// their icon; role order is presentation-only and does not alter job eligibility.
subject_sprite_definitions :: proc(roles: []logic.Subject_Role_Definition, catalog: config.Catalog) -> string {
    for definition in roles {
        if definition.sprite != "" { return definition.sprite }
        if role, found := logic.find_role(catalog.subject_roles, logic.subject_role_id(definition.role_id)); found && role.sprite != "" { return role.sprite }
    }
    return ""
}

subject_sprite :: proc(roles: []logic.Subject_Role, catalog: config.Catalog, definitions: []logic.Subject_Role_Definition = nil) -> string {
    for job in roles {
        for definition in definitions { if definition.role_id == job && definition.sprite != "" { return definition.sprite } }
        if role, found := logic.find_role(catalog.subject_roles, logic.subject_role_id(job)); found && role.sprite != "" {
            return role.sprite
        }
    }
    return ""
}
