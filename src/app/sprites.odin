package main

import "../config"
import "../logic"

// Startup/reload collection only. Paths borrow the candidate catalog; renderer
// deduplicates and stages them. No backend handles enter simulation or UI state.
sprite_paths :: proc(catalog: config.Catalog) -> []string {
    paths := make([dynamic]string, context.temp_allocator)
    for building in catalog.buildings { if building.sprite != "" { append(&paths, building.sprite) } }
    for subject in catalog.subjects {
        if subject.sprite != "" { append(&paths, subject.sprite) }
        for role in subject.roles { if role.sprite != "" { append(&paths, role.sprite) } }
    }
    return paths[:]
}

// Subject presentation uses only the subject type and its per-role overrides; the
// role catalog supplies identity metadata, never assets. Role order is cosmetic and
// does not alter job eligibility. An empty result means the caller falls back to the
// subject type color.
subject_sprite_definitions :: proc(definitions: []logic.Subject_Role_Definition, fallback: string) -> string {
    for definition in definitions { if definition.sprite != "" { return definition.sprite } }
    return fallback
}

subject_sprite :: proc(roles: []logic.Subject_Role, definitions: []logic.Subject_Role_Definition, fallback: string) -> string {
    for job in roles {
        for definition in definitions { if definition.role_id == job && definition.sprite != "" { return definition.sprite } }
    }
    return fallback
}
