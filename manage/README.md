# Asset Manager

Local web tool (Node + React) to visually edit the JSON files in `../assets`.
It is a development tool only; the game never depends on it.

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

## Features

- **config/buildings.json** — array of building types identified by `id`: code,
  localization keys with live English preview, size preview (64 screen units per
  world unit), RGB color picker, power values, needs/produces with pickers fed by
  `config/resources.json`. Renaming an `id` offers to update `building_id` in levels.
- **config/resources.json** — array of resources identified by `id`, with the list
  of building types using each one. Renaming an `id` offers to update the
  `resource_id` references in `buildings.json`.
- **levels/*.json** — map of the level (world origin at centre, X right, Y down,
  dashed 1280×720 window reference). Drag to move with snapping, scroll to zoom,
  drag the background to pan, arrow keys nudge, Del removes. Inspector for
  ID, `building_id`, position, health, and repairing; list reordering changes draw
  order. The `+` next to *levels* creates a new level file.
- **localization/en.json** — searchable key/text table, rename/delete with
  reference warnings, list of keys referenced by other assets but not defined.
- Any other JSON — generic tree editor. Every file also has a raw **JSON** tab.
- Undo/redo per file (Ctrl+Z / Ctrl+Y outside text fields), Ctrl+S saves the
  current file, Ctrl+Shift+S saves all. Reference updates in other files are
  separate unsaved edits in those files.

## Validation and saving

`src/lib/schema.js` holds the validation rules (required/unknown fields, types,
unique IDs and codes, cross-file references, ranges), modelled on the strict
loaders in `src/config` and `src/localization`. Keep it in sync when the Odin
structures or the JSON layout change. Errors are shown under the editor; saving
a file with errors asks for confirmation. `npm test` checks the rules against the
shipped assets and against edits the game loader rejects (`test/schema.test.js`).

Saving preserves key order and each file's formatting style (`src/lib/format.js`):
files that keep short objects on one line (`"color": { "r": 0, ... }`) are written
the same way, fully expanded files stay expanded, and a trailing newline is kept
if present. Writes go through a temporary file and rename; the server refuses
invalid JSON. If a file changed on disk since it was loaded, the save asks before
overwriting. The game reads JSON at startup, so restart it after saving.
