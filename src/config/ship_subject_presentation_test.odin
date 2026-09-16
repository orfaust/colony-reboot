package config

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
ship_dimensions_and_optional_catalog_sprites :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    texts["ship_shuttle_name"] = "Shuttle"
    resources, _ := decode_resources(transmute([]byte)resource_fixture, texts, allocator)
    ships, error := decode_ships(transmute([]byte)ships_fixture, nil, texts, allocator)
    testing.expect(t, error == "", error)
    if error != "" { return }
    testing.expect(t, ships[0].width == 2.5 && ships[0].height == 1.25 && ships[0].sprite == "")
    subjects, subject_error := decode_subjects(transmute([]byte)subject_fixture, resources, texts, allocator)
    testing.expect(t, subject_error == "", subject_error)
    if subject_error != "" { return }
    testing.expect(t, subjects[0].sprite == "")
    for path in ([?]string{"", "assets/sprites/example.png"}) {
        field := fmt.aprintf("\"sprite\":%q,\"id\":", path, allocator=allocator)
        ship_data, _ := strings.replace_all(ships_fixture, `"id":`, field, allocator)
        decoded, err := decode_ships(transmute([]byte)ship_data, nil, texts, allocator)
        testing.expect(t, err == "", err)
        if err == "" { testing.expect(t, decoded[0].sprite == path) }
        subject_data, _ := strings.replace_all(subject_fixture, `"id":`, field, allocator)
        decoded_subjects, sub_err := decode_subjects(transmute([]byte)subject_data, resources, texts, allocator)
        testing.expect(t, sub_err == "", sub_err)
        if sub_err == "" { testing.expect(t, decoded_subjects[0].sprite == path) }
    }
    for value in ([?]string{`null`, `42`, `" "`, `"../bad.png"`, `"/assets/bad.png"`, `"assets/bad.jpg"`, `"assets/../bad.png"`, `"assets\\bad.png"`}) {
        field := fmt.aprintf("\"sprite\":%s,\"id\":", value, allocator=allocator)
        ship_data, _ := strings.replace_all(ships_fixture, `"id":`, field, allocator)
        _, err := decode_ships(transmute([]byte)ship_data, nil, texts, allocator)
        testing.expect(t, strings.contains(err, "sprite"), err)
        subject_data, _ := strings.replace_all(subject_fixture, `"id":`, field, allocator)
        _, sub_err := decode_subjects(transmute([]byte)subject_data, resources, texts, allocator)
        testing.expect(t, strings.contains(sub_err, "sprite"), sub_err)
    }
    for field in ([?]string{"width", "height"}) {
        original := fmt.aprintf("\"%s\":%s", field, field == "width" ? "2.5" : "1.25", allocator=allocator)
        for value in ([?]string{"0", "-1", "1e-100", "1e100", "null", `"2"`}) {
            replacement := fmt.aprintf("\"%s\":%s", field, value, allocator=allocator)
            data, _ := strings.replace_all(ships_fixture, original, replacement, allocator)
            _, err := decode_ships(transmute([]byte)data, nil, texts, allocator)
            testing.expect(t, err != "", value)
        }
        missing := fmt.aprintf("%s,", original, allocator=allocator)
        data, _ := strings.replace_all(ships_fixture, missing, "", allocator)
        _, err := decode_ships(transmute([]byte)data, nil, texts, allocator)
        testing.expect(t, strings.contains(err, field), err)
    }
}
