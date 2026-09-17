# Asset Manager

Local web tool (Node + React) to visually edit the JSON configuration versions in
`../assets/config`. It is a development tool only; the game never depends on it.

## Requirements

Node.js 20 or newer (verified with Node 24.11.1 / npm 11.6.2 on Windows).

## Run

From this directory:

```sh
npm install
npm run dev        # http://127.0.0.1:5173 (Vite + API in one process, hot reload)
```

Production-style run without Vite:

```sh
npm run build
npm start          # http://127.0.0.1:5174 (override with PORT / HOST)
```

Set `ASSETS_DIR` to edit a different assets directory. The server binds to
localhost only and has no authentication: do not expose it on a network.

## Configuration versions

Every configuration version is one self-contained directory under
`assets/config/<name>` (`default`, then whatever you add for experiments). Each
version holds the same documents: `buildings.json`, `resources.json`,
`subjects.json`, `subject_roles.json`, `ships.json`, `space_stations.json`,
`key_bindings.json`, `levels/*.json` and `localization/en.json`. Sprites under
`assets/sprites` stay shared.

The **Version** selector in the top bar lists the available versions and scopes
all editing to the selected one; versions are never merged, and switching reloads
every document from the new directory. **+ New** duplicates the current version
under a new name (validated as 1-64 letters, digits, `-` or `_`), and **Delete**
removes a non-default version after confirmation. Unsaved changes block version
switching, creation and deletion until they are saved or discarded.

The game reads the same directories, so a version created here runs with
`odin run src/app -- --config <name>` (or `-define:CONFIG_PROFILE=<name>`).

## Features

Ship/subject sprite fields and dimensions currently store metadata only; they
must not be confused with the per-role subject sprites or current ship draw sizes.
See [Ship and Subject Presentation Metadata](../docs/ship-subject-presentation.md).

- **Files menu** in the top bar replaces the directory path and permanent sidebar.
  It groups the selected version's assets by folder, shows the active file, error counts and unsaved markers,
  and keeps the new-level action. It closes on selection, Escape, outside click or
  when keyboard focus leaves it; Escape and selection return focus to the trigger.
  Use Tab/Shift+Tab to navigate its buttons. The editor uses the full window width.

- **buildings.json** — array of building types identified by `id`: code,
  localization keys with live English preview, size preview in pixels, RGB color picker, optional repository-relative PNG `sprite` path,
  power values, always on, warm-up/cooldown, operative health,
  materials, staffing (`subject_roles`: a three-column table showing localized role
  name, an editable whole-number quantity and a staffing-mode select). Every role from the role catalog
  has a row, in catalog order. Missing assignments display zero quantity and the
  standard mode default (on demand for repairer, continuous otherwise); only editing a cell creates that
  assignment. Rendering never changes the JSON. Duplicate assignments are blocked;
  unknown/malformed rows remain preserved for repair in the JSON tab. Unknown fields,
  validation and normal undo/history are preserved. This compact staffing matrix is
  an intentional exception to the default master-detail list convention. Also includes residents (subject type and capacity), needs/produces/storage (with capacities) with pickers fed by
  `resources.json`. Renaming an `id` offers to update `building_id` in levels.
- **resources.json** — array of resources identified by `id`, with the list
  of building types using each one. Renaming an `id` offers to update the
  `resource_id` references in `buildings.json` and `subjects.json`.
- **subject_roles.json** — identity metadata for `worker`, `supervisor`,
  `repairer`: ID and localization name key, with no color or sprite. All three are
  required once;
  a left-hand selectable list and right-hand selected-role properties, using the
  shared responsive master-detail layout. The form restores and selects missing
  roles, supports confirmed removal and preserves selection while reordering.
  Only one role's fields are shown at a time; malformed entries remain repairable
  through the JSON tab. Role
  pickers in subject types and levels use the localized catalog names, saving IDs.
  Role/building sprite fields validate normalized `assets/.../*.png` paths only:
  no upload, file creation or existence check. **Browse…** lists PNGs already under
  `assets/`; choosing one only sets the path after confirmation. When a path is set,
  a read-only preview is shown from the `GET /api/image` endpoint, which serves PNGs
  inside `assets/` and refuses traversal or other extensions. A missing or unreadable
  file shows an inline message and never blocks editing or saving. Previews use
  nearest-neighbor rendering to match pixel art. Run `python tools/build.py` at the
  repository root for required pre-compilation file and PNG checks. See
  [Role Metadata and Sprite Paths](../docs/roles-and-sprites.md).
