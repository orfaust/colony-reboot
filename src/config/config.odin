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
    subjects: []logic.Subject_Type,
    subject_roles: []logic.Role,
    ships: []logic.Ship,
    space_stations: []logic.Space_Station, // Immutable initial data, not live session stock.
}
Level :: struct {
    version: int,
    level: int,
    buildings: []logic.Building_Instance,
    subjects: []logic.Subject_Instance,
    space_station: logic.Station_Instance,
}

// Decoded storage belongs to allocator, even on failure; errors are static or
// allocator-owned strings. A Dynamic_Arena must use alignment=64 for JSON maps.
// The application keeps its startup arena alive through session/render shutdown.
// Strict structural validation precedes typed decoding: no missing/unknown fields,
// nulls (outside `config:"nullable"` and Maybe fields), unknown enum names, fractional integers,
// or overflowing RGB channels are silently accepted.
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
        // Fields tagged `config:"one_of"` form one group: exactly one must be present.
        one_of: [dynamic]string
        one_of.allocator = allocator
        one_of_present := 0
        for field in fields {
            child_path := fmt.aprintf("%s.%s", path, field.name, allocator=allocator)
            child, found := object[field.name]
            tag := reflect.struct_tag_get(field.tag, "config")
            optional := tag == "one_of" || tag == "optional"
            if tag == "one_of" {
                append(&one_of, field.name)
                if found { one_of_present += 1 }
            }
            if !found {
                if optional { continue }
                return fail(child_path, "required field is missing", allocator)
            }
            // Optional sprite strings may be explicitly empty to select color rendering.
            if text, is_string := child.(string); tag == "optional" && is_string && text == "" { continue }
            // Fields tagged `config:"nullable"` accept null, which decodes as the zero value.
            if _, is_null := child.(json.Null); is_null && tag == "nullable" { continue }
            if err := shape_error(child, field.type.id, child_path, allocator); err != "" { return err }
        }
        if len(one_of) > 0 && one_of_present != 1 {
            names := strings.join(one_of[:], ", ", allocator)
            return fail(path, fmt.aprintf("exactly one of %s is required", names, allocator=allocator), allocator)
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
    case reflect.Type_Info_Enum:
        // json.unmarshal silently ignores unknown enum names, so they are rejected here.
        text, ok := value.(json.String)
        known := false
        if ok { for name in t.names { if name == text { known = true; break } } }
        if !known {
            names := strings.join(t.names, ", ", allocator)
            return fail(path, fmt.aprintf("expected one of: %s", names, allocator=allocator), allocator)
        }
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
    case reflect.Type_Info_Union:
        // Maybe(T): null decodes as no value; anything else follows the single variant's rules.
        if len(t.variants) != 1 { return fail(path, "unsupported configuration field type", allocator) }
        if _, is_null := value.(json.Null); is_null { return "" }
        return shape_error(value, t.variants[0].id, path, allocator)
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
        if d.sprite != "" && !valid_sprite_path(d.sprite) { return {}, fmt.aprintf("buildings[%d].sprite: expected a normalized assets/.../*.png path using forward slashes, without parent traversal", index, allocator=allocator) }
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
        if d.warmup_time < 0 || d.cooldown_time < 0 {
            return {}, fmt.aprintf("building %q: warmup_time and cooldown_time must be nonnegative hours", d.id, allocator=allocator)
        }
        if d.min_operative_health < 0 || d.min_operative_health > 1 {
            return {}, fmt.aprintf("building %q: min_operative_health must be in [0,1]", d.id, allocator=allocator)
        }
        if d.materials_amount < 0 {
            return {}, fmt.aprintf("building %q: materials_amount must be nonnegative", d.id, allocator=allocator)
        }
        for role, j in d.subject_roles {
            if role.quantity < 0 { return {}, fmt.aprintf("building %q subject_roles[%d].quantity: must be nonnegative", d.id, j, allocator=allocator) }
            for previous in d.subject_roles[:j] {
                if previous.role_id == role.role_id { return {}, fmt.aprintf("building %q subject_roles[%d]: duplicate role_id", d.id, j, allocator=allocator) }
            }
        }
        // Shape validation requires a nonempty type in any non-null residents object.
        if logic.hosts_residents(d) && d.residents.capacity <= 0 {
            return {}, fmt.aprintf("building %q: residents.capacity must be positive", d.id, allocator=allocator)
        }
        // Codes are catalog identifiers, not localization keys.
        keys := [?]string{d.name_key, d.description_key}
        for key in keys { if err := text_error(key, texts, allocator); err != "" { return {}, err } }
        for need, i in d.needs {
            // Shape validation guarantees only one amount is present; the other is zero.
            if max(need.amount_per_unit, need.amount_per_hour, need.amount_per_resident) <= 0 || !resource_exists(catalog.resources, need.resource_id) {
                return {}, fmt.aprintf("building %q needs[%d]: amount_per_unit, amount_per_hour, or amount_per_resident must be positive and resource_id must reference resources.json", d.id, i, allocator=allocator)
            }
            if need.capacity < 0 {
                return {}, fmt.aprintf("building %q needs[%d]: capacity must be nonnegative", d.id, i, allocator=allocator)
            }
            if need.amount_per_resident > 0 && !logic.hosts_residents(d) {
                return {}, fmt.aprintf("building %q needs[%d]: amount_per_resident requires residents", d.id, i, allocator=allocator)
            }
        }
        for product, i in d.produces {
            // Shape validation guarantees only one rate is present; the other is zero.
            if max(product.units_per_hour, product.amount_per_resident) <= 0 || !resource_exists(catalog.resources, product.resource_id) {
                return {}, fmt.aprintf("building %q produces[%d]: units_per_hour or amount_per_resident must be positive and resource_id must reference resources.json", d.id, i, allocator=allocator)
            }
            if product.amount_per_resident > 0 && !logic.hosts_residents(d) {
                return {}, fmt.aprintf("building %q produces[%d]: amount_per_resident requires residents", d.id, i, allocator=allocator)
            }
            if product.capacity < 0 {
                return {}, fmt.aprintf("building %q produces[%d]: capacity must be nonnegative", d.id, i, allocator=allocator)
            }
        }
        for stock, i in d.storage {
            if !resource_exists(catalog.resources, stock.resource_id) || stock.capacity < 0 {
                return {}, fmt.aprintf("building %q storage[%d]: resource_id must reference resources.json and capacity must be nonnegative", d.id, i, allocator=allocator)
            }
            for previous in d.storage[:i] {
                if previous.resource_id == stock.resource_id {
                    return {}, fmt.aprintf("building %q storage[%d]: duplicate resource_id %q", d.id, i, stock.resource_id, allocator=allocator)
                }
            }
        }
    }
    return
}

