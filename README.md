# Colony Reboot

A 2D game engine in Odin. The current prototype provides a resizable, black
1280x720 window (minimum 640x360) and a centered main menu with the uppercase
COLONY REBOOT title above the buttons.

## Toolchain

Verified build and headless tests on Windows with Odin
`dev-2026-01-nightly:7fa05f1` and its vendored raylib 5.5 (OpenGL backend).
The validated build additionally requires Python 3.10+ (3.14 verified), using only
its standard library. Other platforms have not been tested.
Raylib uses the zlib/libpng license; its license and bundled dependency notices
are distributed in the Odin installation under `vendor/raylib/LICENSE` and
`vendor/raylib/raylib.odin`. Original geometric PNGs and their reproducible source
are documented in [assets/sprites/README.md](assets/sprites/README.md); existing
font assets remain unchanged.

## Build and Test

Run from the repository root with Odin and Python on PATH. The validated build
creates `build` and checks all configured sprite files before invoking Odin.

```sh
python tools/build.py
python -m unittest discover -s tools -p 'test_*.py' -v
odin check src/app
odin test src/contracts -out:build/contracts-tests.exe
odin test src/ui -out:build/ui-tests.exe
odin test src/localization -out:build/localization-tests.exe
odin test src/logic -out:build/logic-tests.exe
odin test src/config -out:build/config-tests.exe
odin test src/app -out:build/app-tests.exe
odin test src/render -out:build/render-tests.exe
odin run tools/gameplay_smoke -out:build/gameplay-smoke.exe
```

Direct `odin build/check/test` bypasses asset existence validation: use
`python tools/build.py` for a release build. `python tools/build.py --check-assets`
validates sprites without compiling. See [Roles and Sprites](docs/roles-and-sprites.md)
for limits and the separately verified GPU smoke command.

These checks pass. To launch the built application from PowerShell:

```powershell
.\build\colony-reboot.exe
```

Interactive launch and visual behavior still require the manual smoke test below.
The working directory must be the repository root so the configuration version can
be found. Asset packaging and executable-relative lookup are not implemented yet.

## Configuration Versions

All JSON configuration lives in version directories under `assets/config`. The
shipped version is `default`:

```text
assets/config/default/
  buildings.json  resources.json  subjects.json  subject_roles.json
  ships.json  space_stations.json  key_bindings.json
  levels/level_0.json
  localization/en.json
```

Sprites (`assets/sprites`) and fonts (`assets/fonts`) are shared, so JSON `sprite`
fields keep their repository-relative `assets/sprites/...` form. Copy the `default`
directory to create another version and edit it freely; every version is
self-contained and validated on load.

Select the version at startup in either of two ways:

```sh
# Runtime argument, no rebuild (works with `odin run` and the built executable).
odin run src/app -- --config test1
.\build\colony-reboot.exe --config test1

# Build-time default used when no --config argument is given.
odin run src/app -define:CONFIG_PROFILE=test1
```

`--config` accepts `--config <name>` and `--config=<name>`; a missing value, a
repeated flag, an unknown argument, or a name that is not 1-64 letters, digits,
`-` or `_` exits with status 2 before any session state is allocated. A name that
is valid but has no directory reports the expected path and suggests copying
`assets/config/default`. Ctrl+R reloads the same version and level file.

`python tools/build.py` validates the sprites referenced by **every** version,
including experimental ones. The `manage` asset manager edits one version at a time
and can duplicate or delete them; see [manage/README.md](manage/README.md).

## Controls and Current Scope