- **subjects.json** — array of subject types identified by `id`: name key, color, optional `sprite` path, required positive pixel `width`/`height` (new types: 64×64), and
  hourly needs (`amount_per_hour`, `shortage_alert_time`, `shortage_max_time`,
  `satisfied_health_gain_per_hour`, `max_shortage_health_loss_per_hour`; at most
  `SUBJECT_NEED_LIMIT` (8) per type, matching the runtime's fixed per-subject need
  arrays), rest/work/overtime
  hours (`rest_time`, `work_time`, `extra_work_time`), health thresholds
  (`min_work_health`, `min_colony_health`) and the `health_rates` object, roles (`{role_id, sprite}` objects in a responsive nested master-detail editor;
  none is saved as `null`). The role list shows localized names and subject
  sprite inheritance. Choose an unused role before adding; new entries
  are selected. Row ordering controls preserve selection even when a neighbor moves.
  The selected detail has duplicate/invalid-ID diagnostics, a sprite override path
  with Browse, and the inherited subject sprite. Removal and resetting malformed data require
  confirmation; legacy entries remain explicitly repairable and unknown fields are
  preserved, and produces (resource and units per hour). Renaming an `id` offers to update `subject_id` in levels and `residents.type` in buildings.
- **key_bindings.json** — searchable actions grouped into menu, camera/world
  and simulation controls. Compact rows separate device and input selection, show
  customized actions and inline errors, and support add/remove/reorder plus confirmed
  per-action or global reset. Pickers exclude duplicates within an action and wheel
  inputs for pan; the last input cannot be removed. Existing malformed data remains
  visible for repair. Validation rejects unknown inputs, empty actions and duplicates.
- **ships.json** — left-hand list and right-hand properties, with predefined ID, code and RGB color (picker and numeric channels), localization name key, validated type (`transport` or `emergency`), optional `sprite` path, positive pixel
  `width`/`height` (new ships: 64×64), maximum speed (`max_speed`, km/h), acceleration/braking duration (`max_speed_hours`, hours), cargo throughput (`units_per_hour`, units loaded/unloaded per simulated hour; zero prevents dispatch), and
  subject capacities (`subject_id`, `capacity`) with subject-catalog pickers.
  New ships start with a unique ID, transport type, and empty `subjects`; adding a
  subject row uses capacity 100. References, duplicates, and capacities are validated. Duplicate/delete/reorder
  controls are available; new name keys must be added to English localization.
- **space_stations.json** — array with a left-hand list and right-hand properties,
  unique station IDs, display codes, name keys and resource/subject/ship stock lists.
  Ship and station lists show the code instead of the ID; ships also show a color swatch. New, duplicate,
  delete and reorder work like the other catalogs; an empty list is allowed. This
  replaces the former singular `space_station.json` object. Stock rows come
  with catalog pickers. New rows use the first unused catalog ID and capacity 100
  for resources/subjects, or zero units for ships. Resource/subject quantities and
  hourly rates belong to the level instance, not the template.
  Inline and document validation check references, duplicate stocks,
  capacities and integer ship counts. Catalog ID changes require manual updates
  to station references; errors remain visible until repaired.