// Standalone subject type array, which may be empty. Needs reference resources.json by ID.
decode_subjects :: proc(data: []byte, resources: []logic.Resource, texts: map[string]string, allocator: mem.Allocator) -> (subjects: []logic.Subject_Type, error: string) {
    error = parse_typed(data, &subjects, allocator)
    if error != "" { return }
    for subject, i in subjects {
        for previous in subjects[:i] {
            if previous.id == subject.id { return nil, fmt.aprintf("subjects[%d]: duplicate ID %q", i, subject.id, allocator=allocator) }
        }
        if err := text_error(subject.name_key, texts, allocator); err != "" { return nil, err }
        if subject.sprite != "" && !valid_sprite_path(subject.sprite) {
            return nil, fmt.aprintf("subjects[%d].sprite: expected a normalized assets/.../*.png path", i, allocator=allocator)
        }
        if subject.width <= 0 || subject.height <= 0 {
            return nil, fmt.aprintf("subjects[%d]: width and height must be positive world-unit dimensions", i, allocator=allocator)
        }
        for need, j in subject.needs {
            if need.amount_per_hour <= 0 || !resource_exists(resources, need.resource_id) {
                return nil, fmt.aprintf("subject %q needs[%d]: amount_per_hour must be positive and resource_id must reference resources.json", subject.id, j, allocator=allocator)
            }
            if need.shortage_alert_time < 0 {
                return nil, fmt.aprintf("subject %q needs[%d]: shortage_alert_time must be nonnegative hours", subject.id, j, allocator=allocator)
            }
            if need.shortage_max_time < 0 {
                return nil, fmt.aprintf("subject %q needs[%d]: shortage_max_time must be nonnegative hours", subject.id, j, allocator=allocator)
            }
        }
        if subject.rest_time < 0 || subject.work_time < 0 {
            return nil, fmt.aprintf("subject %q: rest_time and work_time must be nonnegative hours", subject.id, allocator=allocator)
        }
        // A null roles decodes as an empty slice: the subject type takes no roles.
        for role, j in subject.roles {
            if role.sprite != "" && !valid_sprite_path(role.sprite) {
                return nil, fmt.aprintf("subjects[%d].roles[%d].sprite: expected a normalized assets/.../*.png path", i, j, allocator=allocator)
            }
            for previous in subject.roles[:j] {
                if previous.role_id == role.role_id { return nil, fmt.aprintf("subject %q: duplicate role %v", subject.id, role, allocator=allocator) }
            }
        }
        for product, j in subject.produces {
            if product.units_per_hour <= 0 || !resource_exists(resources, product.resource_id) {
                return nil, fmt.aprintf("subject %q produces[%d]: units_per_hour must be positive (units per hour) and resource_id must reference resources.json", subject.id, j, allocator=allocator)
            }
        }
    }
    return
}

