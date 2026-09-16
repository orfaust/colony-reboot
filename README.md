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
odin test src/ui -out:build/ui-tests.exe
odin test src/localization -out:build/localization-tests.exe
odin test src/logic -out:build/logic-tests.exe
odin test src/config -out:build/config-tests.exe
odin test src/app -out:build/app-tests.exe
odin test src/render -out:build/render-tests.exe
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
The working directory must be the repository root so the localization file can
be found. Asset packaging and executable-relative lookup are not implemented yet.

## Controls and Current Scope

Default bindings come from `assets/config/key_bindings.json` (see
[Key Bindings](docs/configuration.md#key-bindings)):

- Mouse movement selects a menu item; left click activates it.
- Up/Down wraps keyboard selection; Enter or Space activates it.
- `exit game` and the native window close button exit the application.
- Play starts level 0 from `assets/levels/level_0.json`, using its configured instances.
- Building definitions are an array in `assets/config/buildings.json`, identified by
  `id`; resources are a separate array in `assets/config/resources.json`. Level
  instances reference a type through `building_id` and keep their own unique `id`.
  Each instance is
  drawn using its configured PNG sprite (or colored rectangle when `sprite` is
  absent/empty), with code and power values inside and configured `width`/`height`.
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
- [Planned subject health and staffing](docs/subject-health-and-staffing.md) specifies
  temporary shifts, health/needs, staffing-dependent operation, emergency medical
  transport, and death. The ordered [implementation plan](docs/subject-health-and-staffing-tasks.md)
  records dependencies and acceptance criteria; these systems are not implemented yet.
- [Role metadata and sprite paths](docs/roles-and-sprites.md): `subject_roles.json`
  defines localized names, colors and sprite paths for the existing jobs;
  building types accept optional `sprite` paths. Configured PNGs replace color
  placeholders, are cached at startup and validated before the supported build.
- [manage/](manage/README.md) contains an optional local web tool (Node + React)
  to edit these JSON files visually; the game does not depend on it.
- Load and Settings currently display localized placeholder messages.
- Escape returns from the scene to the menu; it never exits the application.
- Unfocused windows ignore menu and scene navigation input.

## Architecture and Ownership

- `src/contracts`: backend-independent input, semantic actions, menu views, building snapshots,
  and immutable role metadata (IDs, resolved names, colors, sprite paths).
- `src/logic`: building/resource definitions and authoritative session state; headless.
- `src/ui`: menu layout, focus, and interaction; no graphics calls.
- `src/render`: raylib window/input adapter and drawing; backend types remain private.
- `src/localization`: English JSON loading and validation; no UI or render dependency.
- `src/config`: startup JSON adapter for building definitions and level 0; validates
  data and references before creating headless logic state.
- `src/app`: composition, action routing, startup, and shutdown.

Logic applies activity commands and validates an instantaneous shared power balance.
Resource production, energy storage, repair, damage, and animation are not implemented.
`logic.Clock` advances a fixed one-simulated-minute tick with bounded catch-up and
time scaling; building warmup/cooldown (output ramp and yellow startup bar) advance once per tick. Notice expiration uses presentation
time only. Presentation is capped at 60 FPS with a vsync hint.

Input and view structures are passed by value, synchronously, with no command queues.
UI retains a bounded 32-message log; overflow discards the oldest warning.
The UI consumes menu input and returns at most one action per frame. Keyboard
navigation runs before pointer selection; a valid click takes priority over
keyboard activation. Layout and input share top-left screen coordinates, with
X right and Y down, in raylib screen units. Layout is recalculated on resizing;
menu dimensions stay fixed at supported sizes and the block stays centered.

The application owns a 64-byte-aligned startup arena for localization, configuration,
and session storage until shutdown. UI views borrow its
strings and the renderer retains no frame data. Temporary C strings are reclaimed
after each frame. Window resources are released before the localization arena.
All graphics calls run on the main thread.

## Buildings and Resources

`Building_Type` defines a stable type `id`, localization keys for name/description,
code, world-unit `width`/`height`, RGB color (0–255 channels), `power_need_kw`, `power_output_kw`, `always_on` (cannot be switched off; its level instances must set `enable_at_start`), `warmup_time`/`cooldown_time` (hours to start producing
after activation / to return to the initial state after deactivation), `min_operative_health`
(health needed to activate), `materials_amount` (to build and repair), `subject_roles`
(`{role_id, quantity, required}` staffing metadata; see [Building staffing](docs/building-staffing.md)), `residents` (`null`, or `{ type, capacity }`: the subject type it hosts and how many), `needs`, `produces`, and
`storage` (`{ resource_id, capacity }` entries for extra resources it can hold). `Building_Instance` holds a unique string ID, typed `building_id` (instead of
a localized type name), world position, normalized health [0,1], `repairing`
(assumed to mean repair in progress), `enable_at_start`, and `residents_amount` (a number
within the type's `residents.capacity`, or `null` when the type has no residents). The building ID links an instance to its definition.

`Resource` distinguishes gameplay materials from graphics assets: stable ID,
name/description/unit localization keys, and RGB color. `Need` references a resource
by ID and specifies exactly one of `amount_per_unit` (units consumed per product unit),
`amount_per_hour` (units consumed per hour of operation), or `amount_per_resident` (units
consumed per resident per hour; only with `residents`),
plus `capacity`.
`Product` references a resource by ID and specifies exactly one of `units_per_hour` (units
produced per hour) or `amount_per_resident` (units produced per resident per hour; only with `residents`),
plus `capacity`. Each level building instance has a required `stored` array of
`{ "resource_id": "water", "amount": 0 }` entries, one per needed, produced, or stored resource;
subject products have only `resource_id` and `units_per_hour`. The JSON resource catalog
and recipe metadata are validated at startup; recipe execution and multi-output
consumption semantics are not implemented.

`Subject_Type` (from `assets/config/subjects.json`) has a stable `id`, a `name_key`, a `color`, an optional `sprite` path, required positive world-unit `width`/`height` (presentation metadata), and
`needs` consumed per hour (`amount_per_hour`, with `shortage_alert_time` hours before complaining (starving starts once denied) and `shortage_max_time` hours before dying or shutting down), consecutive `rest_time`/`work_time` hours, `roles` (`{role_id, sprite}` objects for eligible jobs, or `null`; see [role assignments](docs/subject-role-assignments.md)), and
`produces` (products like a building's). Level `subjects` are `Subject_Instance`s
with their own `id`, a `subject_id`, a required `residence` (its building type's `residents` must host the subject type, within
`residents.capacity`) and a nullable `occupation`
(building instance IDs of the same level), `roles` (string IDs taken from its subject type's `roles[].role_id`: one or more of `worker`, `supervisor`,
`repairer`, or `[]` when the type's `roles` is `null`), and a positive `speed` multiplier. Subjects are validated at startup but
are not drawn or simulated yet.

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
These recipes are validated metadata only, not active simulation.

The application owns logic state and starts a fresh session on Play. Logic returns
snapshots by value; the renderer receives only an application-built 2D description,
not authoritative state. Definition strings, slices, and instance IDs borrow immutable
startup configuration storage. Logic copies the instance array so resetting or mutating
a session cannot change the loaded template. Display strings borrow localization
storage. There are no command queues or per-frame simulation allocations. The config loader
validates instance building IDs against the catalog and checks duplicate IDs; logic checks
nonempty instance/type IDs, finite positions, and health in [0,1].

The application maps world origin to viewport center with X right and Y down and
64 screen units per world unit. The rectangle uses the type's `width` and `height`
(default catalog values 1.5×1.5, or 96×96 screen units), with a center pivot;
its bounds are presentation-only, not collision geometry. The renderer draws an
rectangle with its code and actual power values centered inside. Text shrinks to
fit and uses black or white for contrast against the configured fill; inactive
buildings receive a black 50% overlay,
using raylib's default alpha blending. Instances are drawn in level-array order. Resizing recenters the scene. Original static PNG sprites replace configured
color fills without changing simulation coordinates or input bounds.

## Building Inspector

Right-click a building to open its information box near the cursor: localized name
and description, activity state, health, activity level, and current power output
and consumption. It also shows:

- Subjects: localized resident type and current/capacity, plus assigned/required
  workers, supervisors and repairers. Assignment counts use live, non-removed
  subjects whose occupation references this building. A multi-role subject counts
  once per supported role; these are assignments, not proof of presence or work.
- Needs and products: localized resource names, stored/capacity with resource units,
  and configured rates per hour, per product unit, or per resident per hour.
  Empty sections are explicit. These rates are metadata, not measured production;
  opening the inspector never consumes or produces resources.

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
screen edge, scroll through Subjects, Needs and Products, then close with Escape.
Check an empty producer, a resident building and all three need-rate modes; verify
stock units and resident counts against level data, then after a transport delivery.
Verify scrolling a box above transport cards affects only the inspector and
right-drag still pans without opening the inspector. These interactive checks require a real window.

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
All simulation values remain unrounded. Zero-assigned/zero-required staffing rows
are omitted, with an explicit message when no staff are assigned or required.

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
optional `sprite` and required positive world-unit `width`/`height` (initially 1×1).
These presentation fields are metadata only; see [Ship and Subject Presentation
Metadata](docs/ship-subject-presentation.md) for validation and migration.
Ships also define `max_speed_hours` (hours to accelerate/brake), `units_per_hour` (cargo units loaded
or unloaded per simulated hour; zero prevents dispatch), plus `subjects`
(`subject_id`, `capacity` entries for the subject types it can transport). `logic.Space_Station` contains
its `id`, `code`, localized `name`, resource/subject capacity arrays, and a ship-count array.
Each level requires a `space_station` instance (`station_id`, `distance` in km from its colony, resource/subject
`units` and `units_per_hour`); the station panel displays only that instance. They load from `assets/config/ships.json` and
`assets/config/space_stations.json` (an ordered array with unique station IDs); JSON `name_key` fields resolve to localized
runtime `name` strings. References and capacities are validated at startup.

Activating healthy, powered housing requests passengers from the station. Suitable
available transports reserve individuals and spend `passengers / units_per_hour`
hours loading them at station before flying with ship-specific acceleration/braking. At 1 km they reserve
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
Play resets the fleet and accrual. Configure positive speeds and stock or subject
rates to exercise dispatch. After unloading, ships take off and return to station
for reuse while subjects walk in single file to their assigned housing. Walkers
are independent runtime instances with stable session IDs, roles, position, speed,
activity and destination. Only their markers disappear indoors; the individuals
persist and can receive separate `Move_Subject` commands. Existing level subjects
and station stock also become individuals. Initial counts must be whole. Autonomous
work/needs cycles and obstacle avoidance are not implemented. Missions remain capped
at 128 per session, and live subject storage at 16,384. The box shows actual onboard
people progressively, not the whole reserved manifest. See
[Ships and Space Station](docs/space_station.md) for examples, numeric types,
signed hourly rates, validation, and ownership.

## UI Text Policy

Every player-facing string, including the window title, menu labels, and status
messages, belongs in `assets/localization/en.json`. Only English is supported.
Use stable named keys. Core UI text uses the typed `localization.Text` schema;
additional building/resource strings use its validated `entries` map and are
referenced by JSON configuration keys. Do not embed UI text in Odin code.

The catalog is loaded once at startup. Invalid JSON, missing/empty required fields,
and embedded NUL characters are rejected. Missing or invalid catalogs produce a
console diagnostic and a nonzero exit rather than hardcoded UI fallback text.
Developer-only console diagnostics are not localized.

## Manual Visual Smoke Test (Pending)

1. Launch from the repository root; verify the black background, four labels,
   and the centered COLONY REBOOT title above the menu without overlap.
2. Resize and maximize/restore; verify centering and the minimum window size.
3. Activate Play by mouse and keyboard; verify the blue square and Control Unit
   code CU inside it (no full name below). Resize to 640×360 and maximize; verify both remain centered and visible.
   Press Escape to return, then Play again; verify a fresh level 0 scene.
   Add a second instance as shown in [Configuration](docs/configuration.md), restart,
   and verify both instances use their configured positions, colors, and codes.
   Try building IDs robots_warehouse, water_collector, and green_house. Change one type's
   width to 2 and height to 0.5; after restart verify a centered 128×32 rectangle
   with its code centered inside it, also after resizing.
   Activate Load and Settings and verify their English placeholder messages.
4. Move the mouse away, navigate with arrows, and verify focus stays visible.
5. Alt-tab away/back and verify unfocused input does not activate menu items.
6. Verify both Exit and the window close button close cleanly.
