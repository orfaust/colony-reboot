# Subject Health and Staffing Implementation Plan

This checklist implements [Subject Health, Shifts, Staffing, and Medical
Evacuation](subject-health-and-staffing.md). Tasks are ordered to keep contracts
explicit, dependencies acyclic, and intermediate states testable. Do not implement
`on_demand` request generation as part of this plan.

Each task must preserve unrelated working-tree changes, update English documentation
and localization where affected, and run its listed checks plus existing regressions.

## 1. Configuration contracts and migration

**Depends on:** none.

- Add subject health thresholds, `extra_work_time`, health rates, and per-need health
  rates to Odin and manage schemas.
- Change building staffing quantity from finite f32 to nonnegative integer.
- Replace `required` with `staffing_mode: continuous | on_demand`.
- Replace level `occupation` with nullable `initial_assignment {building_id, role_id}`
  and add individual `health`.
- Add `emergency` to validated ship types.
- Migrate shipped JSON using the agreed human/robot defaults without silently
  normalizing malformed external data.
- Extend the existing master-detail manage editors and preserve unknown fields,
  selection, history keys, and malformed-data repair paths.

**Acceptance:** shipped data validates; legacy fields fail with actionable paths;
integer quantities reject fractions; threshold/rate NaN, infinity, range, duplicate,
and reference failures are tested in Odin and manage.

## 2. Shared views, commands, and events

**Depends on:** task 1.

- Define the minimum dependency-free IDs/value contracts for health, work phase,
  assignment, staffing coverage, and medical status.
- Add read-only subject/building snapshots and events needed by application/UI.
- Specify ownership and delivery order; do not expose config slices or mutable logic
  pointers.
- Define edge-triggered events for understaffing, restored staffing, medical
  evacuation, return, and death.

**Acceptance:** contract tests prove snapshots cannot mutate authoritative state and
all event payloads use stable IDs.

## 3. Runtime subject health and need state

**Depends on:** tasks 1–2.

- Add health, phase timers, idle time, and one need-state record per individual.
- Initialize explicit subjects from level health and generated residents at health
  one; preserve identity through current transport flows.
- Implement full/partial need fulfillment accounting and independent shortage
  clocks without per-tick allocation.
- Implement additive fixed-tick health calculation, clamping, quadratic shortage,
  quadratic inactivity, and the configured positive/negative rates.
- Keep reservation/travel/transport activity neutral while need effects remain
  active.

**Acceptance:** headless tests cover tick-size boundaries, partial fulfillment,
multiple simultaneous needs, alert=max, very large elapsed values, saturation at
zero/one, and human/robot defaults.

## 4. Staffing-slot model and coverage

**Depends on:** tasks 1–3.

- Materialize stable continuous staffing slots from integer building role entries.
- Track reservation and physical occupant independently by building/role/slot.
- Derive `staffed` without changing player-requested `enabled`.
- Ignore `on_demand` entries until a future explicit request system exists.
- Release slots safely on disablement, subject invalidation, reset, and reload.

**Acceptance:** duplicate coverage is impossible; only physically arrived eligible
subjects cover slots; required coverage is deterministic and reset-safe.

## 5. Building operation under staffing loss

**Depends on:** task 4.

- Integrate staffing before power and production evaluation.
- Keep normal power consumption while understaffed.
- Set power output to zero, consume no production inputs, and create no products.
- Resume immediately without warmup when staffing returns to an enabled building.
- Preserve real activation, cooldown, health locks, and player commands.
- Publish transition events once, not every tick.

**Acceptance:** tests cover producers, generators, consumers, combined buildings,
power cascades, staffing loss/restoration in the same tick, and unchanged enabled
state.

## 6. Shift scheduler and reservations

**Depends on:** tasks 3–5.

- Implement deterministic candidate ordering and exclusive reservations.
- Permit reservation during final rest, forecasting remaining rest plus travel.
- Request replacements early enough to reach the building by shift end.
- Invalidate stale reservations and immediately reschedule.
- Ensure station/inbound subjects are never candidates before landing discharge.
- Bound scheduler work and document behavior when subject/slot limits are reached.

**Acceptance:** tests cover competing buildings, multiple eligible roles, fairness,
distance/ID tie-breaks, rest forecasts, invalidation, no candidate, and deterministic
replay with explicit seeds where randomness is absent/introduced.

## 7. Physical handoff, normal work, overtime, and rest

**Depends on:** task 6.

- Move reserved subjects to work only after rest completes.
- Commit slot handoff atomically on physical arrival.
- Advance `work_time`, enter `extra_working`, apply overtime loss, and enforce
  `extra_work_time`.
