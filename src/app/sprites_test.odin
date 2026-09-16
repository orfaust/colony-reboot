package main

import "core:testing"
import "../logic"
import "../config"

@(test)
sprite_catalog_collection_and_role_priority :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    buildings := [?]logic.Building_Type{{sprite="assets/a.png"}, {sprite=""}}
    roles := [?]logic.Role{
        {id="worker",sprite="assets/worker.png"},
        {id="supervisor",sprite="assets/supervisor.png"},
        {id="repairer",sprite=""},
    }
    catalog := config.Catalog{buildings=buildings[:],subject_roles=roles[:]}
    paths := sprite_paths(catalog)
    testing.expect(t, len(paths) == 3 && paths[0] == buildings[0].sprite)
    jobs := [?]logic.Subject_Role{.repairer,.supervisor,.worker}
    testing.expect(t, subject_sprite(jobs[:], catalog) == "assets/supervisor.png")
    testing.expect(t, subject_sprite(jobs[:1], catalog) == "")
    testing.expect(t, subject_sprite(nil, catalog) == "")
}