// Cross-file check, run once buildings and subjects are both decoded: a non-null
// residents.type references a subjects.json ID.
validate_residents :: proc(catalog: Catalog, allocator: mem.Allocator) -> string {
    for building in catalog.buildings {
        if !logic.hosts_residents(building) { continue }
        known := false
        for subject in catalog.subjects { if subject.id == building.residents.type { known = true; break } }
        if !known {
            return fmt.aprintf("building %q residents.type: %q must reference a subject ID in assets/config/subjects.json", building.id, building.residents.type, allocator=allocator)
        }
    }
    return ""
}

@(private)
find_building_instance :: proc(buildings: []logic.Building_Instance, id: string) -> (logic.Building_Instance, bool) {
    for building in buildings { if building.id == id { return building, true } }
    return {}, false
}

@(private)
building_instance_exists :: proc(buildings: []logic.Building_Instance, id: string) -> bool {
    _, found := find_building_instance(buildings, id)
    return found
}

// A building stores each resource it needs, produces, or lists in storage. A resource in
// several lists has one stored entry, bounded by the largest capacity.
@(private)
stock_capacity :: proc(definition: logic.Building_Type, resource_id: string) -> (capacity: f32, found: bool) {
    for need in definition.needs {
        if need.resource_id != resource_id { continue }
        capacity = found ? max(capacity, need.capacity) : need.capacity
        found = true
    }
    for product in definition.produces {
        if product.resource_id != resource_id { continue }
        capacity = found ? max(capacity, product.capacity) : product.capacity
        found = true
    }
    for stock in definition.storage {
        if stock.resource_id != resource_id { continue }
        capacity = found ? max(capacity, stock.capacity) : stock.capacity
        found = true
    }
    return
}

