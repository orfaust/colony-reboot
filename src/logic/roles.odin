package logic

import c "../contracts"

Role :: c.Role

// Preserve the existing simulation jobs; their catalog metadata cannot rename or
// create gameplay behavior. No allocation or dependency on localization/rendering.
subject_role_id :: proc(role: Subject_Role) -> string {
    switch role {
    case .worker: return "worker"
    case .supervisor: return "supervisor"
    case .repairer: return "repairer"
    }
    unreachable()
}

// Returned metadata borrows the supplied catalog. No fallback UI text is invented.
find_role :: proc(roles: []Role, id: string) -> (Role, bool) {
    for role in roles { if role.id == id { return role, true } }
    return {}, false
}
