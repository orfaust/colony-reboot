# Roles and Sprites

Role metadata is shared through explicit contracts. Optional PNG sprites replace
colored building and subject-role placeholders without changing simulation,
inspector behavior, or FIFO transport/landing rules.

## Role contract and catalog

`contracts.Role` (also exported as `logic.Role`) contains:

- `id: string`: stable untranslated identifier;
- `name: string`: resolved English display name;
- `color: contracts.RGB`: integer red, green, blue channels in [0,255];
- `sprite: string`: optional repository-relative PNG path; absent/empty uses color.

`config.Catalog.subject_roles` holds an ordered immutable array of these definitions.
The JSON source is `assets/config/subject_roles.json`. As in the ship catalog, JSON
uses `name_key` instead of embedding player-facing names:

```json
[
  {
    "id": "worker",
    "name_key": "subject_role_worker_name",
    "color": { "r": 80, "g": 170, "b": 240 },
    "sprite": "assets/sprites/roles/worker.png"
  },
  {
    "id": "supervisor",
    "name_key": "subject_role_supervisor_name",
    "color": { "r": 240, "g": 180, "b": 80 },
    "sprite": "assets/sprites/roles/supervisor.png"
  },
  {
    "id": "repairer",
    "name_key": "subject_role_repairer_name",
    "color": { "r": 100, "g": 200, "b": 120 },
    "sprite": "assets/sprites/roles/repairer.png"
  }
]
```

Names are stored in `assets/localization/en.json` under those keys. Missing, empty,
or NUL-containing translations fail startup with actionable diagnostics; there is
no hardcoded player-facing name fallback.

This catalog describes the **existing three simulation jobs**, not new gameplay
behavior. IDs are strings on the wire and in `Role`, but must match the existing
`logic.Subject_Role` values exactly: `worker`, `supervisor`, `repairer`. Each must
appear once. Unknown, duplicate, or omitted roles fail validation (including `[]`).
Subject types and level subjects retain their current role arrays and eligibility
rules. Extending gameplay to a new job still requires extending its simulation
contract; adding arbitrary catalog entries does not create a job.

`logic.subject_role_id` maps an existing enum value to its stable ID;
`logic.find_role` returns metadata by ID with an explicit found flag. Missing
lookups do not synthesize UI text. Catalog order does not determine gameplay.

## Building sprite metadata

Every type in `assets/config/buildings.json` accepts an optional `sprite` string, for
example `"sprite": "assets/sprites/buildings/control_unit.png"`. It is exposed as
`logic.Building_Type.sprite`. Level building instances continue to reference types
through `building_id`; sprite paths are not duplicated into instances or snapshots.
A nonempty path replaces the colored building fill. Empty or omitted paths retain
the colored rectangle; null and non-string values are invalid. Dimensions, rules,
code/power labels, dimming, activity bars and draw order remain unchanged.

### Path and image contract

Role and building sprite paths:

- when nonempty, start with `assets/` and end with lowercase `.png`;
- are relative to the **repository root**, not the catalog file's directory;
- use forward slashes, without empty, `.` or `..` path components;
- reject backslashes, colons, NULs, and leading/trailing whitespace;
- are case-sensitive metadata; IDs and paths are not localization keys.

All 14 previously reserved paths now have original, reproducibly generated PNGs.
See [asset provenance and regeneration](../assets/sprites/README.md). New editor
entries default to an empty sprite rather than a nonexistent filename.

Supported images are static, non-interlaced, 8-bit RGB/RGBA PNGs, 1–4096 pixels per
axis, at most 64 MiB compressed or decoded. The full image is the frame; there is no
animation/atlas metadata, speculative animation system, or 3D asset dependency.
The build validator checks signature, chunk bounds/CRCs, dimensions, compressed
pixel size, row filters, and rejects APNG. Unsupported formats fail explicitly.

## Required validated build

From the repository root, with Python 3.10+ and Odin on PATH:

```sh
python tools/build.py
```

This is the supported **build-time** validation entry point, verified on Windows
with Python 3.14 and Odin `dev-2026-01-nightly:7fa05f1`. It recursively scans JSON
under `assets/config` and `assets/levels`, validates every `sprite` field, checks
file existence, exact path casing (including on Windows), containment under assets,
and PNG contents **before invoking** `odin build src/app -out:build/colony-reboot.exe`.
A failure identifies the source JSON, field/index and path and exits nonzero without
invoking the compiler. Empty/absent fields are deliberately ignored. Non-Windows
output is `build/colony-reboot` but that platform is not verified here.

`python tools/build.py --check-assets` runs just this validation. It validates
sprite references, not the full game configuration schema (covered by config tests
and startup). Unreferenced PNGs are not runtime dependencies and are not scanned.

