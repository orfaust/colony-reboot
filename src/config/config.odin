package config

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:strings"
import "../logic"
import c "../contracts"

Catalog :: struct {
    buildings: []logic.Building_Type,
    resources: []logic.Resource,
}
Level :: struct {
    version: int,
    level: int,
    buildings: []logic.Building_Instance,
}

// Decoded storage belongs to allocator, even on failure; errors are static or
// allocator-owned strings. A Dynamic_Arena must use alignment=64 for JSON maps.
// The application keeps its startup arena alive through session/render shutdown.
// Strict structural validation precedes typed decoding: no missing/unknown fields,
// nulls, fractional integers, or overflowing RGB channels are silently accepted.
@(private)
shape_error :: proc(value: json.Value, type: typeid, path: string, allocator: mem.Allocator) -> string {
    fail :: proc(path, reason: string, allocator: mem.Allocator) -> string {
        return fmt.aprintf("%s: %s", path, reason, allocator=allocator)
    }
    info := reflect.type_info_base(type_info_of(type))
    #partial switch t in info.variant {
    case reflect.Type_Info_Struct:
        object, ok := value.(json.Object)
        if !ok { return fail(path, "expected an object", allocator) }
        fields := reflect.struct_fields_zipped(type)
        for field in fields {
            child_path := fmt.aprintf("%s.%s", path, field.name, allocator=allocator)
            child, found := object[field.name]
            if !found { return fail(child_path, "required field is missing", allocator) }
            if err := shape_error(child, field.type.id, child_path, allocator); err != "" { return err }
        }
        for key in object {
            found := false
            for field in fields { if field.name == key { found = true; break } }
            if !found { return fail(path, fmt.aprintf("unknown field %q", key, allocator=allocator), allocator) }
        }
    case reflect.Type_Info_Slice:
        array, ok := value.(json.Array)
        if !ok { return fail(path, "expected an array (use [] for an empty list)", allocator) }
        for child, i in array {
            child_path := fmt.aprintf("%s[%d]", path, i, allocator=allocator)
            if err := shape_error(child, t.elem.id, child_path, allocator); err != "" { return err }
        }
    case reflect.Type_Info_String:
        text, ok := value.(json.String)
        if !ok || strings.trim_space(text) == "" || strings.contains(text, "\x00") {
            return fail(path, "expected a nonempty string without NUL characters", allocator)
        }
    case reflect.Type_Info_Boolean:
        if _, ok := value.(json.Boolean); !ok { return fail(path, "expected true or false", allocator) }
    case reflect.Type_Info_Integer, reflect.Type_Info_Float:
        number, ok := value.(json.Float)
        if !ok || math.is_nan(number) || math.is_inf(number) {
            return fail(path, "expected a finite number", allocator)
        }
        if type == u8 && (number < 0 || number > 255 || math.floor(number) != number) {
            return fail(path, "RGB channel must be an integer in [0,255]", allocator)
        }
        if type == int && (math.floor(number) != number || math.abs(number) > 2147483647) {
            return fail(path, "expected a 32-bit integer", allocator)
        }
        if type == f32 && math.abs(number) > 3.402823466e38 {
            return fail(path, "number exceeds the f32 range", allocator)
        }
    case:
        return fail(path, "unsupported configuration field type", allocator)
    }
    return ""
}

@(private)
parse_typed :: proc(data: []byte, output: ^$T, allocator: mem.Allocator) -> string {
    context.allocator = allocator
    parser := json.make_parser(data, spec=.JSON, allocator=allocator)
    value, err := json.parse_value(&parser)
    if err != .None { return fmt.aprintf("invalid JSON: %v", err, allocator=allocator) }
    defer json.destroy_value(value, allocator)
    if parser.curr_token.kind != .EOF { return "unexpected trailing content after JSON document" }
    if reason := shape_error(value, T, "$", allocator); reason != "" { return reason }
    if err := json.unmarshal(data, output, spec=.JSON, allocator=allocator); err != nil {
        return fmt.aprintf("cannot decode configuration: %v", err, allocator=allocator)
    }
    return ""
}

@(private)
resource_exists :: proc(resources: []logic.Resource, id: string) -> bool {
    for resource in resources { if resource.id == id { return true } }
    return false
}

@(private)
text_error :: proc(key: string, texts: map[string]string, allocator: mem.Allocator) -> string {
    value, ok := texts[key]
    if !ok || strings.trim_space(value) == "" || strings.contains(value, "\x00") {
        return fmt.aprintf("localization key %q is missing or empty in assets/localization/en.json", key, allocator=allocator)
    }
    return ""
}

