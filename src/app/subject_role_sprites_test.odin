package main

import "core:testing"
import "../config"
import "../logic"

@(test)
subject_role_sprite_overrides :: proc(t: ^testing.T) {
    metadata := [?]logic.Role{{id="worker",sprite="assets/worker.png"},{id="repairer",sprite="assets/repairer.png"}}
    roles := [?]logic.Subject_Role_Definition{{role_id=.worker,sprite="assets/human_worker.png"},{role_id=.repairer}}
    types := [?]logic.Subject_Type{{id="human",roles=roles[:]}}
    catalog := config.Catalog{subject_roles=metadata[:],subjects=types[:]}
    jobs := [?]logic.Subject_Role{.worker,.repairer}
    testing.expect(t, subject_sprite_definitions(roles[:],catalog) == "assets/human_worker.png")
    testing.expect(t, subject_sprite(jobs[:],catalog,roles[:]) == "assets/human_worker.png")
    testing.expect(t, subject_sprite(jobs[1:],catalog,roles[:]) == "assets/repairer.png")
    found := false
    for path in sprite_paths(catalog) { if path == "assets/human_worker.png" { found = true } }
    testing.expect(t, found)
    roles[0].sprite = ""
    testing.expect(t, subject_sprite_definitions(roles[:],catalog) == "assets/worker.png")
}