**Direct `odin build`, `odin check` and `odin test` do not run Python or check sprite
file existence.** They remain useful compiler/headless checks but are not the
validated release build. No Odin compile-time hook is claimed. The validator reads
the current external catalogs; changing assets after building requires rerunning
the build. Deploy the assets tree alongside the game and run from the repository
root; startup still diagnoses missing/corrupt textures rather than silently using
color for an explicitly configured sprite.

## Startup, ownership and errors

Startup loads and validates role metadata after buildings and before subject types,
once before opening the window. Complete coverage of the existing enum ensures
that every role a subject can reference has metadata. `load_roles` publishes the
array only after successful validation. Missing files and invalid contents identify
`assets/config/subject_roles.json` in the startup console diagnostic.

Decoded IDs, sprite paths, arrays and partial allocations on failure belong to the
startup allocator. Display names borrow localization storage. The composition
layer's startup arena outlives catalog/logic/UI use and is freed at shutdown. All
returned slices/strings are read-only by contract; clone before modifying them.
There are no additional queues, callbacks or threads. After opening the window,
the app collects building/role paths and render deduplicates them in a graphics-thread
cache. Each unique texture is loaded once, with nearest-neighbor filtering; draws
only look up cached handles, never load/decode files. Init failure releases partial
textures and aborts startup. `render.close` unloads all textures before closing the
GPU context. Paths borrow the configuration arena; GPU types remain entirely in render.
[Development Ctrl+R reload](development-reload.md) also rereads roles and sprite files.
Cache replacement is transactional: failure unloads only staged textures and retains
old handles/strings; success releases the old cache before the old configuration arena
is freed. The fixed UI font and graphics context survive level reload.

Building sprites use their existing screen rectangle. Moving subjects use the first
role in their runtime role list with a nonempty sprite; transport manifest icons use
the subject type's role order. Without a role sprite they retain the existing subject
color. Ships/resources/stations have no sprite field in the current contract and
retain their existing presentation. Role priority is cosmetic, not job assignment.
Static frames use top-left screen coordinates (+X right, +Y down), top-left pivot,
full-frame stretching, white tint and standard straight-alpha blending. Camera
projection is unchanged; sprite destination rectangles are rounded to screen pixels
for this pixel art. This final render-only alignment never changes movement or
input coordinates. Empty-sprite color fallbacks retain their original geometry.

## Asset editor

The Files menu discovers `config/subject_roles.json` automatically. Its specialized
form uses a selectable role list on the left (localized name, ID and color) and
only the selected role's properties on the right. It edits ID, localized name key,
RGB color and sprite path, reorders definitions without changing the selected role,
and selects newly restored required jobs. Empty catalogs show an explicit empty
state; invalid rows remain selectable for JSON repair. This master-detail layout
is the convention for future list editors (see `AGENTS.md`), without requiring
unrelated existing editors to be rewritten. Removal is explicit and causes validation
errors until the missing job is restored. Names in subject-type and level-subject
role pickers come from this catalog and English localization; their saved values
remain untranslated IDs. Developer-only fallback labels are raw IDs.

The building and role forms include optional sprite-path fields; newly created
entries use an empty path. Renaming IDs does not rename files or silently rewrite
custom paths. Both browser forms validate syntax only and point users to the
validated build for filesystem checks. Existing undo/save and localization-reference
tracking remain unchanged.

## Verified tests

```sh
python -m unittest discover -s tools -p 'test_*.py' -v
odin test src/config -out:build/task4-config.exe
odin test src/app -out:build/task4-app.exe
node --test manage/test/*.test.js
odin run tools/sprite_smoke -out:build/sprite-smoke.exe -define:SPRITE_GPU_TEST=true
```

Python tests cover present/missing paths, role/nested/level fields, empty fallback,
invalid types/syntax/casing, non-PNG/corrupt files, dimensions, deterministic art,
and validation-before-compiler ordering. Odin tests cover role priority, borrowed
path collection and optional config fields. The GPU smoke command opens a hidden
window, verifies actual pixel readback (sprite, transparency, color fallback), cache
deduplication, partial failure cleanup, reload and shutdown. It writes ignored
`build/sprite-smoke.png` for inspection. It requires a graphics driver; verified on
AMD Radeon 780M/OpenGL 3.3. It is separate from the headless suites because linking
the Odin testing runtime with this raylib build produced Windows CRT conflicts.

Manual game check: Play, pan/zoom buildings, inspect their overlays, observe role
sprites leaving the landing platform and in transport cards. Blank a sprite and
rebuild to check color fallback; set an invalid path and verify `python tools/build.py`
fails before compilation. Restore valid data before continuing. FIFO holding and
landing rules must remain unchanged.