@(private)
has_stock :: proc(stored: []logic.Stored_Resource, resource_id: string) -> bool {
    for stock in stored { if stock.resource_id == resource_id { return true } }
    return false
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
    if err := validate_station_instance(level.space_station, catalog, allocator); err != "" { return {}, err }
    for building, i in level.buildings {
        definition, found := find_building(catalog, building.building_id)
        if !found {
            return {}, fmt.aprintf("buildings[%d]: unknown building_id %q; add its definition to assets/config/buildings.json", i, building.building_id, allocator=allocator)
        }
        if !logic.valid_instance(building) {
            return {}, fmt.aprintf("buildings[%d]: invalid instance; health must be in [0,1]", i, allocator=allocator)
        }
        for stock, j in building.stored {
            for previous in building.stored[:j] {
                if previous.resource_id == stock.resource_id {
                    return {}, fmt.aprintf("buildings[%d].stored[%d]: duplicate resource_id %q", i, j, stock.resource_id, allocator=allocator)
                }
            }
            capacity, stocked := stock_capacity(definition, stock.resource_id)
            if !stocked {
                return {}, fmt.aprintf("buildings[%d].stored[%d]: resource_id %q is not needed, produced, or stored by %q", i, j, stock.resource_id, building.building_id, allocator=allocator)
            }
            if stock.amount < 0 || stock.amount > capacity {
                return {}, fmt.aprintf("buildings[%d].stored[%d].amount: must be in [0, capacity] (%v)", i, j, capacity, allocator=allocator)
            }
        }
        for need in definition.needs {
            if !has_stock(building.stored, need.resource_id) {
                return {}, fmt.aprintf("buildings[%d].stored: missing entry for needed resource %q", i, need.resource_id, allocator=allocator)
            }
        }
        for product in definition.produces {
            if !has_stock(building.stored, product.resource_id) {
                return {}, fmt.aprintf("buildings[%d].stored: missing entry for produced resource %q", i, product.resource_id, allocator=allocator)
            }
        }
        for stock in definition.storage {
            if !has_stock(building.stored, stock.resource_id) {
                return {}, fmt.aprintf("buildings[%d].stored: missing entry for stored resource %q", i, stock.resource_id, allocator=allocator)
            }
        }
        // residents_amount is a number in [0, residents.capacity] exactly when the type has residents.
        residents_amount, has_residents_amount := building.residents_amount.?
        if logic.hosts_residents(definition) {
            if !has_residents_amount {
                return {}, fmt.aprintf("buildings[%d].residents_amount: must be a number because %q has residents", i, building.building_id, allocator=allocator)
            }
            if f64(residents_amount) != math.floor(f64(residents_amount)) {
                return {}, fmt.aprintf("buildings[%d].residents_amount: must be a whole number of subjects", i, allocator=allocator)
            }
            if residents_amount < 0 || residents_amount > definition.residents.capacity {
                return {}, fmt.aprintf("buildings[%d].residents_amount: must be in [0, residents.capacity] (%v)", i, definition.residents.capacity, allocator=allocator)
            }
        } else if has_residents_amount {
            return {}, fmt.aprintf("buildings[%d].residents_amount: must be null because %q has no residents", i, building.building_id, allocator=allocator)
        }
        if definition.always_on && !building.enable_at_start {
            return {}, fmt.aprintf("buildings[%d].enable_at_start: must be true because %q is always_on", i, building.building_id, allocator=allocator)
        }
        // Mirrors logic.toggle: a building below its operative health cannot be activated.
        if building.enable_at_start && building.building_id != c.CONTROL_UNIT_ID && building.health < definition.min_operative_health {
            return {}, fmt.aprintf("buildings[%d]: enable_at_start requires health of at least min_operative_health (%v)", i, definition.min_operative_health, allocator=allocator)
        }
        for previous in level.buildings[:i] {
            if previous.id == building.id { return {}, fmt.aprintf("buildings[%d]: duplicate ID %q", i, building.id, allocator=allocator) }
        }
    }
    for subject, i in level.subjects {
        subject_type: logic.Subject_Type
        type_found := false
        for definition in catalog.subjects { if definition.id == subject.subject_id { subject_type = definition; type_found = true; break } }
        if !type_found {
            return {}, fmt.aprintf("subjects[%d]: unknown subject_id %q; add its definition to assets/config/subjects.json", i, subject.subject_id, allocator=allocator)
        }
        for previous in level.subjects[:i] {
            if previous.id == subject.id { return {}, fmt.aprintf("subjects[%d]: duplicate ID %q", i, subject.id, allocator=allocator) }
        }
        residence, residence_found := find_building_instance(level.buildings, subject.residence)
        if !residence_found {
            return {}, fmt.aprintf("subjects[%d]: residence %q must reference a building instance ID in this level", i, subject.residence, allocator=allocator)
        }
        // Building IDs were resolved above. The residence type must host this subject type
        // (a null residents has an empty type), within residents.capacity per instance.
        host, _ := find_building(catalog, residence.building_id)
        if host.residents.type != subject.subject_id {
            return {}, fmt.aprintf("subjects[%d]: residence %q (%s) cannot host subject type %q; set residents.type", i, subject.residence, residence.building_id, subject.subject_id, allocator=allocator)
        }
        residents := 1
        for previous in level.subjects[:i] { if previous.residence == subject.residence { residents += 1 } }
        if f32(residents) > host.residents.capacity {
            return {}, fmt.aprintf("subjects[%d]: residence %q exceeds its residents.capacity (%v)", i, subject.residence, host.residents.capacity, allocator=allocator)
        }
        // A null occupation decodes as "": the subject is not working anywhere.
        if subject.occupation != "" && !building_instance_exists(level.buildings, subject.occupation) {
            return {}, fmt.aprintf("subjects[%d]: occupation %q must be null or reference a building instance ID in this level", i, subject.occupation, allocator=allocator)
        }
        if subject.speed <= 0 { return {}, fmt.aprintf("subjects[%d]: speed must be positive", i, allocator=allocator) }
        // Instance roles come from the subject type's roles; a type with null roles takes none, so its instances use [].
        if len(subject.roles) == 0 && len(subject_type.roles) > 0 {
            return {}, fmt.aprintf("subjects[%d]: roles must list at least one role of subject type %q", i, subject.subject_id, allocator=allocator)
        }
        for role, j in subject.roles {
            for previous in subject.roles[:j] {
                if previous == role { return {}, fmt.aprintf("subjects[%d]: duplicate role %v", i, role, allocator=allocator) }
            }
            allowed := false
            for type_role in subject_type.roles { if type_role.role_id == role { allowed = true; break } }
            if !allowed {
                return {}, fmt.aprintf("subjects[%d]: role %v is not in the roles of subject type %q", i, role, subject.subject_id, allocator=allocator)
            }
        }
    }
    if logic.initial_subject_count(level.space_station,level.buildings,level.subjects) > logic.SUBJECT_LIMIT {
        return {}, fmt.aprintf("level: initial subjects exceed the runtime limit of %d; reduce station stock or initial residents", logic.SUBJECT_LIMIT, allocator=allocator)
    }
    if logic.initial_balance(level.buildings, catalog.buildings) < 0 {
        return {}, "initial power demand of Control Units and enable_at_start buildings exceeds their output"
    }
    return
}