// Standalone resource array, loaded and validated before building references.
decode_resources :: proc(data: []byte, texts: map[string]string, allocator: mem.Allocator) -> (resources: []logic.Resource, error: string) {
    error = parse_typed(data, &resources, allocator)
    if error != "" { return }
    for resource, i in resources {
        for previous in resources[:i] {
            if previous.id == resource.id { return nil, fmt.aprintf("resources[%d]: duplicate ID %q", i, resource.id, allocator=allocator) }
        }
        keys := [?]string{resource.name_key, resource.description_key, resource.unit_type_key}
        for key in keys { if err := text_error(key, texts, allocator); err != "" { return nil, err } }
    }
    return
}

// Resources borrow the independently validated resources.json storage. Buildings
// are decoded in array order; IDs, not positions, are the stable references.
decode_catalog :: proc(data: []byte, resources: []logic.Resource, texts: map[string]string, allocator: mem.Allocator) -> (catalog: Catalog, error: string) {
    catalog.resources = resources
    error = parse_typed(data, &catalog.buildings, allocator)
    if error != "" { return }
    if len(catalog.buildings) == 0 { return {}, "catalog must define at least one building type" }
    for d, index in catalog.buildings {
        for previous in catalog.buildings[:index] {
            if previous.id == d.id || previous.code == d.code {
                return {}, fmt.aprintf("building %q: id and code must be unique", d.id, allocator=allocator)
            }
        }
        if d.width <= 0 || d.height <= 0 {
            return {}, fmt.aprintf("building %q: width and height must be positive world-unit dimensions", d.id, allocator=allocator)
        }
        if d.power_need_kw < 0 || d.power_output_kw < 0 {
            return {}, fmt.aprintf("building %q: power values must be nonnegative kW", d.id, allocator=allocator)
        }
        // Codes are catalog identifiers, not localization keys.
        keys := [?]string{d.name_key, d.description_key}
        for key in keys { if err := text_error(key, texts, allocator); err != "" { return {}, err } }
        for need, i in d.needs {
            if need.amount_per_unit <= 0 || !resource_exists(catalog.resources, need.resource_id) {
                return {}, fmt.aprintf("building %q needs[%d]: amount_per_unit must be positive and resource_id must reference resources.json", d.id, i, allocator=allocator)
            }
        }
        for product, i in d.produces {
            if product.time_per_unit <= 0 || !resource_exists(catalog.resources, product.resource_id) {
                return {}, fmt.aprintf("building %q produces[%d]: time_per_unit must be positive (hours per unit) and resource_id must reference resources.json", d.id, i, allocator=allocator)
            }
        }
    }
    return
}

find_building :: proc(catalog: Catalog, id: c.Building_Type_ID) -> (logic.Building_Type, bool) {
    for building in catalog.buildings { if building.id == id { return building, true } }
    return {}, false
}

decode_level :: proc(data: []byte, catalog: Catalog, allocator: mem.Allocator) -> (level: Level, error: string) {
    error = parse_typed(data, &level, allocator)
    if error != "" { return }
    if level.version != 1 { return {}, "version: expected 1" }
    if level.level != 0 { return {}, "level: expected 0 for the initial scene" }
    for building, i in level.buildings {
        if _, found := find_building(catalog, building.building_id); !found {
            return {}, fmt.aprintf("buildings[%d]: unknown building_id %q; add its definition to assets/config/buildings.json", i, building.building_id, allocator=allocator)
        }
        if !logic.valid_instance(building) {
            return {}, fmt.aprintf("buildings[%d]: invalid instance; health must be in [0,1]", i, allocator=allocator)
        }
        for previous in level.buildings[:i] {
            if previous.id == building.id { return {}, fmt.aprintf("buildings[%d]: duplicate ID %q", i, building.id, allocator=allocator) }
        }
    }
    if logic.initial_balance(level.buildings, catalog.buildings) < 0 {
        return {}, "initial Control Unit power demand exceeds its output; only Control Units start active"
    }
    return
}

load :: proc(texts: map[string]string, allocator: mem.Allocator) -> (Catalog, Level, bool) {
    resources_path :: "assets/config/resources.json"
    resource_data, resource_ok := os.read_entire_file(resources_path)
    if !resource_ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", resources_path); return {}, {}, false }
    defer delete(resource_data)
    resources, resource_error := decode_resources(resource_data, texts, allocator)
    if resource_error != "" { fmt.eprintf("Invalid %s: %s\n", resources_path, resource_error); return {}, {}, false }
    catalog_path :: "assets/config/buildings.json"
    level_path :: "assets/levels/level_0.json"
    data, ok := os.read_entire_file(catalog_path)
    if !ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", catalog_path); return {}, {}, false }
    defer delete(data)
    catalog, error := decode_catalog(data, resources, texts, allocator)
    if error != "" { fmt.eprintf("Invalid %s: %s\n", catalog_path, error); return {}, {}, false }
    level_data, level_ok := os.read_entire_file(level_path)
    if !level_ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", level_path); return {}, {}, false }
    defer delete(level_data)
    level, level_error := decode_level(level_data, catalog, allocator)
    if level_error != "" { fmt.eprintf("Invalid %s: %s\n", level_path, level_error); return {}, {}, false }
    return catalog, level, true
}
