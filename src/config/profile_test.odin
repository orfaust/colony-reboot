package config

import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
profile_name_validation :: proc(t: ^testing.T) {
    for valid in ([?]string{"default", "test1", "test-1", "A_b9"}) {
        testing.expectf(t, valid_profile_name(valid), "%q should be accepted", valid)
    }
    // Anything that could escape CONFIG_ROOT, or that a filesystem would normalize,
    // is rejected before it reaches a path.
    for invalid in ([?]string{"", ".", "..", "nested/profile", "nested\\profile", "/absolute", "C:drive", "with space", "semi;colon", "dot.dot", "\x00"}) {
        testing.expectf(t, !valid_profile_name(invalid), "%q should be rejected", invalid)
    }
    long := strings.repeat("a", 65, context.temp_allocator)
    testing.expect(t, !valid_profile_name(long))
}

@(test)
profile_paths_and_resolution :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    profile := Profile{"default"}
    testing.expect(t, profile_path(profile, "buildings.json", allocator) == "assets/config/default/buildings.json")
    testing.expect(t, profile_path(profile, DEFAULT_LEVEL, allocator) == "assets/config/default/levels/level_0.json")
    testing.expect(t, profile_path(profile, "localization/en.json", allocator) == "assets/config/default/localization/en.json")
    // The shipped default profile resolves; the level it points at exists on disk.
    resolved, error := resolve_profile(DEFAULT_PROFILE_NAME, allocator)
    testing.expectf(t, error == "", error)
    testing.expect(t, resolved == DEFAULT_PROFILE)
    testing.expect(t, os.exists(profile_path(profile, DEFAULT_LEVEL, allocator)))
    _, missing_error := resolve_profile("no-such-profile", allocator)
    testing.expect(t, strings.contains(missing_error, "assets/config/no-such-profile"), missing_error)
    _, invalid_error := resolve_profile("bad/name", allocator)
    testing.expect(t, strings.contains(invalid_error, "invalid configuration profile"), invalid_error)
}

@(test)
profile_arguments :: proc(t: ^testing.T) {
    arena: mem.Dynamic_Arena
    mem.dynamic_arena_init(&arena, alignment=64)
    defer mem.dynamic_arena_destroy(&arena)
    allocator := mem.dynamic_arena_allocator(&arena)
    args := [][]string{
        {"game.exe"},
        {"game.exe", "--config", "test1"},
        {"game.exe", "--config=test1"},
        {"game.exe", "-config", "test1"},
        {"game.exe", "--reload-smoke", "--config", "test1"},
    }
    expected := [?]string{DEFAULT_PROFILE_NAME, "test1", "test1", "test1", "test1"}
    for arguments, i in args {
        name, error := parse_profile_name(arguments, allocator)
        testing.expectf(t, error == "" && name == expected[i], "args %v gave %q / %q", arguments, name, error)
    }
    failures := [][]string{
        {"game.exe", "--config"},
        {"game.exe", "--config", "test1", "--config", "test2"},
        {"game.exe", "--config", "bad/name"},
        {"game.exe", "--config="},
        {"game.exe", "--unknown"},
    }
    for arguments in failures {
        name, error := parse_profile_name(arguments, allocator)
        testing.expectf(t, error != "" && name == "", "args %v should fail, gave %q", arguments, name)
    }
}