- Release immediately below `min_work_health` or on medical/death transitions.
- Start rest at the subject's current location and clear the temporary assignment.
- Begin quadratic inactivity immediately after completed rest when unassigned.

**Acceptance:** tests cover on-time handoff without an uncovered tick, late/no
replacement, overtime expiry, incapacity during overtime, replacement still in
transit, role changes between shifts, and pause/time scaling.

## 8. Medical state and death

**Depends on:** tasks 3 and 7.

- Detect the downward crossing of `min_colony_health` once.
- Release work/reservations and create one bounded medical request.
- Move/wait at a valid landing platform using existing individual movement rules.
- Remove subjects permanently at health zero from every relevant state.
- Reconcile residence counts, slots, requests, and manifests without loss or
  duplication; emit one event.

**Acceptance:** tests cover threshold equality/crossing, repeated ticks, zero before
pickup, zero while reserved/moving/onboard, unavailable platform, request limits,
and population conservation.

## 9. Emergency ships, batching, and priority landing

**Depends on:** tasks 1, 6, and 8.

- Select the first available stable-order emergency ship compatible with the subject
  type.
- Batch ready compatible patients up to capacity without delaying dispatch to fill.
- Add non-preemptive two-class landing priority: emergency before ordinary, FIFO
  within each class.
- Preserve ordinary holding behavior and prevent starvation/corruption when missions
  cancel or ships become unavailable.
- Use emergency ships for both outbound medical evacuation and patient return.

**Acceptance:** tests cover human/robot compatibility, mixed catalogs, full/partial
batches, occupied platforms, multiple emergencies, ordinary waiter ordering,
cancellation, and exact manifest accounting.

## 10. Station hospitalization and return

**Depends on:** tasks 3 and 9.

- Keep patients as identified individuals rather than station stock units.
- Apply automatic configured station recovery without consuming resources.
- At `min_work_health`, request return on a compatible emergency ship.
- Keep returning subjects unavailable until landing-platform discharge.
- Return them unassigned, rested as explicitly defined by implementation, and
  eligible for any supported role.

**Acceptance:** tests cover recovery boundary, multiple patients, no compatible ship,
station/ship capacity, return batching, landing wait, death exclusion, and identity
preservation across the round trip.

## 11. UI, localization, and presentation

**Depends on:** tasks 2, 5, 7–10.

- Add all player-facing labels/notices to `assets/localization/en.json` with stable
  keys; add no hardcoded Odin UI strings.
- Present subject health, work/medical phase, role, assignment, timers, and need
  shortages in readable fixed-size info boxes.
- Present building staffing coverage and uncovered continuous slots.
- Add localized edge-triggered notices for staffing loss/restoration, medical
  dispatch/return, and death.
- Preserve focus, scrolling, input consumption, resize, and existing sprite fallback.

**Acceptance:** headless UI/render tests cover formatting, decimals only when useful,
long localized text, empty states, event ordering, and no per-frame allocation or
asset loads; perform a documented visual smoke test.

## 12. Reload, reset, limits, and failure safety

**Depends on:** tasks 1–11.

- Extend successful development reload to rebuild health/need rates, slots,
  reservations, patients, and emergency queues from the current level.
- Preserve the entire old playable session on invalid JSON/reference/sprite staging.
- Free all owned arrays/manifests on success, reset, failure, and shutdown.
- Define capacities and explicit overflow behavior for slots, medical requests,
  patients, and events; never silently remove a subject.
- Confirm pause behavior and bounded fixed-step catch-up.

**Acceptance:** reload failure preserves active shifts, health, patients, and queues;
success restarts cleanly; allocator/memory tracking and limit tests pass.

## 13. Integration and gameplay smoke

**Depends on:** all previous tasks.

- Run the supported build with sprite/config validation, all Odin suites, manage
  tests/build, and diff checks.
- Exercise a multi-day human/robot scenario with shift rotation, late replacement,
  staffing-based production/power suspension, simultaneous shortages, medical
  evacuation, station recovery, emergency-priority landing, return, and death while
  waiting.
- Record observed balance outcomes without claiming final tuning.
- Update configuration, power, station, manage, and architecture documentation to
  match implemented behavior and verified commands.

**Acceptance:** all automated checks pass, the visual/gameplay smoke is documented,
module boundaries remain acyclic, and any unperformed manual verification is stated.

## Suggested delivery slices

To keep reviews manageable:

1. **Data foundation:** tasks 1–3.
2. **Staffing and shifts:** tasks 4–7.
3. **Medical transport:** tasks 8–10.
4. **Presentation and hardening:** tasks 11–13.

Do not claim a slice complete until its acceptance criteria and affected regression
suites pass. Later slices must preserve the verified behavior of earlier ones.
