package config

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
subject_dimensions_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture, texts, allocator)
    subjects, error := decode_subjects(transmute([]byte)subject_fixture, resources, texts, allocator)
    testing.expect(t, error == "", error)
    if error != "" { return }
    testing.expect(t, subjects[0].width == 0.5 && subjects[0].height == 1.25)
    for field in ([?]string{"width", "height"}) {
        original := fmt.aprintf("\"%s\":%s", field, field == "width" ? "0.5" : "1.25", allocator=allocator)
        for value in ([?]string{"0", "-1", "1e-100", "1e100", "null", `"2"`, "true", "[]", "{}"}) {
            replacement := fmt.aprintf("\"%s\":%s", field, value, allocator=allocator)
            data, _ := strings.replace_all(subject_fixture, original, replacement, allocator)
            _, err := decode_subjects(transmute([]byte)data, resources, texts, allocator)
            testing.expect(t, strings.contains(err, field), err)
        }
        missing := fmt.aprintf("%s,", original, allocator=allocator)
        data, _ := strings.replace_all(subject_fixture, missing, "", allocator)
        _, err := decode_subjects(transmute([]byte)data, resources, texts, allocator)
        testing.expect(t, strings.contains(err, field), err)
    }
}
