package localization

import "core:testing"
import "core:mem"
import "core:strings"

@(test)
inspector_text_is_required_and_validated :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    text, ok := decode(transmute([]byte)#load("../../assets/config/default/localization/en.json"), allocator)
    testing.expect(t, ok)
    for key in INSPECTOR_LABEL_KEYS {
        original := text.entries[key]
        text.entries[key] = ""
        testing.expect(t, !validate_inspector_text(text.entries), key)
        text.entries[key] = original
    }
    for format in INSPECTOR_FORMATS {
        original := text.entries[format.key]
        for token in format.tokens {
            text.entries[format.key], _ = strings.replace_all(original, token, "", allocator)
            testing.expect(t, !validate_inspector_text(text.entries), format.key)
        }
        text.entries[format.key] = original
    }
    testing.expect(t, validate_inspector_text(text.entries))
}
