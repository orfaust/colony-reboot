package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../logic"
import "../localization"

roles_fixture :: string(`[
{"id":"worker","name_key":"worker_name"},
{"id":"supervisor","name_key":"supervisor_name"},
{"id":"repairer","name_key":"repairer_name"}
]`)

@(test)
role_metadata_contract_and_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := make(map[string]string, allocator)
    texts["worker_name"] = "Worker"
    texts["supervisor_name"] = "Supervisor"
    texts["repairer_name"] = "Repairer"
    roles, error := decode_roles(transmute([]byte)roles_fixture, texts, allocator)
    testing.expect(t, error == "", error)
    if error != "" { return }
    testing.expect(t, len(roles) == 3)
    for job in logic.Subject_Role {
        role, found := logic.find_role(roles, logic.subject_role_id(job))
        testing.expect(t, found && role.name != "")
    }
    testing.expect(t, roles[0].id == "worker" && roles[0].name == "Worker")
    _, found := logic.find_role(roles, "unknown")
    testing.expect(t, !found)
    changes := [?][2]string{
        {`"id":"worker"`, `"id":"supervisor"`},
        {`"id":"worker"`, `"id":"Worker"`},
        {`"id":"worker"`, `"id":""`},
        {`{"id":"worker","name_key":"worker_name"}`, `{"id":"worker"}`},
        {`"name_key":"worker_name"`, `"name":"Worker"`},
        {`worker_name`, `missing_translation`},
        // Presentation data is no longer part of the role catalog.
        {`"id":"worker",`, `"id":"worker","color":{"r":0,"g":0,"b":0},`},
        {`"id":"worker",`, `"id":"worker","sprite":"assets/sprites/roles/worker.png",`},
        {`"id":"worker"`, `"id":"worker","unexpected":true`},
    }
    for change in changes {
        data, _ := strings.replace_all(roles_fixture, change[0], change[1], allocator)
        _, invalid := decode_roles(transmute([]byte)data, texts, allocator)
        testing.expect(t, invalid != "", change[1])
    }
    for data in ([?]string{"[]", "{}", "null", "[null]", "[", roles_fixture + " {}"}) {
        _, invalid := decode_roles(transmute([]byte)data, texts, allocator)
        testing.expect(t, invalid != "", data)
    }
    texts["worker_name"] = "   "
    _, invalid_text := decode_roles(transmute([]byte)roles_fixture, texts, allocator)
    testing.expect(t, invalid_text != "")
}

@(test)
role_startup_and_building_sprites :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    english :: #load("../../assets/config/default/localization/en.json")
    texts, texts_ok := localization.decode(transmute([]byte)english, allocator)
    testing.expect(t, texts_ok)
    level_path := profile_path(DEFAULT_PROFILE, DEFAULT_LEVEL, allocator)
    catalog, _, ok := load(texts.entries, allocator, level_path)
    testing.expect(t, ok && len(catalog.subject_roles) == 3)
    for building in catalog.buildings { testing.expect(t, valid_sprite_path(building.sprite)) }
    // The role catalog resolves localized names and nothing else: identity metadata
    // only, no color and no sprite.
    for role in catalog.subject_roles { testing.expect(t, role.name != "") }
    role_source :: #load("../../assets/config/default/subject_roles.json")
    with_sprite, _ := strings.replace_all(string(role_source), `"name_key"`, `"sprite":"assets/sprites/roles/worker.png","name_key"`, allocator)
    _, sprite_error := decode_roles(transmute([]byte)with_sprite, texts.entries, allocator)
    testing.expect(t, sprite_error != "", sprite_error)
}

@(test)
sprite_paths_and_building_schema :: proc(t: ^testing.T) {
    for path in ([?]string{"assets/building.png", "assets/sprites/subjects/human.png", "assets/sprites/my building.png"}) {
        testing.expect(t, valid_sprite_path(path), path)
    }
    for path in ([?]string{"", " ", "assets/../worker.png", "assets/./worker.png", "assets//worker.png", "/assets/worker.png", "C:/worker.png", "assets\\worker.png", "https://example.com/worker.png", "worker.png", "assets/worker.jpg", "assets/worker.png ", "assets/a\x00.png"}) {
        testing.expect(t, !valid_sprite_path(path), path)
    }
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture, texts, allocator)
    catalog, error := decode_catalog(transmute([]byte)building_fixture, resources, texts, allocator)
    testing.expect(t, error == "", error)
    if error != "" { return }
    testing.expect(t, catalog.buildings[1].sprite == "assets/sprites/buildings/custom.png")
    for replacement in ([?]string{``, `,"sprite":""`}) {
        data, _ := strings.replace_all(building_fixture, `,"sprite":"assets/sprites/buildings/custom.png"`, replacement, allocator)
        fallback, error := decode_catalog(transmute([]byte)data, resources, texts, allocator)
        testing.expect(t, error == "", error)
        if error == "" { testing.expect(t, fallback.buildings[1].sprite == "") }
    }
    for replacement in ([?]string{`,"sprite":null`, `,"sprite":1`, `,"sprite":"../custom.png"`}) {
        data, _ := strings.replace_all(building_fixture, `,"sprite":"assets/sprites/buildings/custom.png"`, replacement, allocator)
        _, invalid := decode_catalog(transmute([]byte)data, resources, texts, allocator)
        testing.expect(t, strings.contains(invalid, "sprite"), invalid)
    }
}