- **levels/*.json** — two tabs: **Map** (map and building instances) and
  **Space station** (station template and level stock). Switching tabs preserves
  map view, selection and unsaved edits. Arrow keys/Home/End navigate the tab bar.
  The Map tab fills a viewport-bounded height without page scrolling. Building
  properties and the instance list scroll inside the right sidebar, including on
  narrow screens; the sidebar can also receive keyboard focus for scrolling.
  Map of the level (world origin at centre, X right, Y down,
  dashed 1280×720 window reference). Choose a building type and enable the **+**
  toggle to place buildings by clicking the map. The cursor becomes a crosshair;
  positions respect pan, zoom and snap. Each click creates and selects a new instance
  with the existing defaults and its own undo step. Placement stays enabled for
  repeated clicks; toggle it off or press Escape while the map is focused to resume
  selection/dragging. The toggle is disabled without a valid building type.
  Drag to move with snapping, scroll to zoom,
  drag the background to pan. Arrow keys nudge and Del removes only while the map
  has keyboard focus, never while navigating menus or editing another panel.
  Deletion asks for confirmation; occupied residences must be reassigned first,
  while deleted workplaces clear subject initial assignments. Committed building ID renames
  update residence and initial-assignment references in the same undoable edit. Reordering
  preserves selection even when moving a neighboring entry. Inspector for
  ID, `building_id`, position, health, repairing, `enable_at_start` (forced on for always_on types), `residents_amount` (only for types with residents), and `stored` (one amount per resource the type
  needs, produces, or stores, up to its capacity; “Sync stored” realigns stored and residents_amount after the type's needs, products, storage, or residents change); list reordering changes draw
  order. The former Subjects section is no longer displayed. Existing `subjects`
  data is preserved and remains editable through the JSON tab; reference validation
  and building rename/deletion safeguards remain active. A station panel edits the required `space_station.distance` in km (finite,
  nonnegative; initially zero) and selects the level's required `space_station.station_id`
  and edits resource/subject units and signed hourly rates (subject quantities require
  integers; fractional subject rates accrue into whole subjects during play), bounded by template
  capacities. “Sync stock with template” keeps matching values, seeds new entries
  with zeroes and removes obsolete IDs without clamping invalid quantities.
  The `+` next to *levels* creates a new level file using the first available station
  template; creating a level requires at least one station template.
- **localization/en.json** — searchable key/text table, rename/delete with
  reference warnings, list of keys referenced by other assets but not defined.
- Any other JSON — generic tree editor. Every file also has a raw **JSON** tab.
- Undo/redo per file (Ctrl+Z / Ctrl+Y outside text fields), Ctrl+S saves the
  current file, Ctrl+Shift+S saves all. Reference updates in other files are
  separate unsaved edits in those files.

### Navigation smoke check

Open **Files**, select an asset, and verify its editor opens and the menu closes.
Check unsaved/error markers, the new-level action, Escape, outside clicks and
Tab/Shift+Tab focus. Switch the **Version** selector and verify the file list
reloads for the new version; use **+ New** and **Delete** to manage a test
version. Resize below 720px: the version selector and the file trigger move to
their own header rows and the scrollable popup should remain inside the viewport.

Building/subject product and level station stock `units_per_hour` inputs
shows a read-only **Hours per unit** preview below it: `1 / units_per_hour`, up to
six significant digits. Zero shows infinity, negative rates retain their sign,
and invalid/missing numbers show a dash. The preview is not saved in JSON.

### Edit a translation from an element card

Click the translated preview below a localization key (for example “Robot transport”),
or focus it with Tab and press Enter/Space. The existing native text prompt opens
with the current English text: confirm to apply, or Cancel/Escape to discard.
This works for names, descriptions and unit labels wherever a key picker appears.
It changes only the value in `localization/en.json`, not the stable key or element
file. Shared references immediately display the new text. Empty translations are
also editable; absent keys retain the **Add text** action.

Changes remain unsaved and use normal localization validation and history. Save
`localization/en.json` or use **Save all** (Ctrl/Cmd+Shift+S); saving only the element
file does not save localization. Undo/redo the translation in the localization file.
Cancel and unchanged confirmation do not add history entries. Missing placeholders
or empty confirmed text remain validation errors rather than being silently fixed.

### Rename a translation key from an element card

Use **Rename key…** beside a localization field (Tab then Enter/Space also works).
Enter a lowercase key matching `[a-z][a-z0-9_]*`, then confirm the affected file and
reference counts. Cancel either dialog to leave all documents and histories unchanged.
The translated value is preserved. All shared references declared by the building,
resource, subject, role, ship, station and level schemas are updated together in
memory; arbitrary text and unknown fields are never search-and-replaced.

Missing/invalid source text, existing destination keys (even with identical values),
dangling destination references, unreadable documents and references outside known
schema fields block the rename with a diagnostic. Required game-code keys cannot
be renamed. Typing into the key input still changes only that reference; use the
explicit rename action to move the translation and its references.

Undo/redo from any affected document restores the entire rename atomically. Later
edits in another affected file must be undone first; reloading files or discarding
a redo branch can block the transaction rather than partially applying it.
**Save all** persists all affected dirty files using existing validation and conflict
checks. Disk writes remain per-file, not a filesystem transaction: if one save fails,
resolve that failure and save the remaining dirty files before running the game.

### Common-field grid mode

Click the sidebar list title (for example **Building types**) or focus it and press
Enter/Space to open an editable table. This is available for buildings, resources,
subject types, subject roles, ships and space stations. Each row represents one
item; columns are declared scalar fields and RGB color present in every item.
Unknown fields, nested lists and fields absent from any row remain in the detail/JSON
view. The ID column stays pinned while scrolling horizontally. Click an ID (or
focus its button and press Enter/Space) to open that exact row in the detail view;
row selection works even with duplicate IDs. IDs are read-only in the grid: use
the existing detail actions for reference-safe renames. Empty/malformed lists show a repair message rather than inferred defaults.

Cell edits use the normal document history, dirty state, validation and saving.
Localization cells retain preview editing and explicit key renaming. The grid scrolls
horizontally/vertically and displays cell validation errors. **Back to details**
restores the existing selection and focuses the list title. Master-detail remains
the default; the grid is an optional bulk-editing view, not a replacement.

## Validation and saving

Required station and building-info UI texts are tracked as game-code references,
so localization cleanup must retain them. Validation checks their format placeholders
as well as power and clock placeholders; missing keys must be restored, not replaced
with hardcoded game fallbacks.

`src/lib/schema.js` holds the validation rules (required/unknown fields, types,
unique IDs and codes, cross-file references, ranges), modelled on the strict
loaders in `src/config` and `src/localization`. Keep it in sync when the Odin
structures or the JSON layout change. Number fields accept only a dot as decimal
separator, whatever the browser locale (`src/lib/number.js`): text with a comma is
flagged and not applied; arrow keys step the value. Errors are shown under the editor; saving
a file with errors asks for confirmation. `npm test` checks the rules against the
shipped assets and against edits the game loader rejects (`test/schema.test.js`).

Saving preserves key order and each file's formatting style (`src/lib/format.js`):
files that keep short objects on one line (`"color": { "r": 0, ... }`) are written
the same way, fully expanded files stay expanded, and a trailing newline is kept
if present. Writes go through a temporary file and rename; the server refuses
invalid JSON. If a file changed on disk since it was loaded, the save asks before
overwriting. The game reads JSON at startup, so restart it after saving.
