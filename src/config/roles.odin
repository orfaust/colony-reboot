package config

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "../logic"
import c "../contracts"

@(private)
Role_Data :: struct {
    id, name_key: string,
    color: c.RGB,
    sprite: string `config:"optional"`,
}

// Nonempty path syntax only. tools/build.py validates existence and PNG contents
// before invoking Odin; render checks GPU loading at startup. Empty paths opt out.
valid_sprite_path :: proc(path: string) -> bool {
    if !strings.has_prefix(path, "assets/") || !strings.has_suffix(path, ".png") ||
        strings.trim_space(path) != path || strings.contains(path, "\\") ||
        strings.contains(path, ":") || strings.contains(path, "\x00") { return false }
    remaining := path
    for segment in strings.split_iterator(&remaining, "/") {
        if segment == "" || segment == "." || segment == ".." { return false }
    }
    return true
}

// Definitions and errors belong to allocator, including partial results on failure.
// Resolved names borrow texts. Exactly one entry per supported simulation role is
// required, so every existing subject role has validated presentation metadata.
decode_roles :: proc(data: []byte, texts: map[string]string, allocator: mem.Allocator) -> (roles: []logic.Role, error: string) {
    definitions: []Role_Data
    error = parse_typed(data, &definitions, allocator)
    if error != "" { return }
    roles = make([]logic.Role, len(definitions), allocator)
    for definition, i in definitions {
        known := false
        for job in logic.Subject_Role { if logic.subject_role_id(job) == definition.id { known = true; break } }
        if !known { return nil, fmt.aprintf("subject_roles[%d]: unknown role ID %q; supported IDs: worker, supervisor, repairer", i, definition.id, allocator=allocator) }
        for previous in definitions[:i] {
            if previous.id == definition.id { return nil, fmt.aprintf("subject_roles[%d]: duplicate ID %q", i, definition.id, allocator=allocator) }
        }
        if err := text_error(definition.name_key, texts, allocator); err != "" { return nil, err }
        if definition.sprite != "" && !valid_sprite_path(definition.sprite) { return nil, fmt.aprintf("subject_roles[%d].sprite: expected a normalized assets/.../*.png path using forward slashes, without parent traversal", i, allocator=allocator) }
        roles[i] = {id=definition.id, name=texts[definition.name_key], color=definition.color, sprite=definition.sprite}
    }
    for job in logic.Subject_Role {
        id := logic.subject_role_id(job)
        if _, found := logic.find_role(roles, id); !found {
            return nil, fmt.aprintf("subject_roles: missing required role %q", id, allocator=allocator)
        }
    }
    return
}

@(private)
load_roles :: proc(catalog: ^Catalog, texts: map[string]string, allocator: mem.Allocator) -> bool {
    path :: "assets/config/subject_roles.json"
    data, ok := os.read_entire_file(path)
    if !ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", path); return false }
    defer delete(data)
    roles, error := decode_roles(data, texts, allocator)
    if error != "" { fmt.eprintf("Invalid %s: %s\n", path, error); return false }
    catalog.subject_roles = roles
    return true
}
