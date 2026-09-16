# Subject Health, Shifts, Staffing, and Medical Evacuation

Status: **planned; not implemented**. This document is the agreed behavioral
specification. Existing `occupation`, rest/work metadata, subject needs, building
staffing metadata, and ordinary transports do not yet implement these rules.

## Goals and boundaries

Subjects are individual authoritative simulation entities. They have no permanent
job. A subject is assigned to one building staffing slot for one shift and may take
a different building or role after resting. The logic package owns health, needs,
shift scheduling, staffing coverage, medical evacuation, death, and all outcomes.
UI and rendering consume snapshots and events only.

The first implementation supports continuous staffing. `on_demand` staffing is
part of the data contract but its request-generating systems (for example repairs)
are deliberately deferred.

## Catalog and level contracts

### Subject type

Each subject type retains `work_time`, `rest_time`, roles, and needs and adds:

- `extra_work_time`: maximum hours a subject may keep a slot after `work_time`.
- `min_work_health`: minimum health required to start or continue work. Default
  `0.4`.
- `min_colony_health`: threshold that requests medical evacuation. Default `0.1`.
- `health_rates`: nonnegative hourly gains/losses and the inactivity ramp duration.

Validation requires finite values, nonnegative times and rates, and
`0 <= min_colony_health < min_work_health <= 1`.

Initial tuning values are intentionally data-driven and may be adjusted later:

```json
{
  "id": "human",
  "work_time": 12,
  "extra_work_time": 4,
  "rest_time": 12,
  "min_work_health": 0.4,
  "min_colony_health": 0.1,
  "health_rates": {
    "work_gain_per_hour": 0.002,
    "rest_gain_per_hour": 0.01,
    "extra_work_loss_per_hour": 0.025,
    "max_inactivity_loss_per_hour": 0.012,
    "inactivity_max_time": 72,
    "station_recovery_per_hour": 0.04
  }
}
```

```json
{
  "id": "robot",
  "work_time": 20,
  "extra_work_time": 8,
  "rest_time": 4,
  "min_work_health": 0.4,
  "min_colony_health": 0.1,
  "health_rates": {
    "work_gain_per_hour": 0.0015,
    "rest_gain_per_hour": 0.02,
    "extra_work_loss_per_hour": 0.015,
    "max_inactivity_loss_per_hour": 0.006,
    "inactivity_max_time": 120,
    "station_recovery_per_hour": 0.06
  }
}
```

Rates are stored as positive magnitudes. Logic decides whether each rate is a gain
or loss and clamps health to `[0,1]`.

### Subject needs

Each subject need adds:

- `satisfied_health_gain_per_hour`: health gained at full fulfillment.
- `max_shortage_health_loss_per_hour`: loss at maximum shortage severity.

Initial values:

| Subject | Resource | Satisfied gain/h | Maximum shortage loss/h |
| --- | --- | ---: | ---: |
| human | water | 0.001 | 0.025 |
| human | meals | 0.002 | 0.012 |
| robot | batteries | 0.0015 | 0.020 |

Partial fulfillment scales the positive gain by the fulfilled fraction. Missing
amount advances that need's independent shortage clock. Need effects from different
resources are additive.

### Staffing slots

Building `subject_roles` entries become:

```json
{
  "role_id": "worker",
  "quantity": 2,
  "staffing_mode": "continuous"
}
```

`quantity` is a nonnegative integer because it represents individual slots.
`staffing_mode` is either:

- `continuous`: the scheduler keeps every slot covered while the building is
  enabled.
- `on_demand`: no automatic assignment until a future system raises a request.

This replaces the ambiguous `required` boolean. Migration maps `required: true` to
`continuous` and `required: false` to `on_demand`.

### Initial subjects

Health is individual level/session state. Explicit level subjects specify health in
`[0,1]`. Generated residents default to health `1`. The permanent-looking
`occupation` field is replaced by an optional initial shift assignment containing
both the building instance and role:

```json
"health": 1,
"initial_assignment": {
  "building_id": "GH1",
  "role_id": "worker"
}
```

`initial_assignment: null` starts the subject without a shift. Validation confirms
the subject can perform the role and the referenced continuous slot exists. Runtime
assignments are not pointers into configuration storage.

### Emergency ships

The existing ship `type` gains `emergency`. Medical missions use only available
ships with `type: "emergency"` whose `subjects` capacity includes the requested
subject type. Selection uses the first compatible available ship in stable catalog
order. Catalogs may provide separate human/robot ships or a ship compatible with
both.

## Orthogonal runtime state

Physical presence, work phase, reservation, and medical state are separate. They
must not be collapsed into one enum because, for example, a resting subject may
already be reserved for a future shift.

A runtime subject includes at least:

- health and stable individual ID;
- physical transport/activity state and position;
- work phase and elapsed work/rest/idle hours;
- optional shift reservation/assignment;
- one state record per need, including shortage hours;
- medical state;
- residence and eligible roles.

A shift assignment identifies `{building_id, role_id, slot_index}`. `slot_index`
prevents two subjects from covering or reserving the same staffing slot.

## Availability and station arrivals

A subject is eligible for a new assignment only when it:

- is physically in the colony;
- has completed `rest_time` or is forecast to complete it before the planned shift;
- has no conflicting assignment;
- is not in medical evacuation or hospitalization;
- has health at least `min_work_health`;
- supports the slot's role.

A subject travelling from the station is never available or reservable. It becomes
available only after being discharged onto the landing platform. A returning
patient has no assignment and may take any role it supports.

## Shift lifecycle and scheduling

The effective lifecycle is:

```text
resting -> reserved -> moving_to_work -> working -> extra_working -> resting
```

