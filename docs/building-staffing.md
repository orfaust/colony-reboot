# Building Staffing

Building type definitions contain a required `subject_roles` array:

```json
"subject_roles": [
  { "role_id": "supervisor", "quantity": 2, "staffing_mode": "continuous" },
  { "role_id": "worker", "quantity": 0, "staffing_mode": "continuous" },
  { "role_id": "repairer", "quantity": 1, "staffing_mode": "on_demand" }
]
```

Each entry requires all three fields. `role_id` is one of worker, supervisor or
repairer and must be unique within the array. `quantity` is a nonnegative integer
because it counts individual physical slots; fractional and overflowing values are
rejected. `staffing_mode` is one of:

- `continuous`: the scheduler keeps every slot covered while the building is enabled.
- `on_demand`: no automatic assignment until a future explicit request system exists.

Zero quantities, `on_demand` entries and empty arrays are allowed. Null arrays,
missing fields, unknown fields/IDs, duplicate IDs, fractional or negative
quantities and unknown staffing modes fail startup validation with actionable paths.
The former `required` boolean is rejected; migration maps `required: true` to
`continuous` and `required: false` to `on_demand`. The old scalar staffing fields
are not accepted.

## Migration and ownership

The shipped definitions map every `required: true` entry to `continuous` and every
`required: false` entry to `on_demand`, keeping the integer quantities unchanged.
Custom JSON must migrate explicitly. No automatic normalization of loaded editor
data is performed.

Odin exposes `Building_Type.subject_roles: []Building_Subject_Role`, where the entry
contains enum `role_id`, int `quantity` and enum `Staffing_Mode staffing_mode`.
`logic.has_continuous_slot` reports whether a type exposes a continuous slot with a
positive quantity for a role; level subjects' `initial_assignment` metadata is
validated against it. This is immutable catalog-owned data and lives as long as the
catalog, including across a running session; successful development reload replaces
it with the candidate catalog. No graphics handles or pointers into mutable
simulation storage are introduced.

## Runtime slots and coverage

`logic.Staffing` materializes one stable slot per continuous unit in building-array
order, then catalog role-entry order, then ascending `slot_index`. `on_demand`
entries and zero quantities create no automatic slot and stay ignored until a future
explicit request system exists. Each slot tracks a physical `occupant` and a
`reserved` replacement independently by building, role and `slot_index`, so two
subjects can never cover one slot or reserve it twice. A reservation may target a
slot the incumbent still covers: it schedules the coming handoff without changing
current coverage.

`logic.derive_staffing(&game,&fleet)` rebuilds claims and per-building coverage once
per fixed tick after movement. A slot is covered only by a physically arrived
eligible subject: live, non-medical, non-evacuating, health at or above
`min_work_health`, supporting the role, in a work phase and inside the assigned
building. Invalid claims (disablement, subject health, medical state, role
incompatibility, stale slot) are released, never silently dropped: a released worker
starts required rest where it stands, and a released rest-complete reserved subject
returns to idle. Conflicts between two claimants resolve in favour of the lower
stable subject ID, independent of array order.

`staffed` is derived as `covered == required` for each building; a building with no
continuous slots is vacuously staffed. It is independent of the player-requested
`active` state and never changes it. `Building_Snapshot.staffed` exposes the flag and
`Staffing_Coverage` reports required/covered/reserved counts per role entry.

An enabled building that is not fully covered produces no electrical output while it
keeps its full power demand, stays enabled and never enters cooldown; warmup and
cooldown remain tied only to real activation and deactivation, so coverage returning
resumes output immediately at the current startup level. Staffing is evaluated
before power each fixed tick, and a command can never start a network on missing
personnel. Coverage changes publish edge-triggered `Staffing_Lost` /
`Staffing_Restored` events, once per transition and only for buildings that stay
enabled; see [Power](power.md#staffing) for the electrical rules. The application
renders both staffing notices through the `notice_staffing_lost` and
`notice_staffing_restored` templates, whose required `{name}` and `{id}` placeholders
are filled with the affected building's localized type name (the `name_key` text from
`buildings.json`) and its level instance ID, for example `Meals Factory (MF1)`. The
immediate toggle-feedback notices follow the same convention; see
[AGENTS.md](../AGENTS.md).

Level initial assignments start on shift: the subject is placed at the assigned
building in the first free `slot_index` of that role in level-subject order, with
`phase = Working` and `work_hours = 0`. Startup validation rejects more initial
assignments than continuous slots and rejects a level whose total continuous slots
exceed `STAFFING_SLOT_LIMIT` (1024), so materialization never truncates and no
subject is silently dropped. Reset clears every derived claim before the subjects
are rebuilt; a successful development reload builds a fresh session and a failed one
preserves the previous session, so stale claims cannot survive either path.

