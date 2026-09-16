package config

import "core:mem"
import "core:strings"
import "core:testing"

key_bindings_source :: #load("../../assets/config/key_bindings.json")

key_bindings_fixture :: string(`{"version":1,"menu_up":["key:up"],"menu_down":["key:down"],
"activate":["key:enter","key:space"],"back":["key:escape"],"select":["mouse:left"],
"zoom_in":["wheel:up"],"zoom_out":["wheel:down"],"pan":["mouse:right","mouse:middle"],
"speed_up":["key:e"],"slow_down":["key:q"]}`)

@(test)
key_bindings_validation :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena,alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    _, shipped_error := decode_key_bindings(transmute([]byte)key_bindings_source,allocator)
    testing.expect(t,shipped_error == "",shipped_error)
    bindings, error := decode_key_bindings(transmute([]byte)key_bindings_fixture,allocator)
    testing.expect(t,error == "",error)
    testing.expect(t,len(bindings.pan) == 2 && bindings.pan[1] == "mouse:middle")
    changes := [?][2]string{
        {"\"version\":1","\"version\":2"},
        {"[\"key:up\"]","[]"},
        {"[\"key:up\"]","[\"key:up\",\"key:up\"]"},
        {"[\"key:up\"]","[\"\"]"},
        {"[\"key:up\"]","\"key:up\""},
        {"\"menu_up\"","\"menu_left\""},
        {"\"pan\":[\"mouse:right\",\"mouse:middle\"]","\"pan\":null"},
        {",\"back\":[\"key:escape\"]",""},
        {",\"slow_down\":[\"key:q\"]",""},
    }
    for change in changes {
        modified, _ := strings.replace_all(key_bindings_fixture,change[0],change[1],allocator)
        _, invalid := decode_key_bindings(transmute([]byte)modified,allocator)
        testing.expect(t,invalid != "",change[1])
    }
}