Default bindings come from `assets/config/default/key_bindings.json` (see
[Key Bindings](docs/configuration.md#key-bindings)):

- Mouse movement selects a menu item; left click activates it.
- Up/Down wraps keyboard selection; Enter or Space activates it.
- `exit game` and the native window close button exit the application.
- Resume Game continues a paused session; Play starts level 0 from
  `assets/config/default/levels/level_0.json`, using its configured instances.
- Building definitions are an array in `assets/config/default/buildings.json`, identified by
  `id`; resources are a separate array in `assets/config/default/resources.json`. Level
  instances reference a type through `building_id` and keep their own unique `id`.
  Each instance is
  drawn using its configured PNG sprite (or colored rectangle when `sprite` is
  absent/empty) at the configured `width`/`height`.
  Rebuild with asset validation and restart after editing JSON, or use development
  **Ctrl+R** with `odin run src/app -define:DEVELOPMENT_RELOAD=true -out:build/colony-reboot-dev.exe`.
  This explicit capability is not enabled by bare `odin run` or `-debug` alone.
  See [Development reload](docs/development-reload.md) for verified commands,
  rollback, current-level restart and ownership.
- In game, the mouse wheel zooms in/out around the cursor (0.25×–4×; scrolling over
  the notice panel is ignored). Dragging with the right or middle mouse button pans
  the view. Zoom and pan reset when Play starts a new session.
- In game, simulated time advances at one hour per real second. The top-left panel
  shows whole hours elapsed and the current speed. E speeds up and Q slows down
  through 1×, 2×, 4×, 8×, 16×, and 32×; Play restarts the clock at hour 0 and 1×.
  See [Game Clock](docs/power.md#game-clock).
- B toggles the buildings overview and S the subjects overview (configurable
  `overview_buildings`/`overview_subjects` bindings). Pressing the active key again
  closes that panel and the other key switches to it; Escape also closes it.
- Click a building to toggle activity. CU and instances with `enable_at_start: true` start
  active; CU and active buildings with `power_output_kw > 0` cannot be disabled,
  even with surplus power. A building below its `min_operative_health` cannot be activated.
  Inactive buildings have a 50% black overlay.
- Activations that would create a power deficit are refused; generator shutdowns
  are always refused.
  The bottom panel shows the latest four warnings in chronological rows, automatically
  scrolling upward as messages arrive. Each expires independently after ten seconds.
- See [Power and Activity](docs/power.md) for rules, timing, ownership, and smoke tests.
- See [Configuration](docs/configuration.md) for schemas and examples.
- [Subject health and staffing](docs/subject-health-and-staffing.md) specifies
  temporary shifts, health/needs, staffing-dependent operation, emergency medical
  transport, and death. The ordered [implementation plan](docs/subject-health-and-staffing-tasks.md)
  records dependencies and acceptance criteria. Three slices are implemented: shared
  subject/event contracts, the runtime health/need state and the staffing-slot model
  with derived coverage, documented in [Subject Runtime Contracts](docs/subject-runtime-contracts.md)
  and [Building staffing](docs/building-staffing.md); enabled but uncovered buildings
  produce no power while keeping their demand and activation state (see
  [Power](docs/power.md#staffing)); and the bounded deterministic scheduler plus the
  shift lifecycle reserve replacements, walk them to work, advance work/overtime/rest
  and perform the atomic arrival handoff; the medical slice crosses
  `min_colony_health` once per individual, releases work, walks patients to the
  landing platform and permanently removes subjects at zero health; and the
  emergency-transport slice batches patients onto emergency ships with
  non-preemptive two-class landing priority; and the station slice recovers
  hospitalized patients automatically and returns them home on emergency ships.
  Resource production runs hourly and individual need fulfillment now draws from the
  stock of the building each subject is physically inside.
  A deterministic multi-day integration smoke
  exercises shift rotation, late replacement, staffing-gated power, simultaneous
  shortages, medical evacuation, station recovery, emergency-priority landing, return
  and a death while waiting; see [Gameplay smoke](docs/gameplay-smoke.md).
- [Role metadata and sprite paths](docs/roles-and-sprites.md): `subject_roles.json`
  defines localized names for the existing jobs and carries no color or sprite;
  subject types and their per-role overrides carry `sprite` paths, and building
  types accept optional `sprite` paths. Configured PNGs replace color
  placeholders, are cached at startup and validated before the supported build.
- [manage/](manage/README.md) contains an optional local web tool (Node + React)
  to edit these JSON files visually; the game does not depend on it.
- Load and Settings currently display localized placeholder messages.
- Escape returns from the scene to the menu; it never exits the application. The
  menu then shows **RESUME GAME** as its first entry, which continues the paused
  session where it stopped. **PLAY** always starts a fresh session from the level,
  so it still resets the clock, fleet and stock.
- Unfocused windows ignore menu and scene navigation input.

## Architecture and Ownership

- `src/contracts`: backend-independent input, semantic actions, menu views, building
  and subject snapshots, edge-triggered event payloads, and immutable role metadata
  (IDs, resolved names, colors, sprite paths).
- `src/logic`: building/resource definitions and authoritative session state; headless.
- `src/ui`: menu layout, focus, and interaction; no graphics calls.
- `src/render`: raylib window/input adapter and drawing; backend types remain private.
- `src/localization`: English JSON loading and validation; no UI or render dependency.
- `src/config`: startup JSON adapter for building definitions and level 0; validates
  data and references before creating headless logic state.
- `src/app`: composition, action routing, startup, and shutdown.

Logic applies activity commands and validates an instantaneous shared power balance.
Subject individuals carry health, a work phase, timers and per-need shortage state;
a fixed-tick step clamps health and applies configured rest/work/overtime, quadratic
inactivity and quadratic need shortage. The same fixed tick materializes continuous
staffing slots, derives physical coverage and reservations, runs the bounded
deterministic scheduler, commits the atomic shift handoff, gates enabled-but-uncovered
power output, and advances medical evacuation, emergency transport, station recovery
and return. Hourly resource production and consumption run all-or-nothing behind the
same staffing gate, and a power deficit force-stops the greatest active consumer
(automatic load shedding). At each whole simulated hour the same boundary also sets
per-need fulfillment from the stock of the building the subject is physically
inside, so the quadratic shortage maths runs on real supply; a subject in transit
draws nothing and a building with no stock entry for a resource keeps that need at
full fulfillment (reported once as a startup configuration diagnostic). Energy
storage, repair, damage, and animation are not implemented.
`logic.Clock` advances a fixed one-simulated-minute tick with bounded catch-up and
time scaling; building warmup/cooldown (output ramp and yellow startup bar) advance once per tick. Notice expiration uses presentation
time only. Presentation is capped at 60 FPS with a vsync hint.

Input and view structures are passed by value, synchronously, with no command queues.
UI retains a bounded 32-message log; overflow discards the oldest warning.
The UI consumes menu input and returns at most one action per frame. Keyboard
navigation runs before pointer selection; a valid click takes priority over
keyboard activation. The menu has a fixed order (Resume Game, Play, Load, Settings,
Exit); Resume Game is only present once a session exists, and is skipped by
keyboard wrapping while hidden. Layout and input share top-left screen coordinates, with
X right and Y down, in raylib screen units. Layout is recalculated on resizing;
menu dimensions stay fixed at supported sizes and the centered block, including the
title, stays inside the window.

The application owns a 64-byte-aligned startup arena for localization, configuration,
and session storage until shutdown. UI views borrow its
strings and the renderer retains no frame data. Temporary C strings are reclaimed
after each frame. Window resources are released before the localization arena.
All graphics calls run on the main thread.

## Buildings and Resources

`Building_Type` defines a stable type `id`, localization keys for name/description,
code, pixel `width`/`height` (64 pixels per world unit; the catalog default is 64×64), RGB color (0–255 channels), `power_need_kw`, `power_output_kw` (mutually exclusive: a building either produces or consumes power, and an `always_on` type must have `power_need_kw == 0`), `always_on` (cannot be switched off; its level instances must set `enable_at_start`), `warmup_time`/`cooldown_time` (hours to start producing
after activation / to return to the initial state after deactivation), `min_operative_health`
(health needed to activate), `materials_amount` (to build and repair), `subject_roles`
(`{role_id, quantity, staffing_mode}` staffing metadata; see [Building staffing](docs/building-staffing.md)), `residents` (`null`, or `{ type, capacity }`: the subject type it hosts and how many), `needs`, `produces`, and
`storage` (`{ resource_id, capacity }` entries for extra resources it can hold). `Building_Instance` holds a unique string ID, typed `building_id` (instead of
a localized type name), world position, normalized health [0,1], `repairing`
(assumed to mean repair in progress), `enable_at_start`, and `residents_amount` (a number
within the type's `residents.capacity`, or `null` when the type has no residents). The building ID links an instance to its definition.

`Resource` distinguishes gameplay materials from graphics assets: stable ID,
name/description/unit localization keys, and RGB color. `Need` references a resource
by ID and specifies exactly one of `amount_per_unit` (units consumed per product unit)
or `amount_per_hour` (units consumed per hour of operation),
plus `capacity`.
`Product` references a resource by ID and specifies `units_per_hour` (units
produced per hour), plus `capacity`; the obsolete building `amount_per_resident` rate
was removed, because per-capita consumption is modelled only by subject needs. Each level building instance has a required `stored` array of
`{ "resource_id": "water", "amount": 0 }` entries, one per needed, produced, or stored resource;
subject products have only `resource_id` and `units_per_hour`. `stored` is the immutable
level template: the session resolves an owned, mutable runtime stock table from it
(capacities from the definitions, amounts seeded from the level) and restores that
table on reset. The JSON resource catalog
and recipe metadata are validated at startup. Recipes run once per whole simulated
hour, all-or-nothing: every input must be available and every output must fit after
those inputs are applied, or the whole hour is skipped with no partial consumption or
production. Each product yields `units_per_hour`; each need consumes `amount_per_hour`
or `amount_per_unit` scaled by the first `produces` entry (the reference product).
Results are independent of the clock speed and frame pacing.

`Subject_Type` (from `assets/config/default/subjects.json`) has a stable `id`, a `name_key`, a `color`, an optional `sprite` path, required positive pixel `width`/`height` at 100% zoom (presentation metadata), and
`needs` consumed per hour (`amount_per_hour`, with `shortage_alert_time` hours before complaining (starving starts once denied), `shortage_max_time` hours before dying or shutting down, and nonnegative `satisfied_health_gain_per_hour`/`max_shortage_health_loss_per_hour` health rates), consecutive `rest_time`/`work_time` hours with `extra_work_time` overtime, individual `min_work_health`/`min_colony_health` thresholds satisfying `0 <= min_colony_health < min_work_health <= 1`, a required `health_rates` object of nonnegative magnitudes, `roles` (`{role_id, sprite}` objects for eligible jobs, or `null`; see [role assignments](docs/subject-role-assignments.md)), and
`produces` (products like a building's). Level `subjects` are `Subject_Instance`s
with their own `id`, a `subject_id`, individual `health` in [0,1], a required `residence` (its building type's `residents` must host the subject type, within
`residents.capacity`), a nullable `initial_assignment` (`{ building_id, role_id }` referencing a continuous staffing slot, replacing the former `occupation`), `roles` (string IDs taken from its subject type's `roles[].role_id`: one or more of `worker`, `supervisor`,
`repairer`, or `[]` when the type's `roles` is `null`), and a positive `speed` multiplier. An initial assignment starts the subject on shift at that building in the first free slot of the role; startup rejects more assignments than continuous slots. Subjects are validated at startup and simulated headlessly (health/needs and staffing coverage); they are not drawn yet.

Instance positions, health, and repair flags come from the level JSON. The CU type
is Control Unit, with its configured blue color and description “Channels energy from sources to utilizers”.
Its configured power values are zero and both recipe lists are empty. All fields
are required in JSON; there are no implicit defaults. The CU displays total active
production minus total active and still-cooling consumption. Shutdown keeps full
consumption and brightness until the startup level reaches zero; requested activity
and housing eligibility still change immediately. Levels may contain multiple buildings
with manually assigned unique IDs. Initial activity comes from `enable_at_start` (CU always starts active).
The catalog also includes Solar Panel, Robots Warehouse, Water Collector, and
Greenhouse, with English names/descriptions and water/vegetables resource metadata.
Water Collector produces 50 L/hour (`units_per_hour: 50`); Greenhouse
requires 3 liters per kilogram of vegetables and produces about 0.167 kg/hour.
These recipes run hourly behind the staffing gate, and a power deficit sheds the
greatest active consumer instead of scaling production.

The application owns logic state and starts a fresh session on Play. Logic returns
snapshots by value; the renderer receives only an application-built 2D description,
not authoritative state. Definition strings, slices, and instance IDs borrow immutable
startup configuration storage. Logic copies the instance array so resetting or mutating
a session cannot change the loaded template. Display strings borrow localization
storage. There are no command queues or per-frame simulation allocations. The config loader
validates instance building IDs against the catalog and checks duplicate IDs; logic checks
nonempty instance/type IDs, finite positions, and health in [0,1].

The application maps world origin to viewport center with X right and Y down and
64 screen pixels per world unit. The rectangle uses the type's pixel `width` and
`height` (catalog default 64×64), scaled by the camera zoom, with a center pivot;
its bounds are presentation-only, not collision geometry. The renderer draws the
sprite (or its configured color fill); no text is drawn over a building. Inactive
buildings receive a black 50% overlay,
using raylib's default alpha blending. Instances are drawn in level-array order. Resizing recenters the scene. Original static PNG sprites replace configured
color fills without changing simulation coordinates or input bounds.

## Building Inspector

Right-click a building to open its information box near the cursor: localized name
and description, activity state, health, activity level, and current power output
and consumption. Rows that do not apply are omitted: a type that produces no power
shows no output row, and a type with no resident slot shows no Subjects section
(not an explicit empty state). It also shows:

- Subjects (only when the type hosts residents): localized resident type and
  current/capacity. A Staffing section shows
  live continuous coverage as `{covered}/{required} covered` per role, scheduled
  replacements as `{role}: {reserved} arriving`, `Uncovered continuous slots: {count}`
  while any continuous slot is physically open, and `{role}: {quantity} on demand`
  for configured on-demand entries; a building with no continuous slots shows the
  localized empty state. Coverage is physical (`logic.staffing_coverage`), not an
  assumption from an assignment. An Individuals section then lists each resident,
  assigned or reserved individual associated with the building with name/ID, health,
  work/medical phase, role, assignment slot, work/rest/idle timers, medical status and
  per-need fulfillment/shortage lines. Removed and unrelated subjects are never shown.
- A Stock section lists one localized row per resolved runtime stock entry (resource
  name plus `amount/capacity` with its unit), including storage-only resources, read
  from `logic.stock_snapshot`, followed by the resolved hourly flow of that resource
  (`consumed in`, `produced out`). A `Production` line reports the live hourly recipe
  state (operational, inactive, warming up, unstaffed, missing input, output full).
  Needs and products list their configured rates per
  hour or per product unit. Empty sections are explicit.
  Amounts change only at whole simulated hour boundaries; opening the inspector never
  consumes or produces resources.

Values refresh from read-only snapshots and borrowed instance/catalog data each
frame, including residents delivered by transports. Formatted strings live only
for the frame and are consumed synchronously by UI/render. Escape closes
the inspector before returning to the menu; right-clicking empty space also closes it.
The box stays inside the viewport when resized (up to 420×520). Wheel input over
it scrolls body rows, keeping the title and navigation hint visible, and never
zooms the world or scrolls transport cards beneath it. Selection is also consumed.
Scroll position resets on a new inspection and clamps after resizing.
All information-panel text uses exactly the same font size (24) as the clock and
notices, including titles: it never shrinks to fit. Long text wraps at words (or
UTF-8 boundaries for long IDs), then scrolls within the panel. Text is left-aligned
with padding; building inspector titles
use the building's configured color and body text stays white. The station panel
also uses left-aligned text, with a white title (stations have no configured color).
Right-button inspection is a fixed mouse gesture, independent of configurable select
bindings: release within 4 pixels opens the box, while a drag retains camera panning.
Overlapping buildings are inspected in reverse draw order (topmost first).

Manual smoke test: inspect a building, observe values during warmup, resize near a
screen edge, scroll through Staffing, Individuals, Needs and Products, then close
with Escape. Verify the coverage fraction and uncovered-slot count against the
individuals listed, including an `arriving` replacement and an on-demand quantity.
Check an empty producer, a resident building and all three need-rate modes; verify
stock units, resident counts and subject health/timers against level data, then after
a transport delivery, a staffing loss/restoration notice and a medical or death
notice. Verify scrolling a box above transport cards affects only the inspector and
right-drag still pans without opening the inspector. These interactive checks require a real window.

## Overview toggles and grids

Two persistent toggles, `Buildings` and `Subjects`, sit bottom-right beside the
notice panel, which shrinks to leave them the reserved column. Clicking one opens
a modal overview grid with one row per element: the active toggle is highlighted,
clicking it again closes the grid, clicking the other switches it, and Escape or a
click on the dimmed backdrop also closes it. The configurable `B` and `S` bindings
perform the same open/close/switch from the keyboard during play. The modal covers the world and the
other overlays, but the two toggles stay drawn above it and consume their clicks;
the modal consumes all other pointer input so clicks and wheel never reach
buildings, transports or the camera.

The buildings grid shows code, name, state, health %, activity %, power out kW,
power need kW, residents, total staffing coverage, and per-resource needs,
products and storage as `<qty>/<capacity>` entries joined with `; ` in configured
order (or the localized empty value when the type configures none). The subjects
grid shows ID, type, health %, work phase, residence, occupation building
(`building.code` of the assigned workplace), role, medical status and work/rest
hours. Each row starts with a small square filled with the element's configured
color: the building type color or the subject type color (`subjects.json`). Grid
columns are sized to their widest cell and clipped per column, the shared
24-pixel font is never scaled, and the wheel scrolls the rows with clamping. UI
owns pagination and scroll state, render only draws the returned page, and the
application builds localized columns and frame-owned cells from read-only
snapshots; opening a grid never mutates simulation state or pauses time.

Manual check: open each grid, confirm values against the inspector, scroll with the
wheel, resize the window, then close with the active toggle or Escape. The real
backend smoke covers both grids:

```sh
python tools/build.py
odin run tools/info_smoke -out:build/info-smoke.exe -define:INFO_BOX_SMOKE=true
```

It writes `build/overview-buildings.png` and `build/overview-subjects.png`.

## Info-box readability and numeric precision

Inspector, station and transport text share 24-pixel type, 26-pixel row spacing,
and 8-pixel padding. Render measures wrapping using the actual font, UI owns scroll
state and pagination, and render draws the resulting frame-owned rows without
scaling. No wrapped text or catalog references are retained across frame resets or
development reload. Transport cards grow with their wrapped content and scroll in
pixels, so even a card taller than its viewport remains accessible. Titles retain
the element color when wrapped; the inspector's title and navigation hint stay
visible. The clock can grow vertically for wrapped text. The notification panel
grows to retain the four newest wrapped messages; if extreme text exceeds the
viewport, it follows the newest visible rows. Station/transport space adapts to
these bounds instead of reducing any font size. World labels on
buildings still scale with their sprites; they are not info boxes.

Presentation-only numbers omit trailing decimal zeros. Quantities, capacities,
percentages and power use up to two decimals; rates use up to three. Outside the
transport box, fractions below one retain three significant digits (scientific
notation for very small values), never silently becoming zero. Transport distance,
current/maximum speed and known ETA hours instead display rounded whole numbers,
including zero for values below half a unit; their simulation precision is unchanged. Whole subject/ship counts remain integers, and subject station
capacity retains its existing whole-person floor. Signed rates keep their direction;
zero is unsigned. Unknown ETA remains localized without a misleading hours suffix.
All simulation values remain unrounded. A building with no continuous staffing slots
shows an explicit localized message; on-demand quantities and every uncovered slot
count are shown explicitly, and an empty Individuals section uses a localized empty
state. Staffing loss/restoration, medical dispatch/return and death each add one
localized edge-triggered notice to the same log, in simulation-event order. Every
building-specific notice (staffing loss/restoration and the immediate toggle
feedback) names the affected building by its localized type name plus its level
instance ID, for example `Meals Factory (MF1)`; those templates require `{name}` and
`{id}` and are precomposed per building at load time, so the bounded log never
allocates per event and never shows a raw placeholder. See the player-facing notice
convention in [AGENTS.md](AGENTS.md).

Verified visual capture using the real backend and current localized catalog:

```sh
python tools/build.py
odin run tools/info_smoke -out:build/info-smoke.exe -define:INFO_BOX_SMOKE=true
```

This writes `build/info-boxes-wide.png`, `build/info-boxes-small.png` and
`build/info-boxes-small-panels.png` (1280×900 and 640×360), including a scrolled
inspector and transport card. When the level has no active departure the capture
uses a synthetic display-only transport to exercise fractional speed formatting.
The developer smoke does not edit assets or change normal game behavior.

## Ships and Space Station

The in-game station data panel is anchored at the top right (16-unit margin).
It shows the localized station name, resource and subject stock/capacity/hourly
rates, and available ship counts; empty sections show localized `None`. Passenger
stock and ships are reserved on request; subject stock replenishes from the level's
hourly rate using private fractional accrual and whole available counts. Resource
rates remain metadata.
The panel wraps text on resize, stays above notifications, and scrolls overflowing
rows with the wheel. It consumes clicks and world zoom input over its bounds. Visual smoke test: start Play,
resize the window, and verify the panel remains at the top right and clicking it
does not toggle buildings beneath it.

`logic.Ship` contains string `id`, `code`, `name`, and `type`, RGB `color`, `max_speed` (km/h),
optional `sprite` and required positive pixel `width`/`height` (initially 64×64).
These presentation fields are metadata only; see [Ship and Subject Presentation
Metadata](docs/ship-subject-presentation.md) for validation and migration.
Ships also define `max_speed_hours` (hours to accelerate/brake along a non-linear,
jerk-limited S-curve; zero means instantaneous), `units_per_hour` (cargo units loaded
or unloaded per simulated hour; zero prevents dispatch), plus `subjects`
(`subject_id`, `capacity` entries for the subject types it can transport). `logic.Space_Station` contains
its `id`, `code`, localized `name`, resource/subject capacity arrays, and a ship-count array.
Each level requires a `space_station` instance (`station_id`, `distance` in km from its colony, resource/subject
`units` and `units_per_hour`); the station panel displays only that instance. They load from `assets/config/default/ships.json` and
`assets/config/default/space_stations.json` (an ordered array with unique station IDs); JSON `name_key` fields resolve to localized
runtime `name` strings. References and capacities are validated at startup.

Activating healthy, powered housing requests passengers from the station. Suitable
available transports reserve individuals and spend `passengers / units_per_hour`
hours loading them at station before flying with ship-specific non-linear
acceleration/braking (a smoothstep S-curve that keeps ETA and stop distance
unchanged from the former constant-acceleration model).
An ordinary request waits in `Awaiting approval`: it holds its passengers and ship
but starts only when the player presses the rocket approval button on its mission
card in the transport panel. Disabling the residence withdraws a pending request
without a return leg. At 1 km ships reserve
an active `landing_platform` and descend vertically from the top of the current
viewport. Takeoff crosses the viewport back to its upper edge. Both endpoints use
current screen projection; the camera never changes flight timing or outcomes.
If occupied, ships hover with their cargo intact in a logic-owned FIFO queue until
clearance after takeoff; cancelling a waiter does not block the others. Timed
unloading moves 9×16 colored subjects out of the 32×32 ship and updates residents.
Disabling the requesting building withdraws its outstanding inbound request and returns
undelivered cargo to the station. Existing residents receive an evacuation request:
they may stay during cooldown, then walk to the landing platform for a capacity-bounded
pickup through the shared FIFO. Boarding decreases assigned residents individually;
station unloading restores the same people's availability. Reactivation before zero
cancels evacuation; after zero the committed evacuation continues. Missing ships,
platforms or station room leave people/request pending without loss. See
[Residence evacuation](docs/space_station.md#residence-evacuation).
The left mission panel shows loading/landing/return phases, cargo, speed and ETA.
It shows **one box per ship**: concurrent missions sharing a ship collapse into a
single card, and a pending request always represents its ship so it stays
approvable. A pending request card shows its localized waiting status and the
rocket approval button instead of an ETA. Evacuation and medical pickups never
wait for approval.
Play resets the fleet and accrual. Configure positive speeds and stock or subject
rates to exercise dispatch. After unloading, ships take off and return to station
for reuse while subjects walk in single file to their assigned housing. Walkers
are independent runtime instances with stable session IDs, roles, position, speed,
activity and destination. Only their markers disappear indoors; the individuals
persist and can receive separate `Move_Subject` commands. Existing level subjects
and station stock also become individuals. Initial counts must be whole. Autonomous
shifts, needs/rest cycles and staffing are part of the subject simulation (see
[Subject Runtime Contracts](docs/subject-runtime-contracts.md)); obstacle avoidance
and pathfinding are not implemented. Missions remain capped
at 128 per session, and live subject storage at 16,384. The box shows actual onboard
people progressively, not the whole reserved manifest. See
[Ships and Space Station](docs/space_station.md) for examples, numeric types,
signed hourly rates, validation, and ownership.

## UI Text Policy

Every player-facing string, including the window title, menu labels, and status
messages, belongs in `assets/config/default/localization/en.json`. Only English is supported.
Use stable named keys. Core UI text uses the typed `localization.Text` schema;
additional building/resource strings use its validated `entries` map and are
referenced by JSON configuration keys. Do not embed UI text in Odin code.

The catalog is loaded once at startup. Invalid JSON, missing/empty required fields,
and embedded NUL characters are rejected. Missing or invalid catalogs produce a
console diagnostic and a nonzero exit rather than hardcoded UI fallback text.
Developer-only console diagnostics are not localized.

## Manual Visual Smoke Test (Pending)

1. Launch from the repository root; verify the black background, four labels
   (Resume Game is hidden until a session starts), and the centered COLONY REBOOT
   title above the menu without overlap. Verify four entries shrink to fit the
   title at 640×360.
2. Resize and maximize/restore; verify centering and the minimum window size.
3. Activate Play by mouse and keyboard; verify the blue Control Unit rectangle
   drawn at its configured position. Resize to 640×360 and maximize; verify it remains centered and visible.
   Press Escape to return: verify five labels with RESUME GAME first and selected.
   Activate Resume Game; verify the same session continues (clock, stock and fleet
   unchanged) rather than restarting. Press Escape again and activate Play; verify
   a fresh level 0 scene.
   Add a second instance as shown in [Configuration](docs/configuration.md), restart,
   and verify both instances use their configured positions and colors.
   Try building IDs robots_warehouse, water_collector, and green_house. Change one type's
   width to 128 and height to 32; after restart verify a centered 128×32 pixel rectangle
   also after resizing.
   Activate Load and Settings and verify their English placeholder messages.
4. Move the mouse away, navigate with arrows, and verify focus stays visible.
5. Alt-tab away/back and verify unfocused input does not activate menu items.
6. Verify both Exit and the window close button close cleanly.
