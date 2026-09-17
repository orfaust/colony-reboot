package config

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

// A configuration profile is one self-contained set of JSON configuration files.
// Every profile lives in its own directory under CONFIG_ROOT:
//
//     assets/config/<profile>/buildings.json
//     assets/config/<profile>/levels/level_0.json
//     assets/config/<profile>/localization/en.json
//
// Sprites and fonts are shared between profiles because they are assets, not
// configuration: JSON `sprite` fields keep their repository-relative
// `assets/sprites/...` form. Copy a profile directory to create a new one.
Profile :: struct {
    name: string,
}

CONFIG_ROOT :: "assets/config"
DEFAULT_PROFILE_NAME :: "default"
DEFAULT_PROFILE :: Profile{DEFAULT_PROFILE_NAME}
DEFAULT_LEVEL :: "levels/level_0.json"

// Compile-time default profile; the runtime `--config <name>` argument overrides it.
COMPILED_PROFILE_NAME :: #config(CONFIG_PROFILE, DEFAULT_PROFILE_NAME)

// Profiles are directory names, so a name must be one safe path segment: no
// separators, no traversal, no drive letters, and nothing the filesystem would
// normalize away. This keeps a mistyped argument inside CONFIG_ROOT.
valid_profile_name :: proc(name: string) -> bool {
    if len(name) == 0 || len(name) > 64 { return false }
    if name == "." || name == ".." { return false }
    for character in name {
        switch {
        case character >= 'a' && character <= 'z':
        case character >= 'A' && character <= 'Z':
        case character >= '0' && character <= '9':
        case character == '-', character == '_':
        case:
            return false
        }
    }
    return true
}

// Builds "<CONFIG_ROOT>/<profile>/<relative>" with forward slashes. The returned
// string belongs to allocator and must stay alive as long as the path is used.
profile_path :: proc(profile: Profile, relative: string, allocator: mem.Allocator) -> string {
    return fmt.aprintf("%s/%s/%s", CONFIG_ROOT, profile.name, relative, allocator=allocator)
}

// Validates the name and that its directory exists. The error belongs to
// allocator and names both the rejected value and the expected directory.
resolve_profile :: proc(name: string, allocator: mem.Allocator) -> (Profile, string) {
    if !valid_profile_name(name) {
        return {}, fmt.aprintf("invalid configuration profile %q: use 1-64 letters, digits, '-' or '_' (no path separators)", name, allocator=allocator)
    }
    profile := Profile{name}
    directory := fmt.aprintf("%s/%s", CONFIG_ROOT, name, allocator=allocator)
    if !os.is_dir(directory) {
        return {}, fmt.aprintf("configuration profile %q not found: expected the directory %s; copy %s/%s to create one", name, directory, CONFIG_ROOT, DEFAULT_PROFILE_NAME, allocator=allocator)
    }
    return profile, ""
}

// Parses the configuration profile from command-line arguments. Supported forms
// are `--config <name>` and `--config=<name>`; a missing or repeated value is an
// error. `arguments` still contains the executable at index 0.
parse_profile_name :: proc(arguments: []string, allocator: mem.Allocator) -> (name: string, error: string) {
    name = COMPILED_PROFILE_NAME
    if !valid_profile_name(name) {
        return "", fmt.aprintf("the build-time CONFIG_PROFILE default %q is not a valid profile name", name, allocator=allocator)
    }
    found := false
    skip := false
    for argument, i in arguments {
        if i == 0 || skip { skip = false; continue }
        switch {
        case argument == "--reload-smoke":
            // Handled by the development reload entry point; not a profile argument.
        case argument == "--config" || argument == "-config":
            if found { return "", "--config was given more than once" }
            if i+1 >= len(arguments) { return "", "--config requires a profile name, for example: --config test1" }
            name = arguments[i+1]
            found = true
            skip = true
        case strings.has_prefix(argument, "--config=") || strings.has_prefix(argument, "-config="):
            if found { return "", "--config was given more than once" }
            name = argument[strings.index_byte(argument, '=')+1:]
            found = true
        case strings.has_prefix(argument, "-"):
            return "", fmt.aprintf("unknown argument %q; supported arguments are --config <name> and --reload-smoke", argument, allocator=allocator)
        }
    }
    if !valid_profile_name(name) {
        return "", fmt.aprintf("invalid configuration profile %q: use 1-64 letters, digits, '-' or '_' (no path separators)", name, allocator=allocator)
    }
    return name, ""
}
