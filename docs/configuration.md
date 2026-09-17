# Building, Resource, and Level Configuration

The application reads nine JSON files from one configuration version once at startup,
before opening the window. Run from the repository root. The shipped version is
`default`, so the paths below are `assets/config/default/...`; select another one
with `--config <name>` (or `-define:CONFIG_PROFILE=<name>`) as described in
[Configuration versions](../README.md#configuration-versions). Restart after editing;
Play resets the loaded level without rereading files. Data changes do not require
rebuilding the executable. Development runs can instead use transactional **Ctrl+R**
reload; see [Development reload](development-reload.md) for the explicit compiler
flag, validation and rollback/lifetime contract. Bare `odin run` and debug builds do
not enable it.

1. `assets/config/default/localization/en.json`: names, descriptions, units, UI text, and power formats.
2. `assets/config/default/resources.json`: standalone array of resource definitions.
3. `assets/config/default/buildings.json`: standalone array of building type definitions.
4. `assets/config/default/levels/level_0.json`: versioned level object with its instance array.
5. `assets/config/default/key_bindings.json`: versioned object mapping actions to inputs.
6. `assets/config/default/subjects.json`: standalone array of subject type definitions, including optional `sprite` paths and required positive pixel `width`/`height`.
7. `assets/config/default/ships.json`: ship array (`id`, `code`, optional `sprite`, positive pixel `width`/`height`, RGB `color`, localized `name_key`, `type` (`transport` or `emergency`), `max_speed` (km/h), `max_speed_hours` (acceleration/braking hours along a non-linear jerk-limited S-curve; zero means instantaneous), `units_per_hour` (cargo units loaded/unloaded per simulated hour), `subjects: [{ subject_id, capacity }]`). Ramp hours and throughput are required finite nonnegative floats; zero ramp is instantaneous, but zero throughput disables dispatch.
8. `assets/config/default/space_stations.json`: station IDs, display codes, names, resource/subject capacities and ship counts.
9. `assets/config/default/subject_roles.json`: localized names for all three supported subject roles. It carries no color or sprite. Loaded before subject types.

See [Role Metadata and Sprite Paths](roles-and-sprites.md) for the role contract and
optional `building.sprite`, `subject.sprite` and `subject.roles[].sprite` paths.
Absent/empty sprite strings preserve
color rendering; nonempty paths must refer to existing supported PNGs. Run
`python tools/build.py` to validate them before compilation (direct Odin commands
only validate code). Startup caches textures and rejects load failures.

See [Ships and Space Station](space_station.md) for the two new schemas. Ships load
before the station; resource and subject catalogs must already be validated.

See [Ship and Subject Presentation Metadata](ship-subject-presentation.md) for the
new data-only fields and ship/subject-type dimension migration.

## Buildings

`buildings.json` is a nonempty array. There are no root keys or version wrapper:

```json
[
  {
    "id": "control_unit",
    "sprite": "assets/sprites/buildings/control_unit.png",
    "name_key": "building_control_unit_name",
    "description_key": "building_control_unit_description",
    "code": "CU",
    "width": 64,
    "height": 64,
    "color": { "r": 0, "g": 86, "b": 179 },
    "power_need_kw": 0,
    "power_output_kw": 0,
    "always_on": true,
    "warmup_time": 0,
    "cooldown_time": 0,
    "min_operative_health": 0,
    "materials_amount": 0,
    "subject_roles": [
      { "role_id": "supervisor", "quantity": 0, "staffing_mode": "continuous" },
      { "role_id": "worker", "quantity": 0, "staffing_mode": "continuous" },
      { "role_id": "repairer", "quantity": 0, "staffing_mode": "on_demand" }
    ],
    "residents": null,
    "needs": [],
    "produces": [],
    "storage": []
  }
]
```

All fields are required. `id` is a stable case-sensitive type identifier. Use
lowercase snake_case, including the reserved `control_unit` ID used by the always-on
CU rules. Both IDs and codes must be nonempty and unique across the building array.
Array order is preserved by the loader, but references use IDs, never array indices.
Changing a type ID requires updating its level references as well.

- `code` is displayed verbatim, without a translation entry. It is a short label
  drawn on the building, not an instance ID and no longer a notice identity: building
  notices name the localized `name_key` text plus the level instance ID.
- `name_key` and `description_key` reference nonempty English localization strings.
- `width` and `height` are finite positive pixel dimensions at 100% zoom, scaled by
  the camera zoom and centered on the instance position. The catalog default is
  64×64, i.e. one world unit (64 screen pixels per world unit). This replaced the
  former world-unit sizes: multiply an existing value by 64 when migrating custom
  data (`1.5` becomes `96`). Building, subject-type and ship dimensions all use
  pixels; world positions and simulation rates are unchanged.
- RGB channels are integers in [0,255].
- Power values are finite, nonnegative kW, and mutually exclusive: `power_need_kw`
  and `power_output_kw` cannot both be positive, so a type is either a generator or a
  consumer. Active instances produce or consume these values; see
  [Power and Activity](power.md). Automatic load shedding only ever stops consumers.
- `warmup_time` is the simulated hours a building takes after activation to reach full
  production; `cooldown_time` is the hours it takes after deactivation to stop producing.
  Power output changes linearly meanwhile (shown by a yellow bar); consumption is
  constant and follows activity immediately. Both are finite, nonnegative
  hours; use `0` for an immediate transition. See [Warmup and Cooldown](power.md#warmup-and-cooldown).
- `always_on` (`true` or `false`) marks building types that must never be switched off.
  Logic rejects shutdown with `Always_On_Locked`, leaving activity, progress and power
  unchanged. The UI shows a localized notice. The Control Unit retains its dedicated
  lock regardless of this flag. Level instances of an `always_on` type must set
  `enable_at_start: true`, and the type must have `power_need_kw == 0` because it can
  never be stopped. Changes take effect on restart or successful development reload.
- `min_operative_health`, in [0,1], is the minimum instance `health` needed to activate
  the building. Activation below it is refused; health does not bypass shutdown locks.
- `materials_amount` is the material units needed to build and to repair the building.
- `subject_roles` is a required array of `{role_id, quantity, staffing_mode}` objects.
  IDs are unique supported jobs; `quantity` is a nonnegative integer slot count (fractions
  are rejected); `staffing_mode` is `continuous` or `on_demand`. Empty arrays are valid.
  Continuous coverage gates the building's power output while it stays enabled; the
  inspector displays live `covered/required` coverage, scheduled `arriving`
  replacements, uncovered continuous slots and on-demand quantities, and lists the
  associated individuals with health, phase, role, assignment, timers and needs (see
  [Building staffing](building-staffing.md)). `on_demand` entries still create no
  automatic slot or request. Legacy staffing scalar fields and the former `required`
  boolean are rejected. See [Building staffing](building-staffing.md).
- `residents` is `null` when the building hosts no subjects, or an object such as
  `{ "type": "human", "capacity": 24 }`: `type` is a subject type ID from `subjects.json`
  and `capacity` (finite, strictly positive) how many subjects of that type it hosts.
  Level subjects' `residence` must respect it (see Level 0). The former `host_type` and
  `host_amount` fields are rejected. `residents_amount` remains the housing assignment;
  per-capita consumption is modelled only by subject needs, not by a building rate.
- Materials are finite and nonnegative; staffing quantities are nonnegative integers.
  Construction and repair are not simulated yet; staffing quantities now drive the
  runtime continuous-slot model (see [Building staffing](building-staffing.md)).
- `needs` and `produces` store validated resource recipe metadata that the simulation
  now executes. Once per whole simulated hour, an operational building runs its whole
  recipe or none of it: every input must be available (`stored >= consumed`) and every
  output must fit after those inputs are applied (`stored - consumed + produced <=
  capacity`). Each product yields `units_per_hour`; each need consumes `amount_per_hour`,
  or `amount_per_unit` scaled by the first `produces` entry, the **reference product**.
  Reordering `produces` therefore changes which product defines the per-unit ratios, so
  the intended product stays first. A need that uses `amount_per_unit` is rejected when
  the first product has no positive `units_per_hour`. The obsolete `amount_per_resident`
  building rate was removed from the schema and is rejected as an unknown field; the
  only per-capita consumption is the subject need wired by `step_need_fulfillment`. See
  [Building production](building-production.md).
- `storage` lists resources the building can hold beyond its needs and products, as
  `{ "resource_id": "materials", "capacity": 500 }` entries (`[]` for none). Each
  `resource_id` must exist in `resources.json` and appear once; `capacity` is finite and
  nonnegative. Level instances keep a `stored` entry for these resources too.

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
"needs": [{ "resource_id": "water", "amount_per_unit": 3, "capacity": 30 }],
"produces": [{ "resource_id": "vegetables", "units_per_hour": 0.16667, "capacity": 50 }]
```

Each need specifies exactly one amount: `amount_per_unit` (resource units per produced
unit) or `amount_per_hour` (resource units consumed per hour of operation).
Specifying more than one, or none, is
rejected. Each building product specifies exactly one rate: `units_per_hour`, resource
units produced per hour. All amounts and rates must be finite
and strictly positive. Water Collector's 50 L/hour is `units_per_hour: 50`; Greenhouse uses
3 L per kg of vegetables and grows 1 kg every 6 hours (`units_per_hour: 0.16667`).
The former building `amount_per_resident` rate (needs and products) is rejected as an
unknown field: per-capita consumption lives only in subject needs.

Each building need and product has a nonnegative `capacity`, the units of that resource
the building can hold. Stock belongs to each level building instance, whose required
`stored` array contains exactly one `{ "resource_id": "vegetables", "amount": 0 }`
entry per resource the type needs, produces, or lists in `storage` (or `[]` when there
are none). A resource that appears in several of those lists has a single entry, bounded
by the largest of their capacities. Amounts must be finite and in [0, `capacity`];
duplicates and resources the type does not need, produce, or store are rejected.
Neither building nor subject products accept `stored`.
Instance storage is borrowed immutable level metadata: it seeds the session's owned,
mutable runtime stock table (`logic.State.stock`) and restores it on reset. The hourly
production step changes amounts at whole simulated hour boundaries. The level storage
must outlive the session. The runtime
table resolves one entry per distinct resource in need/product/storage order, bounded
by the largest capacity; `logic.STOCK_ENTRY_LIMIT` (1024) bounds the whole level and a
larger resolved table is rejected at startup.

## Subjects

`subjects.json` is a separate array of subject types (for example colonists or robots).
It may be empty:

```json
[
  {
    "id": "human",
    "name_key": "subject_human_name",
    "color": { "r": 199, "g": 106, "b": 0 },
    "rest_time": 8,
    "work_time": 10,
    "extra_work_time": 4,
    "min_work_health": 0.4,
    "min_colony_health": 0.1,
    "health_rates": {
      "work_gain_per_hour": 0.002,
      "rest_gain_per_hour": 0.01,
      "extra_work_loss_per_hour": 0.025,
      "max_inactivity_loss_per_hour": 0.012,
      "inactivity_max_time": 72,
      "station_recovery_per_hour": 0.04
    },
    "width": 1,
    "height": 1,
    "roles": [{ "role_id": "worker", "sprite": "" }, { "role_id": "repairer", "sprite": "" }],
    "needs": [{
      "resource_id": "meals",
      "amount_per_hour": 0.1,
      "shortage_alert_time": 24,
      "shortage_max_time": 72,
      "satisfied_health_gain_per_hour": 0.002,
      "max_shortage_health_loss_per_hour": 0.012
    }],
    "produces": []
  }
]
```

All fields except sprite paths are required. Subject IDs must be unique and `name_key` must exist in
`en.json`. `color` (RGB channels in [0,255]) distinguishes the subject type. Each need references a resource by ID and specifies `amount_per_hour`, the
resource units one subject consumes per hour, which must be finite and strictly
positive; subject needs are hourly only, with no `amount_per_unit`. Each need also has
`shortage_alert_time`, how many hours the subject can go without that resource before it complains
(finite, nonnegative; formerly `alert_time`, which is now rejected even alongside
the new field—rename the key in custom catalogs without changing its value), and `shortage_max_time`, how many
hours it can remain in shortage before it dies or shuts down (finite, nonnegative).
This field replaces `starving_max_time`; custom catalogs must rename the key without
changing its value. The legacy name is rejected, including alongside the new name. Starving
starts as soon as the resource is denied; `shortage_alert_time` only delays the complaint. Each need
also declares two nonnegative health magnitudes: `satisfied_health_gain_per_hour` at full
fulfillment and `max_shortage_health_loss_per_hour` at maximum shortage severity.

`rest_time` is how many consecutive hours the subject must rest and `work_time` how many
consecutive hours it can work; both are finite, nonnegative hours. `extra_work_time` is the
maximum finite nonnegative overtime after `work_time`. Individual health thresholds are
`min_work_health` and `min_colony_health`, and must satisfy
`0 <= min_colony_health < min_work_health <= 1`. `health_rates` is a required object of
six nonnegative finite magnitudes: `work_gain_per_hour`, `rest_gain_per_hour`,
`extra_work_loss_per_hour`, `max_inactivity_loss_per_hour`, `inactivity_max_time`
(hours) and `station_recovery_per_hour`. The shipped human and robot definitions use the
tuning values from [Subject Health, Shifts, Staffing, and Medical Evacuation](subject-health-and-staffing.md).
A subject type may declare at most `NEED_SLOT_LIMIT` (8) needs; larger catalogs are
rejected because runtime need state uses fixed per-subject arrays. The runtime
health/need state, its fixed-tick calculation and its ownership are documented in
[Subject Runtime Contracts](subject-runtime-contracts.md). Medical evacuation remains
pending; the staffing-slot model, its derived coverage, the bounded shift scheduler,
the work trip, the atomic handoff and the rest/overtime lifecycle are implemented
(see [Building staffing](building-staffing.md)).

`roles` lists the roles the subject type
can take as `{role_id, sprite}` objects (`worker`, `supervisor`, `repairer`, without
duplicate role IDs), or is `null` (`[]` is equivalent) when it takes none. `sprite`
is an optional normalized PNG path for that role; empty/omitted uses `subject.sprite`,
and if that is also empty the subject type color is drawn. Role presentation never
reads `subject_roles.json`, which holds only IDs and localized names.
Legacy string entries are rejected. Level subject roles remain string IDs and must
come from the type's `role_id` values. See [subject role assignments](subject-role-assignments.md). `produces` lists what the subject
produces, each with a positive `units_per_hour` (subjects have no `amount_per_resident`),
and no `capacity` or `stored`: subjects hold no stock. Rest, work and overtime
scheduling and subject production remain validated metadata only; the health rates
and needs already drive the fixed-tick health step, and the scheduler uses
`rest_time`/`work_time` to plan reservations.

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
      "repairing": false,
      "enable_at_start": true,
      "residents_amount": null
    },
    {
      "id": "SP1",
      "building_id": "solar_panel",
      "position": { "x": 3, "y": 0 },
      "health": 1,
      "repairing": false,
      "enable_at_start": false,
      "residents_amount": null
    }
  ],
  "subjects": [],
  "space_station": {
    "station_id": "space_station",
    "distance": 35000.25,
    "resources": [],
    "subjects": []
  }
}
```

All fields are required. Instance IDs must be unique within a level, `building_id`
must exist in the building array, positions must be finite, and health must be in
[0,1]. Empty building/subject arrays are valid, but a station instance is required. `enable_at_start: true` makes an instance active when
the level starts; `control_unit` instances are always active and cannot be disabled,
and instances of an `always_on` building type (such as `control_unit`) must set
`enable_at_start: true`. An instance with `enable_at_start: true` and `health` below
its type's `min_operative_health`, or an initial power deficit of the buildings that
start active, is rejected before the window opens.

`residents_amount` is how many residents live in the instance. It is a finite number in
[0, `residents.capacity`] when the building type has `residents` (e.g.
`"residents_amount": 12` on a Humans Residence) and must be `null` for every other type.
The field is required either way.

The required `space_station` selects a template in `space_stations.json` through
`station_id`, plus a required finite, nonnegative `distance` in km from that level's
colony. Distance belongs only to the level instance, not to the station catalog.
Its `resources` and `subjects` each require one row per template ID,
with `units` and signed `units_per_hour`. Capacities come only from the template;
quantities must be between zero and that capacity. Subject `units` must be whole;
subject rates may be fractional and accrue into whole available subjects each fixed
tick as individual runtime subjects. Initial station stock plus colony residents
must fit the 16,384-subject runtime limit. `residents_amount` must also be whole;
explicit level subjects are preserved and any remaining residents are materialized
as individuals. Resource rates remain metadata. See [station instances](space_station.md#one-station-instance-per-level).
The example above uses the shipped station's empty resource/subject lists.

The required `subjects` array (use `[]` for none) places subject instances:

```json
"subjects": [
  { "id": "H1", "subject_id": "human", "residence": "HR1", "health": 1, "initial_assignment": { "building_id": "GH1", "role_id": "worker" }, "roles": ["worker", "supervisor"], "speed": 1 },
  { "id": "H2", "subject_id": "human", "residence": "HR1", "health": 0.5, "initial_assignment": null, "roles": ["repairer"], "speed": 0.8 }
]
```

All fields are required. Subject IDs must be unique among the level's subjects, and
`subject_id` must exist in `subjects.json`. `residence` references a building
**instance** ID of the same level (e.g. `HR1`, not `humans_residence`). `health` is the
individual health in [0,1]; generated residents default to `1`. `initial_assignment`
replaces the former `occupation`: it is `null` for no initial shift, or an object with
`building_id` (a building instance ID) and `role_id`. Validation confirms the subject
can perform the role and the referenced building type exposes a positive `continuous`
staffing slot for it. The level format has no explicit `slot_index`: subjects fill
consecutive slots of the same building role in level-subject order, and a level with
more initial assignments than continuous slots (or more than
`STAFFING_SLOT_LIMIT` total continuous slots) is rejected before a session starts. An
initial assignment starts the subject on shift at the assigned building, with
`work_hours` at zero; later scheduling may invalidate it if the subject or building
state does not allow the claim. `roles` is an array, without
duplicates, of the jobs the subject can do: `worker`, `supervisor`, and/or `repairer`
(case-sensitive). Every role must be listed in the subject type's `roles`; the array must
be nonempty when the type has roles, and `[]` when the type's `roles` is `null` (or `[]`). The former single `role` field is rejected. `speed` is a finite positive multiplier;
`1` is normal speed. The residence's building type must have `residents.type` equal to the
subject's `subject_id`, and each residence instance holds at most its type's
`residents.capacity` subjects (a fractional capacity rounds down in effect: `1.5` allows
one resident).
Initial assignments, health and rest/work values now drive the staffing-slot model:
`logic.derive_staffing` materializes stable continuous slots, tracks physical
occupants and reservations independently and derives each building's `staffed` flag,
and `logic.schedule_staffing`, `logic.step_shifts` and `logic.commit_shift_handoffs`
reserve replacements, walk them to work, advance work/overtime/rest and commit the
atomic handoff. Medical evacuation releases work, walks patients to a landing
platform and removes them permanently at zero health; emergency ships batch patients
with non-preemptive two-class landing priority; and hospitalized patients recover
automatically at the station and return home on emergency ships. The behavior is
specified in [Subject Health,
Shifts, Staffing, and Medical Evacuation](subject-health-and-staffing.md). Its ordered
[implementation plan](subject-health-and-staffing-tasks.md) records the delivered
slices (tasks 1-13) and the remaining deferrals (resource production, `on_demand`
request generation).

Instances are copied and drawn in level-array order. Overlaps are allowed; clicking
selects the last-drawn building at that point, unless the notice panel consumes it.
The world origin is the viewport center, X right, Y down, at 64 screen pixels per
world unit. Rectangles use the type's pixel dimensions scaled by zoom, have a center
pivot and draw only their sprite or configured color fill.
Resizing changes the viewport origin, not world positions. The camera zooms
(0.25×–4×, around the cursor) and pans through the `zoom_in`, `zoom_out`, and `pan`
key bindings; it changes only presentation. There is no automatic layout or
gameplay collision yet.

## Key Bindings

`key_bindings.json` maps each action to a nonempty array of inputs. All actions
are required, and any one listed input triggers the action:

```json
{
  "version": 1,
  "menu_up": ["key:up"],
  "menu_down": ["key:down"],
  "activate": ["key:enter", "key:space"],
  "back": ["key:escape"],
  "select": ["mouse:left"],
  "zoom_in": ["wheel:up"],
  "zoom_out": ["wheel:down"],
  "pan": ["mouse:right", "mouse:middle"],
  "speed_up": ["key:e"],
  "slow_down": ["key:q"],
  "overview_buildings": ["key:b"],
  "overview_subjects": ["key:s"]
}
```

- `menu_up`/`menu_down` move the menu selection; `activate` runs the selected item,
  including **Resume Game** while a paused session exists. Resume continues that
  session; Play still starts a fresh one.
- `back` leaves the game for the menu. `select` clicks menu items and toggles buildings.
- `zoom_in`/`zoom_out` zoom around the cursor: each wheel notch or key press is one
  10% step. `pan` drags the view while held.
- `speed_up`/`slow_down` step the in-game clock speed one level per press. Pressing
  both in the same frame does nothing. See [Game Clock](power.md#game-clock).
- `overview_buildings`/`overview_subjects` toggle the bottom-right overview grids
  during play. Pressing the active action again closes that panel; pressing the
  other switches to it. Pressing both in the same frame does nothing, and Escape
  also closes an open overview.

Input names use a lowercase prefix and a case-insensitive name:

- `key:<name>` uses raylib `KeyboardKey` names, e.g. `key:a`, `key:enter`,
  `key:left_shift`, `key:kp_add`, `key:equal`.
- `mouse:<name>` uses raylib `MouseButton` names: `left`, `right`, `middle`, `side`,
  `extra`, `forward`, `back`.
- `wheel:up` / `wheel:down` are wheel directions. They cannot be used for `pan`,
  which needs an input that can be held.

Unknown names, empty arrays, duplicate inputs within an action, and missing or
unknown actions are startup errors. The same input may serve several actions.

## Migration to configuration versions

- Every JSON file moved into a version directory: `assets/config/<version>/`.
  `default` keeps the shipped configuration, so a previous
  `assets/config/buildings.json` is now `assets/config/default/buildings.json`,
  `assets/levels/level_0.json` is now `assets/config/default/levels/level_0.json`,
  and `assets/localization/en.json` is now
  `assets/config/default/localization/en.json`.
- `assets/levels/` and `assets/localization/` no longer exist. Sprites and fonts stay
  shared, so `sprite` fields keep their `assets/sprites/...` form.
- There is no silent fallback: a missing file is reported with its version-relative
  path, and an unknown version fails before the window opens.

## Migration from the previous object catalog

- Move the old root `resources` array to `assets/config/default/resources.json`.
- Replace the remaining keyed definitions with an array, dropping root `version`.
- Rename each definition's `kind` to `id`; remove the redundant outer key.
- In every level, rename `kind` to `building_id`; preserve the instance's own `id`.
- Ensure both sides use the same case, e.g. `control_unit`, not `Control_Unit`.
- The old object format and legacy `kind` fields are rejected; there is no silent
  compatibility fallback. Catalog arrays currently have no schema-version field;
  the level format still requires version 1.
- Building and subject products now use `units_per_hour` instead of `time_per_unit`: invert the old
  hours per unit (`time_per_unit: 3` becomes `units_per_hour: 0.33333`). Subject needs use `shortage_alert_time` instead of `autonomy_time`, with the
  same value.

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
configuration. It resolves the flat runtime stock table from the definitions once per
session, seeded from the level template. Reset restores the template amounts and
allocates nothing. Snapshots and commands use stable instance/type IDs; the renderer
retains no frame-temporary data.
See [Power](power.md) for command ordering, notices, and simulation timing boundaries.
