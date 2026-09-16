package config

import "core:mem"
import "core:strings"
import "core:testing"

@(test)
subject_role_objects_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    texts := test_texts(allocator)
    resources, _ := decode_resources(transmute([]byte)resource_fixture, texts, allocator)
    original :: `{"role_id":"worker","sprite":""}`
    for replacement in ([?]string{`{"role_id":"worker"}`, `{"role_id":"worker","sprite":"assets/roles/human.png"}`}) {
        data, _ := strings.replace_all(subject_fixture, original, replacement, allocator)
        decoded, err := decode_subjects(transmute([]byte)data,resources,texts,allocator)
        testing.expect(t, err == "", err)
        if err == "" { testing.expect(t, decoded[0].roles[0].role_id == .worker) }
    }
    for replacement in ([?]string{`"worker"`, `null`, `{}`, `{"role_id":"unknown"}`, `{"role_id":"worker","sprite":null}`, `{"role_id":"worker","sprite":42}`, `{"role_id":"worker","sprite":"../bad.png"}`, `{"role_id":"worker","extra":1}`}) {
        data, _ := strings.replace_all(subject_fixture, original, replacement, allocator)
        _, err := decode_subjects(transmute([]byte)data,resources,texts,allocator)
        testing.expect(t, strings.contains(err,"roles"), err)
    }
}
