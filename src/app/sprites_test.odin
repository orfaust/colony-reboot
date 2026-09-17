package main

import "core:testing"
import "../logic"
import "../config"

@(test)
sprite_catalog_collection_and_subject_priority :: proc(t: ^testing.T) {
    defer free_all(context.temp_allocator)
    buildings := [?]logic.Building_Type{{sprite="assets/a.png"}, {sprite=""}}
    roles := [?]logic.Subject_Role_Definition{{role_id=.worker,sprite="assets/worker.png"},{role_id=.supervisor,sprite=""},{role_id=.repairer}}
    subjects := [?]logic.Subject_Type{{id="human",sprite="assets/human.png",roles=roles[:]},{id="robot",roles=roles[:]}}
    catalog := config.Catalog{buildings=buildings[:],subjects=subjects[:]}
    paths := sprite_paths(catalog)
    // Building, subject-type and per-role paths only; the role catalog contributes none.
    testing.expect(t, len(paths) == 4 && paths[0] == buildings[0].sprite && paths[1] == "assets/human.png" && paths[2] == "assets/worker.png")
    jobs := [?]logic.Subject_Role{.repairer,.supervisor,.worker}
    // Runtime role order wins; an unmatched job falls back to the subject-type sprite.
    testing.expect(t, subject_sprite(jobs[:], roles[:], "assets/human.png") == "assets/worker.png")
    testing.expect(t, subject_sprite(jobs[:2], roles[:], "assets/human.png") == "assets/human.png")
    testing.expect(t, subject_sprite(jobs[:], nil, "assets/human.png") == "assets/human.png")
    testing.expect(t, subject_sprite(jobs[:], nil, "") == "" && subject_sprite(nil, nil, "") == "")
    testing.expect(t, subject_sprite_definitions(roles[:], "assets/human.png") == "assets/worker.png")
    testing.expect(t, subject_sprite_definitions(roles[1:], "assets/human.png") == "assets/human.png")
    testing.expect(t, subject_sprite_definitions(nil, "") == "")
}
