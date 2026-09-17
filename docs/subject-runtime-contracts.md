# Subject Runtime Contracts and Health State

Status: **data foundation, staffing-slot model, staffing-dependent operation, shift
scheduler, shift lifecycle, medical evacuation/death, emergency medical transport,
station hospitalization/return, hourly building production, individual need
fulfillment, automatic load shedding
and UI/localization presentation implemented**. This
document
records the contracts and runtime state introduced by roadmap tasks 2 ("Shared views,
commands, and events"),
3 ("Runtime subject health and need state"), 4 ("Staffing-slot model and coverage"),
5 ("Building operation under staffing loss"), 6 ("Shift scheduler and reservations"),
7 ("Physical handoff, normal work, overtime, and rest"), 8 ("Medical state and
death"), 9 ("Emergency ships, batching, and priority landing"), 10 ("Station
hospitalization and return") and 11 ("UI, localization, and presentation") of the
[health and staffing plan](subject-health-and-staffing-tasks.md). The authoritative
behavior remains [Subject Health, Shifts, Staffing, and Medical Evacuation](subject-health-and-staffing.md).

## Shared contracts (`src/contracts/subjects.odin`)

`src/contracts` stays dependency-free and holds only stable IDs, value types and
event payloads. Nothing in this file points at configuration slices or at logic
storage.

| Contract | Purpose |
| --- | --- |
| `Subject_Role` | Shared, untranslated role vocabulary (`worker`, `supervisor`, `repairer`). Logic aliases it as `logic.Subject_Role`; configuration decodes the lowercase JSON names. |
| `Health` | Alias for a normalized `f32` in `[0,1]`. Logic clamps every update. |
| `Work_Phase` | Per-tick work/rest/idle phase (`Idle`, `Resting`, `Reserved`, `Moving_To_Work`, `Working`, `Extra_Working`). |
| `Shift_Assignment` | `{ building_id, role_id, slot_index }`; a stable value, never a pointer into another module's storage. |
| `Medical_Status` | Medical lifecycle orthogonal to phase and activity (`None`, `Pending_Evacuation`, `Evacuating`, `Hospitalized`, `Returning`). |
| `Need_Snapshot` / `NEED_SLOT_LIMIT` | One per-need runtime record copied into a view, plus the fixed per-subject capacity. |
| `Subject_Snapshot` | Read-only individual view: ID, type, residence, health, phase, medical status, assignment, position, timers and need records. |
| `Staffing_Coverage` | Required/covered/reserved slot counts for one building role entry. |
| `Sim_Event` / `Sim_Event_Kind` | Edge-triggered event payloads: staffing lost/restored, production blocked/resumed, per-building power shed, medical evacuation/return, death. |

### Ownership, mutability and lifetime

- Every contract value is plain data and is passed by value. Strings borrow
  validated level/catalog storage owned by the application arena and stay valid for
  the whole session. Consumers never free or mutate them.
- Snapshots are copies. Mutating a returned `Subject_Snapshot` (including its need
  records) never changes authoritative state, because it holds no pointer or slice
  into logic storage. `NEED_SLOT_LIMIT` bounds the fixed array, so a snapshot copy
  allocates nothing.
- Runtime assignments and reservations are values (`Maybe(Shift_Assignment)`), not
  pointers. `subject_view` and `subject_view_of` in `src/logic/subject_runtime.odin`
  are the only producers of subject views.

## Edge-triggered events (`src/logic/events.odin`)

`State` owns a fixed-capacity `Event_Queue`. Logic appends one event when a
transition happens, never once per tick. The application reads `pending_events`
in ascending `sequence` order, which is exactly the order in which transitions
happened during the fixed tick.

- Capacity: `EVENT_LIMIT` (128) events per session, no allocation.
- Overflow: when full, the **newest** event is rejected and `overflowed` increments.
  Already-queued transitions are preserved, and the drop stays observable. The
  counter is cumulative and survives `clear_events`.
- Payloads carry stable IDs only: `building_id` borrows level storage, `subject_id`
  is a `Subject_ID`. No logic pointers cross the boundary.

The implemented slices append the staffing, production, load-shedding, medical,
return and death transitions
through `push_event`; the application drains the pending events once per fixed tick
and turns each into one localized notice (see [UI, localization and
presentation](#ui-localization-and-presentation)). `Power_Shed` is emitted once per
building stopped by automatic load shedding, in shed order; the application groups
every `Power_Shed` event of one tick into a single localized notice.

## Runtime subject state (`src/logic/subject_runtime.odin`)

`Runtime_Subject` gained orthogonal fields:

- `health`: `f32` clamped to `[0,1]` by the health step.
- `phase`: `Work_Phase`, independent of physical `activity`.
- `work_hours`, `rest_hours`, `idle_hours`: timer data. Advancing and transitioning
  them is part of the shift lifecycle task, not this slice.
- `assignment`, `reservation`: optional `Shift_Assignment` values materialized by
  the staffing-slot task.
- `medical`: `Medical_Status`, populated by the medical task.
- `needs` / `need_count`: fixed `[NEED_SLOT_LIMIT]Need_State` per individual, built
  from the subject type at creation. Each record stores `resource_id`,
  `fulfillment`, the independent `shortage_hours` clock, and cached quadratic
  `shortage_severity` / `health_effect_per_hour`.

### Initialization and identity

- Explicit level subjects start at their configured `health`.
- Generated residents and station stock start at health `1`.
- Each individual gets one need record per configured need of its type, initialized
  to full fulfillment and a zero shortage clock.
- Subject IDs, level source IDs, transport manifests and movement flows are
  unchanged: adding the new fields does not re-key anyone. A removed slot is still
  reused only by fully overwriting the record, including health and need state.
- Startup validation rejects a subject type with more than `NEED_SLOT_LIMIT` needs
  (`subjects[%d]: at most 8 needs are supported per subject type`) instead of
  silently truncating it.

## Fixed-tick health calculation (`src/logic/subject_health.odin`)

`logic.step_subject_health(&fleet, elapsed_hours = TICK_HOURS)` runs once per fixed
tick, headlessly, before movement and transport. It rejects NaN, infinite, zero and
negative `elapsed_hours` (nothing changes) and, for every live subject:

1. Advances each need's independent shortage clock. Full fulfillment (`>= 1`) clears
   it; any missing amount advances it by `elapsed_hours`.
2. Computes each need's quadratic severity and signed effect:
   `gain = satisfied_health_gain_per_hour * fulfillment`,
   `loss = max_shortage_health_loss_per_hour * severity^2`, where
   `severity = clamp((shortage_hours - shortage_alert_time) / (shortage_max_time - shortage_alert_time), 0, 1)`.
   Before `shortage_alert_time` there is no loss. At and beyond `shortage_max_time`
   severity saturates at one. When alert and maximum times are equal, severity
   becomes one immediately at that time.
3. Adds the activity effect and clamps health:
   `health = clamp(health + sum(hourly_effects) * elapsed_hours, 0, 1)`.

Activity effects:

- `Resting`: `+rest_gain_per_hour`; `Working`: `+work_gain_per_hour`;
  `Extra_Working`: `-extra_work_loss_per_hour`.
- `Idle`: quadratic inactivity loss
  `max_inactivity_loss_per_hour * clamp(idle_hours / inactivity_max_time, 0, 1)^2`.
  A configured `inactivity_max_time` of zero disables the ramp instead of dividing
  by zero.
- `Reserved` and `Moving_To_Work` are activity-neutral, as is any subject who is not
  physically `Inside` a building (`.Station`, `.Reserved` boarding, `.Onboard`,
  `.Waiting`, `.Moving`). Need effects stay active in every phase and during
  transport.
- Positive activity always contributes near full health; clamping alone limits it.

### Need fulfillment input

The fixed-tick health calculation consumes the `fulfillment` of each need record;
lowering it advances that need's shortage clock and scales its positive gain. Since
phase 3 of the [building production plan](building-production.md) that value is
driven by `logic.step_need_fulfillment` from the runtime stock of the building the
subject is physically `Inside` (see
[Individual need fulfillment](#individual-need-fulfillment-srclogicfulfillmentodin)).
The health step itself is unchanged: it owns all shortage and health math, and
setting a record's `fulfillment` below `1` still advances the clock and scales the
gain, so full, partial and zero fulfillment remain directly testable.

## Runtime slot model

`logic.Staffing` (in `src/logic/staffing.odin`) materializes one stable slot per
continuous unit: building-array order, then catalog role-entry order, then ascending
`slot_index`. The shipped level materializes 21 slots; the control unit, solar
panels, landing platform, robots warehouse and humans residence contribute none
because their entries are zero or `on_demand`. Zero-quantity and `on_demand` entries
never create an automatic slot; `on_demand` is reserved for a future explicit
request system.

Each `Staffing_Slot` stores `{building_index, role_id, slot_index}` plus two
independent claims, `occupant` and `reserved`. A claim caches the owning subject's
array index and stable `Subject_ID`; the index is only trusted while the ID matches,
so a reused array slot can never alias another person. `building_index`, `role_id`
and `slot_index` are stable for the whole session and are rebuilt identically by
every reset from the same level template and catalog.

`logic.derive_staffing(&game,&fleet)` rebuilds the derived claims and per-building
coverage once per fixed tick after movement and after any reset or command. It is
deterministic, allocation-free and bounded by the slot table and the subject array.
A claim survives only when it names a materialized continuous slot, the building is
enabled, the subject is a live, healthy, non-medical, non-evacuating colony resident
supporting the role, and (for an occupant) the subject has physically arrived and is
in `Working`/`Extra_Working`. Invalid claims are released, never silently dropped:
a released worker starts required rest where it stands with `work_hours` and
`rest_hours` at zero, and a released rest-complete reserved subject returns to
`Idle`. Occupancy and reservation are independent, so a scheduled replacement may
reserve the slot an incumbent still covers; two subjects can never both cover one
slot or both reserve it. Conflicts are resolved in favour of the lower stable
`Subject_ID`, independent of array order.

`on_demand` entries are ignored: an assignment with no materialized slot is
released on the next derivation. `staffed` is `covered == required` per building,
so a building with no continuous slots is vacuously staffed; the flag is independent
of the player-requested `active` state and never changes it. `Building_Snapshot`
carries the derived `staffed` value, and `Staffing_Coverage` reports
required/covered/reserved counts per role entry.

Level initial assignments start on shift: the subject is placed at the assigned
building with `phase = Working`, `work_hours = 0` and the first free `slot_index` of
that building role in level-subject order. Startup validation rejects more initial
assignments than continuous slots and rejects a level whose total continuous slots
exceed `STAFFING_SLOT_LIMIT` (1024), so materialization never truncates.

Capacity and overflow behavior are explicit: the slot table is a fixed limit checked
at startup; the scheduler's subject/slot limits are specified by roadmap task 6.
Reset clears every derived claim before the subjects are rebuilt, and a successful
development reload builds a fresh session, so no stale occupant or reservation can
survive either path; a failed reload keeps the previous session untouched.

## Building operation under staffing loss

`Building_Snapshot` keeps player intent (`active`), derived coverage (`staffed`) and
resulting output separate. `logic.building_output_gated` is true for an enabled
building whose continuous slots are not fully covered; `snapshot` then reports
`power_output_kw = 0`, and `balance` omits its output. Consumption is never gated:
an unstaffed building keeps its full `power_need_kw`, stays enabled, never enters
cooldown and keeps warming up, so `available_kw` can become negative. The same tick's
`step_load_shedding` resolves the deficit by force-stopping the greatest active
consumer, so the negative balance does not persist while an eligible load exists.
Coverage returning resumes output immediately at the
current startup level because `active`/`level` were never changed.

Staffing is derived before power each fixed tick, so a building that loses coverage
cannot produce during that tick, and `toggle` evaluates the resulting network with
uncovered buildings at zero output. Real activation, health gates, cooldown and the
producer/Control Unit locks are unchanged.

`derive_staffing` also publishes the edge-triggered `Staffing_Lost` and
`Staffing_Restored` events into the session's bounded `Event_Queue`, in building
order, at most once per transition. Tracking is baselined by the first derivation
after a reset (a new session publishes nothing for buildings that start unstaffed),
only buildings enabled on both derivations publish, and a restoration is published
only after a loss that has not yet been recovered. Disabling or enabling a building
is a player command, not a staffing incident. The event queue's capacity and
overflow behavior are unchanged. The application drains the queue once per fixed
tick through `publish_event_notices`, converts each transition to one localized
notice in sequence order, and clears the queue so it cannot fill and drop newer
transitions. Hourly resource production and consumption read the same derived
coverage, so an enabled but unstaffed building neither consumes nor produces while it
keeps its full demand.

## Hourly production, consumption and load shedding (`src/logic/production.odin`)

`logic.step_production(&game,tick)` runs once per fixed tick and evaluates every
building only when the passed logical tick is a whole simulated hour
(`tick % TICKS_PER_HOUR == 0`), so the result is independent of the clock speed and
the frame pacing. For one building at that boundary:

- **Gating:** `operational = active && level >= 1 && building_staffed`. An inactive,
  warming/cooling or unstaffed building neither consumes nor produces; it keeps its
  activity and never enters cooldown because of production.
- **Recipe:** every product yields `units_per_hour`; every need consumes
  `amount_per_hour`, or `amount_per_unit * reference.units_per_hour`, where the
  reference is the first `produces` entry. Startup validation rejects an
  `amount_per_unit` need whose first product has no positive `units_per_hour`; the
  obsolete building `amount_per_resident` rate no longer exists.
- **All-or-nothing:** the whole hour runs only when every input is available
  (`stock >= consumed`) and every output fits after the inputs are applied
  (`stock - consumed + produced <= capacity`). Otherwise the entire hour is skipped
  with no partial consumption or production. Amounts are fractional and accumulate.
- **Events:** `Production_Blocked` is published once when an operational building
  starts skipping hours for a missing input; `Production_Resumed` once when a
  previously blocked building runs again. A full output store publishes nothing; it is
  visible only in the inspector. Leaving operation resets the blocked sequence.

The borrowed recipe metadata (`logic.Recipe`: the catalog `needs`/`produces` slices)
is materialized once per session and never allocates per tick. `production_status` and
`production_rates` are read-only evaluations for the inspector.

`logic.step_load_shedding(&game)` resolves a negative instantaneous balance without
scaling production: while `available_kw < 0` the active consumer with the greatest
configured `power_need_kw` (lowest level index on a tie) is force-stopped
(`active = false`, `level = 0`) and one `Power_Shed` event is queued. Generators, the
Control Unit and `always_on` types are never candidates; a shed building does not
enter cooldown and stays off until the player re-enables it. If no candidate remains
the signed balance is displayed unchanged. Power attributes are mutually exclusive at
startup (`power_need_kw == 0` or `power_output_kw == 0`) and `always_on` requires zero
demand, so the shedding rule and the pre-existing shutdown locks can never conflict.

## Individual need fulfillment (`src/logic/fulfillment.odin`)

`logic.step_need_fulfillment(&game,&fleet,tick)` runs once per fixed tick and, like
production, evaluates only at a whole simulated hour
(`tick % TICKS_PER_HOUR == 0`). It is placed immediately after `step_production` and
before `step_subject_health`, so a subject draws from the stock its building produced
this hour and the same tick's health step consumes the resulting fraction.

For every live subject physically `Inside` a building (`activity == .Inside` and
`destination` naming a level building instance) and for each configured need of its
type:

- `required` is the need's `amount_per_hour`; `available` is the containing building's
  runtime stock for that resource.
- `fulfillment = clamp(available / required, 0, 1)`.
- The supplied amount (`required * fulfillment`, i.e. `min(required, available)`) is
  removed from the building stock. Amounts stay fractional `f64` and are never
  rounded.
- The unmet fraction is *not* handled here: `step_subject_health` keeps advancing the
  existing shortage clock and applying the unchanged quadratic shortage maths. No
  health, shortage or severity formula changed in phase 3.

A subject in transit (`.Station`, `.Onboard`, `.Waiting`, `.Moving` and station-side
`.Reserved`) draws nothing and keeps its previous `fulfillment`; the health step
keeps applying the last known fraction while it travels.

A building that resolves no stock entry for a needed resource leaves `fulfillment` at
`1`, so a level without a stocked supply keeps working instead of silently starving
its subjects. `config.load` reports that gap once at startup as an actionable
configuration diagnostic for resident buildings (`report_unstocked_resident_needs`);
it is developer console text, never a UI string, and does not reject the level.

The step allocates nothing, retains no catalog storage past the call and never
changes building activity or level. The obsolete building-level
`amount_per_resident` rate was removed from `Need` and `Product`, from decoding and
validation (including the `one_of` groups and the residents requirement), from the
manage schema and editor, and from the documentation; per-capita consumption is
modelled only by subject needs.

## Shift scheduler and reservations

`logic.schedule_staffing(&game,&fleet)` (in `src/logic/scheduling.odin`) runs once
per fixed tick after `derive_staffing` and reserves unassigned individuals for
materialized continuous slots. It never moves anyone and never changes a phase
except through `reserve_staffing_slot` (a rest-complete idle subject becomes
`Reserved`); task 7 owns movement, handoff and the work/rest/overtime timers.

- Candidate ordering: role/health eligibility filters, then forecast arrival
  ascending (remaining required rest plus straight-line travel at the individual's
  speed), then the type's nominal `work_time` descending, then distance ascending,
  then stable `Subject_ID` ascending.
- Station stock, onboard people and station-side boarding are never candidates; the
  check is `staffing_subject_in_colony` plus the reservation mutator's own filters.
- An uncovered slot is filled immediately. A slot whose incumbent still works uses a
  just-in-time rule: the replacement is reserved when its forecast arrival is within
  `SCHEDULER_ARRIVAL_WINDOW` (one fixed tick) of the incumbent's remaining
  `work_time`, which places the request in the final part of the candidate's rest.
  Once the incumbent is `Extra_Working`, the earliest-arriving eligible candidate is
  requested regardless of lateness. A subject with a claim is never a candidate for
  another slot.
- `Scheduler { cursor, subject_cursor, deferred }` lives in `logic.State`, is
  cleared by reset and reload, and uses no random source. Each pass examines at most
  `SCHEDULER_SLOT_BUDGET` slots and `SCHEDULER_EVALUATION_LIMIT` subject evaluations;
  a cut-short pass leaves unexamined slots untouched and retries them next pass with
  rotating cursors, and `deferred` counts the deferred slot examinations. Deferral
  never drops a subject and never changes a reservation.
- Stale claims are cancelled by the same-tick `derive_staffing` call before the
  scheduler runs, so invalidation (health, medical, disablement, slot removal, role,
  reset/reload) is replaced immediately in that tick.

## Shift lifecycle and physical handoff

`logic.step_shifts(&game,&fleet)` (in `src/logic/shift.odin`) advances the
rest/work/overtime timers by one fixed tick and performs the non-movement phase
transitions:

- `Resting` accrues rest up to `rest_time`. On completion it starts the work trip when
a reservation exists, otherwise it enters `Idle` where inactivity starts immediately.
- `Reserved` (rest already complete) starts the work trip immediately.
- `Idle` accrues `idle_hours`; the health step turns that into the quadratic
inactivity loss.
- `Working` accrues `work_hours`; at `work_time` it enters `Extra_Working` and the
health step applies the overtime loss.
- `Extra_Working` accrues overtime until `work_time + extra_work_time`, then the
subject leaves the slot even without a replacement and rests where it is.

The work trip re-targets the individual to the reserved building and is moved by the
normal `step_subjects` walk. Reservation waiting after rest and travel to work remain
health-neutral. Health/medical/evacuation ineligibility is released by the same
tick's `derive_staffing` (below `min_work_health` or any non-`None` medical state),
which starts required rest wherever the subject stands.

`logic.commit_shift_handoffs(&game,&fleet)` runs after movement and before
`derive_staffing`. For every reserved, arrived, still-eligible subject it releases the
incumbent (who starts rest at the workplace) and records the replacement in the same
step, so coverage never observes an uncovered tick between consecutive shifts. An
absent replacement simply leaves the slot open for the scheduler, and a replacement
already travelling keeps its reservation when the incumbent leaves at extra-work
expiry. Because this step runs after movement, an arrival committed this tick is
covered by the same tick's derivation.

Fixed-tick order in the application is authoritative and is exactly:

```text
step (warmup/cooldown ramps)
  -> derive_staffing (coverage committed at the end of the previous tick)
  -> step_production (hourly: logical tick % TICKS_PER_HOUR == 0)
  -> step_need_fulfillment (hourly: same boundary, draws from building stock)
  -> step_subject_health
  -> step_medical
  -> step_shifts
  -> step_transports (movement)
  -> commit_shift_handoffs
  -> derive_staffing (settles movement and arrivals for this tick)
  -> step_load_shedding (resolves a negative balance in the same tick)
  -> schedule_staffing
  -> publish_event_notices
```

Timers and phase transitions run before movement, and handoff/coverage before
scheduling, so invalidation, replacement and power evaluation all observe a
consistent lifecycle. Production runs on the coverage committed by the previous
tick's final derivation, individual need fulfillment shares the production hour
boundary (after production, so a building's fresh output is available), and load
shedding runs after this tick's derivation, so a
coverage loss is paid for in the tick it happens. The whole lifecycle is tick-driven:
pausing stops it, speed levels only change how often ticks run, and identical tick
counts produce identical state. The application reconstructs the logical tick index
inside the frame loop because `advance_clock` advances whole frame batches; the
hourly production and fulfillment steps use that index, never the post-frame
`clock.ticks` value.

## Medical evacuation and death (`src/logic/medical.odin`)

`logic.step_medical(&game,&fleet)` runs once per fixed tick immediately after
`step_subject_health` and before the shift/movement steps, so death removal (step 4 of
the fixed-tick order) is delivered before medical requests (step 5) of the same tick
and both follow ascending runtime subject order. It is headless, and the steady state
allocates nothing.

- **Requests are per-subject state.** `Runtime_Subject.medical` is the only medical
request record: at most one per live subject, bounded by `SUBJECT_LIMIT`. There is no
request table, so no request can overflow and nobody is silently dropped.
- **Threshold crossing.** A live, colony-side subject (`Inside`/`Moving`/`Waiting`)
with `health <= subject type.min_colony_health` transitions from `None` to
`Pending_Evacuation` exactly once and emits one `Medical_Evacuation` event. Threshold
equality triggers; a higher value does not. Health keeps evolving while the request is
pending and needs are not paused.
- **Work release.** The request immediately clears `assignment` and `reservation`
through `release_subject_assignment`/`release_subject_reservation`.
`staffing_subject_eligible` rejects every non-`.None` medical state, so the scheduler
never reserves a patient; the freed slot is refilled by the same tick's
`derive_staffing`/`schedule_staffing` (replacement search).
- **Platform walk.** The patient is ordered to the first active `landing_platform` in
building order using `evacuation_platform`, `destination`, `target` and the existing
`.Waiting`/`.Moving` walk with single-file spacing. With no active platform the
patient stays safely in place and retries each tick; a disabled platform anchor is
reassigned. `move_subject` rejects any medical subject.
- **Death is permanent.** At `health <= 0`, anywhere in the lifecycle, the subject is
marked `Removed` and emits exactly one `Subject_Died` event. `reconcile_death`
releases staffing claims and then reconciles exactly one owner: a transport manifest
(`.Reserved`/`.Onboard`, detaching the individual and correcting `units`/`loaded`/
`requested` plus the destination reservation of an undelivered ordinary passenger),
residence occupancy (`Inside`/`Moving`/`Waiting`), or station stock (`.Station`).
`residents_amount` mirrors the occupant count and every mission manifest stays
compact, so population is reduced by exactly one with no duplication.
- **Residence-evacuation interaction.** `reconcile_evacuations` and
`dispatch_evacuations` skip medical subjects, and a subject that becomes medical while
holding a planned residence-evacuation seat is detached from that manifest before the
medical order, so only the medical path owns it.

Removing a passenger rebuilds that one mission's manifest and frees the replaced
allocation immediately; death is a rare event, not a per-tick path. Logic emits
stable-ID events only; the application turns them into localized notices (below).

## Emergency medical transport (`src/logic/medical_transport.odin`)

Medical dispatch runs inside `logic.dispatch_transports`, every tick, after the
ordinary residence-evacuation and immigration dispatch. Only `emergency` ships carry
patients; ordinary transports never do.

- **Selection.** For a ready patient type the mission uses the first available
  emergency ship in stable catalog order whose `subjects` capacity includes that
  type. Non-emergency ships and ships with no capacity for the type are skipped. A
  catalog with separate human/robot ships or one ship compatible with both behaves
  the same way: the first compatible available unit wins.
- **Batching.** Ready compatible patients of one subject type are batched on one
  mission/leg up to whole shipped capacity. A leg launches as soon as one patient is
  ready, so an executable mission is never delayed to fill the ship; the remainder is
  picked up by further legs or later cycles. One mission carries one subject type
  because per-type capacity, handling and the manifest are per-type.
- **Manifest ownership.** `Runtime_Subject.medical_reserved` marks a patient holding
  a seat; `medical` becomes `.Evacuating` at boarding and `.Hospitalized` at station
  discharge. `Transport.medical` distinguishes the mission from ordinary cargo and
  from residence evacuation. Station discharge never increments `stock.units` and
  `station_reserved_subjects` ignores medical missions, so patients do not consume
  anonymous stock capacity.
- **Landing priority.** `transport_lands_ahead` defines two non-preemptive classes:
  a medical mission outranks every ordinary mission, and within one class the lower
  arrival ticket lands first. A ship already descending, unloading or taking off
  keeps the platform (`reserve_platform`), and a held mission whose required pad is
  disabled never blocks another, preserving the existing inactive-pad rule. Ordinary
  and residence-evacuation missions remain one shared FIFO class.
- **Re-targeting and cancellation.** When a held (`Outbound`/`Waiting_Landing`,
  nothing boarded) medical mission's pickup platform disappears, it and its patients
  are re-targeted to another active platform. With no active platform anywhere, the
  stationary held mission is cancelled through the ordinary withdraw path, its seats
  are released back to `.Pending_Evacuation` and the ship returns to the station. A
  boarded mission is never cancelled: it already owns the individuals and completes
  its return.

Each dispatch allocates one manifest per leg, freed with the mission on completion,
reset or shutdown. The medical dispatch is headless and uses the existing `Ship`,
`Station_Ship` and `Transport` value contracts only. Emergency ship selection
(`first_available_emergency`) is direction-agnostic so the return leg reuses it.

## Station hospitalization and return (`src/logic/medical.odin`, `medical_transport.odin`)

A medically evacuated individual does not merge into anonymous station stock. The
patient keeps their stable `Subject_ID`, stays outside `stock.units`, and is excluded
from ordinary station stock selection and replenishment.

- **Recovery.** `subject_health.odin` adds `station_recovery_per_hour` to a
  `.Hospitalized` patient every fixed tick, at the same fixed-tick point as the other
  health effects. It consumes no colony or station resource; needs still apply on
  top, so a shortage can slow or cancel recovery.
- **Return request.** Once health reaches `min_work_health` (equality included),
  `request_medical_returns` moves the patient to `.Returning`. This is idempotent:
  the patient leaves `.Hospitalized`, and `.Returning` patients are never requested
  again.
- **Return dispatch.** `dispatch_medical_returns` batches `.Returning` patients of
  one subject type onto the first compatible available `emergency` ship in stable
  catalog order, up to whole shipped capacity, launching as soon as one patient is
  ready. With no compatible ship the patients stay `.Returning` and retry; ordinary
  transports are never used. The leg loads at the station (`Loading`), flies to the
  colony and shares the two-class priority landing queue.
- **Colony discharge.** `deliver_medical_patients` unloads each patient at the
  landing platform and walks them to `medical_home`, their original residence, using
  the normal single-file spacing. Occupancy is incremented directly and never touches
  ordinary cargo reservations or station stock; each discharge emits one
  `Medical_Return` event and clears `medical`, `medical_reserved` and `medical_home`.
  Returned individuals are unassigned, fully rested (`rest_hours == rest_time`,
  `phase == .Idle`), keep their roles and are immediately eligible for any supported
  role. If no residence can be resolved for a patient, the rest stay aboard and are
  returned to the station as hospitalized patients rather than being dropped.
- **Death.** A patient at zero health is removed permanently anywhere in the return
  lifecycle (waiting, loading or aboard); removal detaches the individual from any
  return manifest and never decrements station stock. A dead patient is never
  returned.

`Runtime_Subject.medical_home` stores the borrowed original-residence ID recorded when
the patient boards the outbound leg (falling back to `residence` at boarding). Each
return leg allocates one manifest, freed with the mission. No station patient capacity
is defined by the specification, so patients do not consume `stock` capacity.

## UI, localization and presentation

The application is the only adapter from logic to presentation. It builds inspector
text from read-only `Building_Snapshot`/`Subject_Snapshot` values and catalog data,
and it drains the event queue; UI and render never mutate authoritative state.

- **Building staffing.** The inspector shows continuous coverage as
  `{covered}/{required} covered` per role, a `{role}: {reserved} arriving` line when
  replacements are scheduled, `Uncovered continuous slots: {count}` while any
  continuous slot lacks a physical occupant, and `{role}: {quantity} on demand` for
  configured `on_demand` entries. A building with no continuous slots shows the
  localized "No continuous slots" state. Coverage comes from
  `logic.staffing_coverage`, so it reports physical occupants rather than assumed
  assignments.
- **Individuals.** Every resident, physically assigned or reserved individual
  associated with the inspected building is listed as a fixed-size block: name and
  stable ID, health, work/medical phase, role, assignment slot, work/rest/idle
  timers, medical status and one line per need (fulfillment percentage plus shortage
  hours). Removed and unrelated individuals are never listed; an empty association
  shows the localized "No individuals" state.
- **Notices.** `publish_event_notices` consumes the pending events once per fixed
  tick, in ascending `sequence` order, and appends one localized notice per
  `Staffing_Lost`, `Staffing_Restored`, `Medical_Evacuation`, `Medical_Return` and
  `Subject_Died`. It then clears the queue. Notice text borrows persistent
  localization storage, so it survives the frame.
- **Localization.** Every label, phase/medical name, format and notice lives in
  `assets/config/default/localization/en.json`; startup validation rejects missing or empty required
  keys and required placeholder tokens. No Odin UI string or fallback is used.
- **Memory and assets.** All inspector/notice text is frame-temporary or borrowed
  persistent localization storage; the paths allocate nothing from the session/heap
  allocator and load no assets per frame. Long localized text wraps through the shared
  measurement contract and scrolls in the existing fixed-size panel, preserving
  focus, scrolling, input consumption, resize and sprite fallback behavior.

## Lifetime, limits, reload and pause

All authoritative state belongs to the session: `logic.State` owns buildings, power,
staffing slots and the event log; `logic.Transport_State` owns individuals, role
projections, station stock and mission manifests. Strings borrow validated
level/catalog storage in the application arena, which lives for the whole session.

Capacities and overflow are explicit and never silently drop a subject:

| Table | Capacity | Overflow behavior |
| --- | --- | --- |
| Continuous staffing slots | `STAFFING_SLOT_LIMIT` (1024) | Startup validation rejects a larger level with an actionable message; the session asserts the bound. |
| Runtime stock entries | `STOCK_ENTRY_LIMIT` (1024) | Startup validation rejects a level whose resolved building resources exceed the limit with an actionable message; the session asserts the same bound. The table is allocated once and never grows. |
| Individuals | `SUBJECT_LIMIT` (16384) | Startup validation rejects a larger initial population; `add_runtime_subject` returns `-1` without growing the array, and a removed slot is reused by full overwrite. |
| Medical requests | `MEDICAL_REQUEST_LIMIT` = `SUBJECT_LIMIT` | Per-subject state, at most one per live individual; there is no separate request table. |
| Patients | `PATIENT_LIMIT` = `SUBJECT_LIMIT` | Identified individuals, not station stock, so the individual array is the only bound. |
| Mission log | `TRANSPORT_LIMIT` (128) | Dispatch stays pending without consuming stock or dropping anyone. |
| Event log | `EVENT_LIMIT` (128) | The newest event is rejected and `overflowed` increments; queued transitions are preserved and the drop stays observable. `Power_Shed` emits one event per shed building, so a tick with more sheds than the remaining capacity drops the newest shed notices while the authoritative shutdowns still happen. |
| Recipes per building | Borrowed catalog slices | Materialized once per session; no fixed table and no per-tick allocation. `production_blocked` is one owned boolean per building. |
| Needs per subject type | `NEED_SLOT_LIMIT` (8) | Startup validation rejects a larger need list instead of truncating it. |

Free paths: `reset` restores initial runtime stock, clears derived staffing claims and
the event log and rebuilds the subjects; `reset_transports` deletes every mission
manifest before clearing the log; `destroy`, `destroy_staffing`, `destroy_stock`,
`destroy_transports` release every owned array and
manifest; a successful development reload constructs a fresh session and the old
arena/manifests are released as the old loop exits; a failed reload frees only the
candidate arena and preserves the running session. Tracking-allocator tests in
`src/logic` and `src/app` assert that no owned block survives reset, destruction or
either reload outcome.

Pause and catch-up: the simulation advances only while a session runs. Zero,
negative and NaN frame intervals advance nothing, so pausing (menu, staging frame)
freezes health, shifts, staffing, power and transport exactly where they were. One
frame is bounded to `MAX_FRAME_SECONDS` of real time, so a stall is dropped rather
than caught up unboundedly (at 32x the cap is 480 fixed one-minute ticks). Speed
levels change only how many ticks a frame runs, never the tick size.

## Verification

`odin test src/contracts`, `odin test src/logic`, `odin test src/config` and
`odin test src/app` cover the value-snapshot and event contracts, tick boundaries,
partial and additive need effects, `shortage_alert_time == shortage_max_time`, very
large and invalid elapsed values, saturation at 0 and 1, the configured human/robot
rates, the materialized slot order, initial assignments, duplicate coverage and
reservations, physical-arrival and eligibility gating, disablement release, reset
safety, the startup capacity limits, the staffing-gated power network (producers,
generators, consumers, combined buildings, cascades, same-tick handoff), the
edge-triggered coverage events, deterministic scheduler ordering across competing
buildings and multiple roles, rest/travel forecasts, just-in-time and overtime
requests, reservation invalidation and same-tick rescheduling, station/inbound
exclusion, work-bound rotation, deterministic replay, the full shift lifecycle (rest
completion, work trip, atomic on-time handoff without an uncovered tick, late/no
replacement, overtime expiry, incapacity during overtime, replacement in transit,
role changes between shifts, inactivity and pause/time scaling), the shipped-level
integration, and the medical slice (threshold equality/crossing, one-time requests
over repeated ticks, work release and same-tick replacement, platform walk and
queuing, unavailable platform retry, permanent removal before pickup and while
reserved/moving/onboard/at the station, manifest correction, residence-evacuation
takeover, event order and population conservation), and the emergency transport
slice (partial/full batches, split remainders, first compatible ship, dual-type
ships, incompatible and unavailable ships, mission limit, two-class non-preemptive
priority, FIFO within a class, ordinary waiter ordering, retarget and clean
cancellation, station discharge as identified patients, and exact manifest
accounting across boarding and in-flight death), and the station return slice
(recovery boundary, automatic recovery without stock consumption, return batching
with capacity split, no compatible ship, occupied-platform landing wait, death
exclusion before and aboard a return leg, multiple patients, and identity/residence
preservation across the full colony-station-colony round trip). Task-12 hardening
adds the explicit capacity and overflow checks (`STAFFING_SLOT_LIMIT`,
`SUBJECT_LIMIT`, `MEDICAL_REQUEST_LIMIT`/`PATIENT_LIMIT`, `TRANSPORT_LIMIT`,
`EVENT_LIMIT`), tracking-allocator regressions proving every owned array and mission
manifest is released by reset and destruction, and app-level reload regressions
proving a failed reload preserves active shifts, health, patients and queues while a
successful reload rebuilds health/need rates, slots, reservations, patients and
emergency queues from the level and releases the candidate arena.
`odin run tools/gameplay_smoke` (also enforced by `odin test src/app`) runs the
multi-day integration scenario documented in [Gameplay smoke](gameplay-smoke.md):
shift rotation, late replacement with overtime, staffing-gated power, simultaneous
shortages, medical evacuation, station recovery, emergency-priority landing, return
and a death while waiting, with population conservation asserted.
`odin check src/app` and `python tools/build.py` validate the composed application
and assets. `odin test src/localization` verifies that every required key and
placeholder is present and non-empty, and `odin test src/app` covers the task-11
presentation: coverage and individual formatting, decimals only when useful, empty
states, long localized text wrapping, event ordering, and that the inspector/notice
paths allocate only from the frame allocator. Phase 1 of the
[building production plan](building-production.md) adds the runtime stock
regressions: `odin test src/logic` covers capacity resolution, seed order, reset
restore, the borrowed snapshot and the tracking-allocator free paths;
`odin test src/config` covers the shared capacity resolver and the `STOCK_ENTRY_LIMIT`
startup rejection; `odin test src/app` covers the localized stock list and that a
failed reload preserves stock while a successful one rebuilds it from the new level.
Phase 2 of the same plan adds the production and load-shedding regressions:
`odin test src/logic` covers recipe math with the first product as the reference,
`amount_per_hour` and fractional accumulation, all-or-nothing skips with one
`Production_Blocked`/`Production_Resumed` per transition, full-output skips that
publish nothing, hourly scheduling compared across clock speeds and frame batching,
activity/warmup/staffing gating, the load-shedding cascade with lowest-index
tie-break and generator/lock protection, reset restore, and the chained
water-collector/greenhouse/meals-factory scenario with explicit initial stock;
`odin test src/config` covers the mutual-exclusion, `always_on` demand and reference
product startup validation; `odin test src/app` covers the grouped power-shed notice
(shed order, composed identities, one notice per tick, buffer reuse after the bounded
log capacity) and that the notice path allocates only from the frame allocator.
Phase 3 completes the plan: `odin test src/logic` covers individual `fulfillment`
drawn from the `Inside` building's stock (full, partial and zero), the unstocked-entry
fallback, transit exclusion for every non-`Inside` activity, the hourly boundary and
that the step allocates nothing; `odin test src/config` covers rejection of the
removed `amount_per_resident` field on needs and products plus the
unstocked-resident-need startup diagnostic; and the gameplay smoke now
drives its shortage episode from real shelter stock instead of the retired manual
fulfillment placeholder.
The developer-only
`tools/info_smoke` capture renders the staffing coverage and individual blocks with
the real font and catalog:

```sh
python tools/build.py
odin build tools/info_smoke -out:build/info-smoke.exe -define:INFO_BOX_SMOKE=true
./build/info-smoke.exe
```