A reservation may coexist with the final part of `resting`. The scheduler forecasts
`remaining rest + travel time` and requests a replacement early enough to reach the
building before the incumbent's `work_time` expires. A reserved subject continues
normal rest recovery until rest completes, then travels immediately. Reservation
waiting after completed rest and travel to work are health-neutral.

A subject covers a slot only after physically reaching the building. At that instant
the handoff from incumbent to replacement is atomic, so consecutive successful
shifts have no uncovered tick.

If no replacement arrives by `work_time`, the incumbent enters `extra_working` and
loses health. The incumbent leaves immediately when the first of these occurs:

- the replacement arrives;
- `extra_work_time` expires;
- health falls below `min_work_health`;
- medical evacuation is triggered;
- health reaches zero.

At `extra_work_time` expiry the subject leaves even without a replacement and rests
where it is. A replacement already travelling continues unless its reservation is
invalidated. Invalid reservations are cancelled and replaced immediately. Causes
include subject health, medical state, building disablement, slot removal, role
incompatibility, and session reset/reload.

Candidate ordering is deterministic: compatible role, health eligibility, forecast
arrival, longest availability, distance, then stable subject ID. A subject is never
reserved for two slots.

## Building staffing and production

Building state distinguishes player intent, staffing, and operation:

- `enabled`: requested activation state.
- `staffed`: every continuous slot is physically covered.
- `operational`: enabled and able to perform production after staffing, power,
  health, and existing activation rules are applied.

When an enabled building loses continuous staffing:

- it remains enabled and does not enter cooldown;
- normal power consumption continues;
- `power_output_kw` becomes zero;
- production inputs are not consumed;
- products are not generated;
- a localized message-box notification is emitted once on the transition;
- the scheduler continues filling uncovered slots.

When coverage returns, output and production resume without warmup because the
building was not disabled. A recovery notification may be emitted once. Warmup and
cooldown remain tied only to real activation/deactivation.

Staffing is evaluated before power output/allocation and resource production each
fixed tick. Missing personnel therefore cannot produce power during that tick.
Notifications are edge-triggered, never emitted every frame or simulation tick.

## Health calculation

Every fixed tick sums all applicable hourly influences and then clamps health:

```text
health = clamp(health + sum(hourly_effects) * elapsed_hours, 0, 1)
```

Normal work and required rest use their positive rates. `extra_working` uses its
negative rate. Reservation waiting after rest, travel to work, and transport are
neutral with respect to activity, while need effects remain independent unless a
future rule explicitly pauses them.

After required rest, an unassigned subject accumulates `idle_hours`. Inactivity loss
starts immediately and ramps quadratically:

```text
severity = clamp(idle_hours / inactivity_max_time, 0, 1)
loss_per_hour = max_inactivity_loss_per_hour * severity^2
```

Positive activity always contributes even near full health; clamping alone limits
the result.

## Need shortage progression

Before `shortage_alert_time`, shortage has no negative health effect. From the alert
time to `shortage_max_time`, loss ramps quadratically:

```text
severity = clamp(
    (shortage_hours - shortage_alert_time) /
    (shortage_max_time - shortage_alert_time),
    0,
    1,
)
loss_per_hour = max_shortage_health_loss_per_hour * severity^2
```

At and beyond `shortage_max_time`, maximum loss continues until fulfillment. When
alert and maximum times are equal, severity becomes one immediately at that time.
The additive result naturally allows prolonged shortage to cancel or exceed rest
recovery.

## Medical evacuation, recovery, and death

Crossing to `health <= min_colony_health` once requests medical evacuation. The
subject immediately releases any staffing slot/reservation, cannot be scheduled,
and moves to or waits at the landing platform. Requests for compatible subjects may
share one emergency ship up to capacity; dispatch does not delay an executable
mission merely to fill the ship.

Emergency missions have landing priority over ordinary missions. Priority is
non-preemptive: a ship already using the platform finishes, then waiting emergency
ships are admitted before ordinary ships. FIFO is preserved within each priority
class.

At the station the subject remains an individual patient rather than merging into
anonymous station stock. Recovery is automatic and consumes no colony or station
resources. At `health >= min_work_health`, an emergency return is requested. The
subject remains unavailable while travelling and becomes available only after
landing-platform discharge.

Health may continue falling while evacuation is pending. At `health <= 0`, anywhere
in the lifecycle, the subject is permanently removed. Removal releases slots and
reservations, removes or adjusts pending/onboard manifests without duplicating
population, triggers replacement search, and emits one localized death notification.
A dead subject cannot recover at the station.

## Fixed-tick order

The intended authoritative order is:

1. fulfill available needs;
2. advance each need's shortage state;
3. calculate and apply health effects;
4. remove subjects at zero health;
5. request medical evacuations and release their work;
6. invalidate stale reservations;
7. advance rest, work, overtime, movement, and transport state;
8. commit physical shift handoffs;
9. schedule replacements;
10. derive building staffing;
11. derive power output and allocate power;
12. consume production inputs and create outputs;
13. publish snapshots, events, and edge-triggered notices.

Exact procedures may split these operations, but observable delivery order must be
stable and covered by headless tests.

## Lifetime, limits, and reload

All authoritative state belongs to the logic/session owner. Stable IDs, never
pointers into another module's mutable storage, cross boundaries. Need state,
reservations, manifests, and patients must be freed on reset and shutdown.
Successful development reload rebuilds the current level from new configuration;
failed reload preserves the complete previous health/staffing/medical state. Queue
limits and overflow behavior must be explicit before implementation; no subject may
be silently dropped.

## Deferred decisions

- What events create and complete `on_demand` slots, including repair work.
- More sophisticated pathfinding, collision avoidance, or shift optimization.
- Save-file persistence; if added, it requires a versioned format.
- Final balance values after gameplay measurement.
