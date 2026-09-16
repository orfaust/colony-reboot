# Ship and Subject Presentation Metadata

The ship catalog (`assets/config/ships.json`) now exposes:

- `sprite`: optional repository-relative PNG path string. Omitted or `""` means unset.
- `width`, `height`: required finite, strictly positive f32 dimensions in world units,
  consistent with building dimensions. Fractional dimensions are valid. Values that
  overflow f32 or round to zero are rejected.

Example fields on a ship definition:

```json
"sprite": "",
"width": 1,
"height": 1
```

The subject **type** catalog (`assets/config/subjects.json`) has the same optional
`sprite` path property and required `width`/`height` with the same finite positive
f32 world-unit contract. These are not fields on individual level subjects. They do
not replace or modify the existing `subject_roles.json` sprite definitions.

Nonempty sprite paths follow the existing convention: `assets/.../*.png`, relative
to the repository root, forward slashes, no parent traversal, empty/dot components,
backslashes, colons, NULs or surrounding whitespace. Null and non-string values are
invalid; only omission or the empty string disables a path.

## Ownership and current behavior

The fields are available as `logic.Ship.sprite`, `logic.Ship.width`,
`logic.Ship.height`, `logic.Subject_Type.sprite`, `logic.Subject_Type.width` and
`logic.Subject_Type.height` after startup or development
reload. Paths borrow immutable catalog allocator storage, just like names and IDs;
no textures or backend handles are stored in logic. Simulation rules, flight timing,
passenger capacity, role assignment and snapshots are unchanged.

This is a **data-structure change**, not a rendering change. Ships retain their
existing drawing dimensions and color. Subject drawing still uses its existing
role-sprite selection. These new fields do not yet override that presentation;
the subject-level sprite still does not override role sprites. Per-type role
assignment overrides are documented in [Subject Role Assignments](subject-role-assignments.md).

The shipped ships use width/height 1 and empty sprite paths; shipped human/robot
subject types also use width/height 1 and empty sprite paths. No new artwork or fabricated paths are added.
The existing validated build (`python tools/build.py`) already checks every nonempty
`sprite` field in configuration/level JSON recursively, including these new fields.
The runtime JSON loader checks syntax only; direct Odin commands bypass the asset
existence check. Thus any nonempty configured path must name a valid existing PNG
for the validated build to succeed, even while its presentation use is pending.

## Asset editor and migration

The ship properties form exposes sprite, width and height, with world-unit labels
and validation. New ships receive an empty sprite and dimensions 1×1. The subject
properties form includes sprite and world-unit dimension fields; new types start
with an empty sprite and dimensions 1×1. Dimensions are also exposed by the catalog
grid. Forms
preserve custom paths, other fields, localization references and undo/history keys.

Existing custom ship and subject-type JSON must add both dimensions. Sprite fields remain optional
for older ships and subjects. Nulls and malformed loaded values are not silently
normalized. Paths are identifiers rather than player-facing text; existing localized
name keys remain unchanged. No new game UI strings are required.