load :: proc(texts: map[string]string, allocator: mem.Allocator, level_path: string = "assets/levels/level_0.json") -> (Catalog, Level, bool) {
    resources_path :: "assets/config/resources.json"
    resource_data, resource_ok := os.read_entire_file(resources_path)
    if !resource_ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", resources_path); return {}, {}, false }
    defer delete(resource_data)
    resources, resource_error := decode_resources(resource_data, texts, allocator)
    if resource_error != "" { fmt.eprintf("Invalid %s: %s\n", resources_path, resource_error); return {}, {}, false }
    catalog_path :: "assets/config/buildings.json"
    data, ok := os.read_entire_file(catalog_path)
    if !ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", catalog_path); return {}, {}, false }
    defer delete(data)
    catalog, error := decode_catalog(data, resources, texts, allocator)
    if error != "" { fmt.eprintf("Invalid %s: %s\n", catalog_path, error); return {}, {}, false }
    if !load_roles(&catalog, texts, allocator) { return {}, {}, false }
    subjects_path :: "assets/config/subjects.json"
    subject_data, subject_ok := os.read_entire_file(subjects_path)
    if !subject_ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", subjects_path); return {}, {}, false }
    defer delete(subject_data)
    subjects, subject_error := decode_subjects(subject_data, resources, texts, allocator)
    if subject_error != "" { fmt.eprintf("Invalid %s: %s\n", subjects_path, subject_error); return {}, {}, false }
    catalog.subjects = subjects
    if residents_error := validate_residents(catalog, allocator); residents_error != "" {
        fmt.eprintf("Invalid %s: %s\n", catalog_path, residents_error)
        return {}, {}, false
    }
    if !load_space_stations(&catalog, texts, allocator) { return {}, {}, false }
    level_data, level_ok := os.read_entire_file(level_path)
    if !level_ok { fmt.eprintf("Cannot read %s. Run from the repository root.\n", level_path); return {}, {}, false }
    defer delete(level_data)
    level, level_error := decode_level(level_data, catalog, allocator)
    if level_error != "" { fmt.eprintf("Invalid %s: %s\n", level_path, level_error); return {}, {}, false }
    return catalog, level, true
}
