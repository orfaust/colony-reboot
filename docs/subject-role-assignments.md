# Subject Role Assignments

In `assets/config/default/subjects.json`, `roles` is now an ordered array of objects:

```json
"roles": [
  { "role_id": "worker", "sprite": "" },
  { "role_id": "repairer", "sprite": "" }
]
```

`role_id` is required and must be worker, supervisor or repairer, without duplicate
IDs within a subject type. `sprite` follows the existing optional sprite contract:
omitted or empty means unset; otherwise it must be a normalized repository-relative
`assets/.../*.png` path. Null or non-string sprite values are invalid. Unknown
fields and legacy string role entries are rejected by startup validation. `roles`
itself remains required and accepts null or [] for no roles.

Migrate each catalog string such as `"worker"` to
`{ "role_id": "worker", "sprite": "" }`. Do not migrate level-instance `roles`:
those remain arrays of string IDs, validated against the type's `role_id` values.
The role catalog `subject_roles.json` has since dropped its `color` and `sprite`
properties and keeps only `id` and `name_key`; subject rendering never reads it for
presentation.

## Ownership and presentation

`logic.Subject_Type.roles` contains `Subject_Role_Definition` values with enum
`role_id` and borrowed immutable `sprite` strings. Transport initialization creates
one owned enum-only projection per subject type. Runtime subjects borrow those
projections (or level-instance role arrays); resets reuse them and transport
destruction frees them. No per-subject or per-frame allocation is introduced.
Gameplay eligibility and inspector role counts remain enum-based.

The application stages nonempty assignment sprites at startup/development reload.
For each eligible role in declared order, presentation selects its per-type sprite
if set, otherwise `subject.sprite`, and finally the subject type color. The first
role with a sprite wins; role order never affects eligibility or job assignment. Moving subjects only
consider their individual role IDs; transport cards use the type's role order.
Build-time asset validation already recursively checks these paths. No new artwork
is supplied and shipped overrides are empty, so shipped visuals are unchanged.
Subject-level `width`/`height` remain unused presentation metadata. `subject.sprite`
is the fallback image, and per-role overrides win over it.

## Editor

Subject role assignments use a nested master-detail editor: list, add and ordering
controls on the left, selected role ID/path and removal on the right. Reordering
keeps the moved row selected; additions select the new row. Duplicate new IDs are
prevented. Existing malformed/legacy entries remain visible with explicit repair
or removal, rather than being silently converted. Unknown object properties and
field-specific history keys are preserved by normal edits.
