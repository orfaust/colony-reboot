# Colony Reboot

A 2D game engine in Odin. The current prototype provides a resizable, black
1280x720 window (minimum 640x360) and a centered main menu with the uppercase
COLONY REBOOT title above the buttons.

## Toolchain

Verified build and headless tests on Windows with Odin
`dev-2026-01-nightly:7fa05f1` and its vendored raylib 5.5 (OpenGL backend).
No additional dependencies are required. Other platforms have not been tested.
Raylib uses the zlib/libpng license; its license and bundled dependency notices
are distributed in the Odin installation under `vendor/raylib/LICENSE` and
`vendor/raylib/raylib.odin`. The default font is provided by raylib; no external
art assets have been added.

## Build and Test

Run from the repository root with Odin on PATH. Create `build` first (`mkdir build`
if it does not exist).

```sh
odin check src/app
odin build src/app -out:build/colony-reboot.exe
odin test src/ui -out:build/ui-tests.exe
odin test src/localization -out:build/localization-tests.exe
odin test src/logic -out:build/logic-tests.exe
odin test src/config -out:build/config-tests.exe
odin test src/app -out:build/app-tests.exe
odin test src/render -out:build/render-tests.exe
```

These checks pass. To launch the built application from PowerShell:

```powershell
.\build\colony-reboot.exe
```

Interactive launch and visual behavior still require the manual smoke test below.
The working directory must be the repository root so the localization file can
be found. Asset packaging and executable-relative lookup are not implemented yet.

## Controls and Current Scope

- Mouse movement selects a menu item; left click activates it.
- Up/Down wraps keyboard selection; Enter or Space activates it.
- `exit game` and the native window close button exit the application.
- Play starts level 0 from `assets/levels/level_0.json`, using its configured instances.
- Building definitions are an array in `assets/config/buildings.json`, identified by
  `id`; resources are a separate array in `assets/config/resources.json`. Level
  instances reference a type through `building_id` and keep their own unique `id`.
  Each instance is
  drawn as a colored rectangle with its code and power values inside, using configured
  `width`/`height`. Restart after editing JSON.
- Click a building to toggle activity. Only CU starts active; CU cannot be disabled.
  Inactive buildings have a 50% black overlay.
- Activations and generator shutdowns that would create a power deficit are refused.
  The bottom panel shows the latest four warnings in chronological rows, automatically
  scrolling upward as messages arrive. Each expires independently after ten seconds.
- See [Power and Activity](docs/power.md) for rules, timing, ownership, and smoke tests.
- See [Configuration](docs/configuration.md) for schemas and examples.
- [manage/](manage/README.md) contains an optional local web tool (Node + React)
  to edit these JSON files visually; the game does not depend on it.
- Load and Settings currently display localized placeholder messages.
- Escape returns from the scene to the menu; it never exits the application.
- Unfocused windows ignore menu and scene navigation input.

## Architecture and Ownership

- `src/contracts`: backend-independent input, semantic actions, menu views, and building snapshots.
- `src/logic`: building/resource definitions and authoritative session state; headless.
- `src/ui`: menu layout, focus, and interaction; no graphics calls.
- `src/render`: raylib window/input adapter and drawing; backend types remain private.
- `src/localization`: English JSON loading and validation; no UI or render dependency.
- `src/config`: startup JSON adapter for building definitions and level 0; validates
  data and references before creating headless logic state.
- `src/app`: composition, action routing, startup, and shutdown.

Logic applies activity commands and validates an instantaneous shared power balance.
Resource production, energy storage, repair, damage, and animation are not implemented;
no simulation state advances with time. Notice expiration uses presentation time only.
A fixed simulation clock with bounded catch-up must be added before time-dependent
rules. Pause, resume, and time scaling therefore have no simulation effect yet.
Presentation is capped at 60 FPS with a vsync hint.

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
code, world-unit `width`/`height`, RGB color (0–255 channels), `power_need_kw`, `power_output_kw`, `needs`, and
`produces`. `Building_Instance` holds a unique string ID, typed `building_id` (instead of
a localized type name), world position, normalized health [0,1], and `repairing`
(assumed to mean repair in progress). The building ID links an instance to its definition.

`Resource` distinguishes gameplay materials from graphics assets: stable ID,
name/description/unit localization keys, and RGB color. `Need` references a resource
by ID and specifies `amount_per_unit`, the resource units consumed per product unit.
`Product` references a resource by ID and specifies `time_per_unit` in hours per unit. The JSON resource catalog
and recipe metadata are validated at startup; recipe execution and multi-output
consumption semantics are not implemented.

Instance positions, health, and repair flags come from the level JSON. The CU type
is Control Unit, with its configured blue color and description “Channels energy from sources to utilizers”.
Its configured power values are zero and both recipe lists are empty. All fields
are required in JSON; there are no implicit defaults. The CU displays total active
production minus total active consumption. Levels may contain multiple buildings
with manually assigned unique IDs. Activity is initialized by logic, not level JSON.
The catalog also includes Solar Panel, Robots Warehouse, Water Collector, and
Greenhouse, with English names/descriptions and water/vegetables resource metadata.
Water Collector is configured for 0.02 hours per liter (50 L/hour); Greenhouse
requires 3 liters per kilogram of vegetables, taking 6 hours per kilogram.
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
using raylib's default alpha blending. Instances are drawn in level-array order. Resizing recenters the scene. No sprites or new art assets are used.

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