The building inspector presents live staffing coverage. For each continuous role it
shows `{covered}/{required} covered`, a separate `{role}: {reserved} arriving` line
when replacements are scheduled, and `Uncovered continuous slots: {count}` while any
slot lacks a physical occupant. Configured `on_demand` quantities are shown as
`{role}: {quantity} on demand`; a building with no continuous slots reports the
localized "No continuous slots" state. Coverage comes from
`logic.staffing_coverage` (physical occupants, not reservations), so the inspector no
longer counts assumed assignments from the temporary `occupation` bridge.

Below the coverage block, the inspector lists each individual associated with the
building (resident, physically assigned, or reserved) as a fixed-size detail block:
subject name and stable ID, health, work/medical phase, role, assignment slot,
work/rest/idle timers, medical status, and one line per need with fulfillment and
any shortage hours. Removed individuals are never listed, and a building with nobody
associated shows the localized "No individuals" state. All labels and formats come
from `assets/config/default/localization/en.json`.

Resource production runs hourly behind the same derived coverage, so an unstaffed
building consumes no production input and creates no product while it keeps its full
demand; see [Building production](building-production.md#gating). Physical handoff
and the medical rules are documented in
[Subject Runtime Contracts](subject-runtime-contracts.md).

## Shift scheduler and reservations

`logic.schedule_staffing(&game,&fleet)` runs once per fixed tick after
`derive_staffing`, so stale reservations have already been cancelled and are
replaced in the same tick. A reserved subject continues normal rest recovery until
rest completes, and a reserved subject is never considered for another slot.

Candidate ordering is deterministic and uses only authoritative state:
compatible role and health eligibility filter first, then forecast arrival
(remaining required rest plus straight-line travel time from the individual's
current position at its configured speed), then longest availability (the subject
type's nominal `work_time`; with mixed types the longer shift wins a tie), then
straight-line distance, then the stable subject ID. Station stock, onboard people
and station-side boarding are never candidates; they become available only after
landing-platform discharge.

An uncovered slot is filled immediately with its best candidate: coverage is needed
now and the individual rests normally before the shift lifecycle moves it to work.
For a slot whose incumbent is still working, the scheduler is deliberately
just-in-time: it reserves a replacement only when the forecast arrival is within one
fixed tick of the incumbent's remaining `work_time`. While both the candidate rests
and the incumbent works that difference stays constant, so the request lands in the
final part of rest and travel starts as soon as rest completes, reaching the
building by shift end. A candidate that would arrive later is not reserved early;
once the incumbent enters `extra_working`, the earliest-arriving eligible candidate
is requested regardless of lateness. Invalidation (health, medical state,
disablement, slot removal, role incompatibility, reset or reload) cancels the claim
and the same tick's scheduler pass replaces it.

`logic.step_shifts` and `logic.commit_shift_handoffs` (in `src/logic/shift.odin`)
turn reservations into physical shifts: a rest-complete reserved subject walks to
the building, and on arrival the incumbent is released and the replacement takes the
slot in the same tick, so coverage never shows an uncovered tick between consecutive
shifts. `work_hours` advances the shift, `extra_working` begins at `work_time` and
loses health, `extra_work_time` expiry (or health/medical ineligibility) releases the
subject to rest where it stands, and a completed rest with no reservation begins
inactivity. See [Subject Runtime Contracts](subject-runtime-contracts.md) for the
per-tick order.

The scheduler is bounded: each pass examines at most `SCHEDULER_SLOT_BUDGET` (128)
materialized slots and performs at most `SCHEDULER_EVALUATION_LIMIT` (65536) subject
evaluations. A bound that cuts the pass short leaves the remaining slots exactly as
they are and retries them next pass; the slot cursor and the subject-scan cursor
rotate so no slot or subject is permanently ignored, and `Scheduler.deferred` counts
deferred slot examinations. Deferral never drops a subject and never changes a
reservation; with no eligible candidate the slot simply stays open.

## Editor and validation

The building editor keeps the compact three-column staffing matrix that is an
explicit exception to the master-detail convention: role name, an integer quantity,
and a staffing-mode select. Missing assignments show defaults (continuous for
supervisor/worker, on demand for repairer) and are added only when edited. Malformed
loaded entries stay visible for explicit repair in the JSON tab, unknown fields are
retained on normal edits, and field-level undo/history keys remain distinct.

Tests cover zero/fractional quantities, both staffing modes, invalid shapes and IDs,
duplicate IDs, missing fields, nonfinite quantities, legacy `required` rejection,
inspector counts, and SSR rendering without data mutation.
