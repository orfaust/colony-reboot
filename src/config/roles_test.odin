package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../logic"
import "../localization"

roles_fixture :: string(`[
{"id":"worker","name_key":"worker_name","color":{"r":0,"g":128,"b":255},"sprite":"assets/sprites/roles/worker.png"},
{"id":"supervisor","name_key":"supervisor_name","color":{"r":255,"g":128,"b":0},"sprite":"assets/sprites/roles/supervisor.png"},
{"id":"repairer","name_key":"repairer_name","color":{"r":0,"g":255,"b":128},"sprite":"assets/sprites/roles/repairer.png"}
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
        testing.expect(t, found && role.name != "" && valid_sprite_path(role.sprite))
    }
    testing.expect(t, roles[0].id == "worker" && roles[0].name == "Worker")
    testing.expect(t, roles[0].color.r == 0 && roles[0].color.g == 128 && roles[0].color.b == 255)
    testing.expect(t, roles[0].sprite == "assets/sprites/roles/worker.png")
    _, found := logic.find_role(roles, "unknown")
    testing.expect(t, !found)
    changes := [?][2]string{
        {`"id":"worker"`, `"id":"supervisor"`},
        {`"id":"worker"`, `"id":"Worker"`},
        {`"id":"worker"`, `"id":""`},
        {`"name_key":"worker_name",`, ``},
        {`"name_key":"worker_name"`, `"name":"Worker"`},
        {`worker_name`, `missing_translation`},
        {`"r":0`, `"r":-1`}, {`"b":255`, `"b":256`}, {`"g":128`, `"g":0.5`},
        {`"sprite":"assets/sprites/roles/worker.png"`, `"sprite":null`},
        {`"sprite":"assets/sprites/roles/worker.png"`, `"sprite":12`},
        {`assets/sprites/roles/worker.png`, `assets/../worker.png`},
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
    for replacement in ([?]string{``, `,"sprite":""`}) {
        data, _ := strings.replace_all(roles_fixture, `,"sprite":"assets/sprites/roles/worker.png"`, replacement, allocator)
        fallback, error := decode_roles(transmute([]byte)data, texts, allocator)
        testing.expect(t, error == "", error)
        if error == "" { testing.expect(t, fallback[0].sprite == "") }
    }
    texts["worker_name"] = "   "
    _, invalid_text := decode_roles(transmute([]byte)roles_fixture, texts, allocator)
    testing.expect(t, invalid_text != "")
}

@(test)
role_startup_and_sprite_metadata_only :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    english :: #load("../../assets/localization/en.json")
    texts, texts_ok := localization.decode(transmute([]byte)english, allocator)
    testing.expect(t, texts_ok)
    catalog, _, ok := load(texts.entries, allocator)
    testing.expect(t, ok && len(catalog.subject_roles) == 3)
    for building in catalog.buildings { testing.expect(t, valid_sprite_path(building.sprite)) }
    // Decoding stays filesystem-independent. tools/build.py rejects this missing file.
    roles_source :: #load("../../assets/config/subject_roles.json")
    missing_file, _ := strings.replace_all(string(roles_source), "assets/sprites/roles/worker.png", "assets/sprites/not-created-by-this-task.png", allocator)
    roles, error := decode_roles(transmute([]byte)missing_file, texts.entries, allocator)
    testing.expect(t, error == "", error)
    if error == "" { testing.expect(t, roles[0].sprite == "assets/sprites/not-created-by-this-task.png") }
}

@(test)
sprite_paths_and_building_schema :: proc(t: ^testing.T) {
    for path in ([?]string{"assets/building.png", "assets/sprites/roles/worker.png", "assets/sprites/my building.png"}) {
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
