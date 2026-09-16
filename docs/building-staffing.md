# Building Staffing

Building type definitions now contain a required `subject_roles` array instead of
`supervisors_required`, `workers_required` and `repairers_required`:

```json
"subject_roles": [
  { "role_id": "supervisor", "quantity": 2, "required": true },
  { "role_id": "worker", "quantity": 0, "required": true },
  { "role_id": "repairer", "quantity": 1, "required": false }
]
```

Each entry requires all three fields. `role_id` is one of worker, supervisor or
repairer and must be unique within the array. `quantity` is a finite nonnegative
f32 value, preserving the old scalar quantity contract (including fractional
values). `required` must be a JSON boolean, not a string or number. Zero quantities,
optional staffing and empty arrays are allowed. Null arrays, missing fields,
unknown fields/IDs, duplicate IDs and negative/overflowing quantities fail startup
validation with actionable paths. The old scalar fields are no longer accepted.

## Migration and ownership

The shipped 11 building definitions preserve their old quantities, ordered as
supervisor, worker, repairer. The first two entries have `required: true`; repairer
has `required: false`, following the requested convention. Custom JSON must migrate
explicitly. No automatic normalization of loaded editor data is performed.

Odin exposes `Building_Type.subject_roles: []Building_Subject_Role`, where the entry
contains enum `role_id`, f32 `quantity` and bool `required`. This is immutable
catalog-owned data and lives as long as the catalog, including across a running
session; successful development reload replaces it with the candidate catalog.
No graphics handles or pointers into mutable simulation storage are introduced.

Staffing remains metadata: the inspector reads quantities from the new array and
continues showing assigned/target counts in its existing localized role lines.
An omitted role has target zero. `required` distinguishes mandatory versus optional
staffing in configuration but does not yet gate activation, production or repairs;
this migration does not add staffing simulation rules or change power/health locks.
The inspector does not currently display a separate required/optional marker.

## Editor and validation

The building editor uses a nested master-detail list. Add/order controls stay with
the list; role ID, quantity, required flag and removal act on the selected row.
New buildings receive all three entries with zero quantities and the flags above.
New entries use an available supported role ID; duplicate creation is prevented.
Selection follows additions/reordering, and removal handles empty lists explicitly.
Malformed loaded entries stay visible for explicit repair/removal, unknown fields
are retained on normal edits, and field-level undo/history keys remain distinct.

Tests cover zero/fractional quantities, both required values, invalid shapes and
IDs, duplicate IDs, missing fields, wrong boolean types, nonfinite quantities,
legacy rejection, inspector counts, and SSR rendering without data mutation.
