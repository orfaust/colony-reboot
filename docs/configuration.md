# Building, Resource, and Level Configuration

The application reads four JSON files once at startup, before opening the window.
Run from the repository root. Restart after editing; Play resets the loaded level
without rereading files. Data changes do not require rebuilding the executable.

1. `assets/localization/en.json`: names, descriptions, units, UI text, and power formats.
2. `assets/config/resources.json`: standalone array of resource definitions.
3. `assets/config/buildings.json`: standalone array of building type definitions.
4. `assets/levels/level_0.json`: versioned level object with its instance array.

## Buildings

`buildings.json` is a nonempty array. There are no root keys or version wrapper:

```json
[
  {
    "id": "control_unit",
    "name_key": "building_control_unit_name",
    "description_key": "building_control_unit_description",
    "code": "CU",
    "width": 1.5,
    "height": 1.5,
    "color": { "r": 0, "g": 86, "b": 179 },
    "power_need_kw": 0,
    "power_output_kw": 0,
    "needs": [],
    "produces": []
  }
]
```

All fields are required. `id` is a stable case-sensitive type identifier. Use
lowercase snake_case, including the reserved `control_unit` ID used by the always-on
CU rules. Both IDs and codes must be nonempty and unique across the building array.
Array order is preserved by the loader, but references use IDs, never array indices.
Changing a type ID requires updating its level references as well.

- `code` is displayed verbatim, without a translation entry. It is not an instance ID.
- `name_key` and `description_key` reference nonempty English localization strings.
- `width` and `height` are finite positive world units, centered on instance position.
  At the current scale of 64 screen units/world unit, 1.5×1.5 becomes 96×96.
- RGB channels are integers in [0,255].
- Power values are finite, nonnegative kW. Active instances produce/consume these
  values; see [Power and Activity](power.md).
- `needs` and `produces` store validated resource recipe metadata. Resource production,
  inventories, and multi-output recipe execution are not implemented yet.

The shipped definitions are `control_unit`, `solar_panel`, `robots_warehouse`,
`water_collector`, `green_house`, and `meals_factory`. Adding a definition does not
place an instance in the world. Add a level instance with its `building_id` to do so.

## Resources

`resources.json` is a separate array, which may be empty if no recipes need resources:

```json
[
  {
    "id": "water",
    "name_key": "resource_water_name",
    "description_key": "resource_water_description",
    "unit_type_key": "unit_l",
    "color": { "r": 0, "g": 179, "b": 255 }
  }
]
```

Resource IDs must be unique and all three text keys must exist in `en.json`.
The shipped resources are `water`, `vegetables`, and `meals`. Buildings reference
these IDs through `resource_id`, case-sensitively:

```json
"needs": [{ "resource_id": "water", "amount_per_unit": 3 }],
"produces": [{ "resource_id": "vegetables", "time_per_unit": 6 }]
```

`amount_per_unit` is required resource units per produced unit. `time_per_unit` is
**hours per unit**, not seconds or units per hour. Both values must be finite and
strictly positive. Water Collector's 50 L/hour is `time_per_unit: 0.02`; Greenhouse
uses 3 L per kg of vegetables and takes 6 hours/kg.

## Level 0

The level keeps its `version: 1` and `level: 0` fields. Its instance `id` is distinct
from the building type identifier:

```json
{
  "version": 1,
  "level": 0,
  "buildings": [
    {
      "id": "CU1",
      "building_id": "control_unit",
      "position": { "x": 0, "y": 0 },
      "health": 1,
      "repairing": false
    },
    {
      "id": "SP1",
      "building_id": "solar_panel",
      "position": { "x": 3, "y": 0 },
      "health": 1,
      "repairing": false
    }
  ]
}
```

All fields are required. Instance IDs must be unique within a level, `building_id`
must exist in the building array, positions must be finite, and health must be in
[0,1]. An empty level is valid. Activity is runtime state: only `control_unit`
instances start active and they cannot be disabled. An initial CU-only power
deficit is rejected before the window opens.

Instances are copied and drawn in level-array order. Overlaps are allowed; clicking
selects the last-drawn building at that point, unless the notice panel consumes it.
The world origin is the viewport center, X right, Y down, at 64 screen units per
world unit. Rectangles have a center pivot, with code and power values fitted inside.
Resizing changes the viewport origin, not world positions. There is no automatic
layout, camera movement, or gameplay collision yet.

## Migration from the previous object catalog

- Move the old root `resources` array to `assets/config/resources.json`.
- Replace the remaining keyed definitions with an array, dropping root `version`.
- Rename each definition's `kind` to `id`; remove the redundant outer key.
- In every level, rename `kind` to `building_id`; preserve the instance's own `id`.
- Ensure both sides use the same case, e.g. `control_unit`, not `Control_Unit`.
- The old object format and legacy `kind` fields are rejected; there is no silent
  compatibility fallback. Catalog arrays currently have no schema-version field;
  the level format still requires version 1.
- Older recipes must use `amount_per_unit` and `time_per_unit`. Divide seconds by
  3600 or invert an hourly rate when migrating; do not merely rename seconds to hours.

Existing dimensions, colors, powers, recipes, resource data, instance IDs, and
positions are preserved by this migration. The optional [asset manager](../manage/README.md)
uses separate editors for the two array files and resolves level references by ID.

## Validation and ownership

Missing files, invalid JSON, duplicate JSON keys, trailing data, nulls, missing or
unknown fields, invalid numeric ranges, duplicate IDs/codes, and broken text or
resource/type references produce file-specific startup diagnostics. No hardcoded
fallback is used. Resources load before buildings so cross-file references can be
checked; the in-memory `Catalog` borrows the validated resource array.

All decoded arrays and strings, including partial allocations on failure, belong
to the supplied startup allocator. Errors are static or allocator-owned strings.
Initialize `Dynamic_Arena` with `alignment=64` on the documented Odin toolchain for
JSON map alignment. The application frees the arena on failure or after window
shutdown. There is no file I/O or JSON parsing in the frame loop.

Logic copies instance arrays into session storage and borrows immutable IDs from
configuration. Reset preserves the template and allocates nothing. Snapshots and
commands use stable instance/type IDs; the renderer retains no frame-temporary data.
See [Power](power.md) for command ordering, notices, and simulation timing boundaries.
