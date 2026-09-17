# Building Resource Production (draft plan)

Status: **phases 0-3 implemented (notice identity, runtime stock foundation, hourly
production and load shedding, individual need fulfillment); logistics (phase 4) is
deferred**. This is a design and phasing document, not the agreed
specification. The decisions listed under [Open decisions](#open-decisions) are not
yet confirmed.
Each building instance owns a flat, mutable runtime stock table. The hourly
production step consumes and produces from it, all-or-nothing, and a power deficit
force-stops the greatest active consumer. Individual fulfillment is driven at the
same hourly boundary from that same stock, so subject needs now run on real supply.

## Scope

Implement resource production and consumption for building instances from the
already-validated configuration (`Building_Type.needs`, `produces`, `storage`,
instance `stored`), driven by the fixed simulation tick, and gated by requested
activity, warmup level, and derived staffing. The same step wires individual need
fulfillment to real stock, which the subject-health slice left as an explicit
placeholder. A negative power balance must also trigger the agreed automatic load
shedding, so production can never run on a deficit it did not pay for.

Confirmed decisions so far: stock is per building instance (no colony pool); an
individual draws its needs from the building it is physically `Inside`; the obsolete
building-level `amount_per_resident` rate is removed from the schema; the
`capacity: 0` battery configuration was corrected in the catalog; aggregate resident
counts use physical presence in the colony, not `residents_amount`; production and
consumption run in **hourly batches** and are all-or-nothing; a power deficit sheds
the greatest consumer immediately and cascades; notice identity becomes the localized
building name plus the instance ID for every building notice.

Inter-building resource transport is explicitly deferred.

Out of scope, deferred to later work:

- Inter-building logistics and distribution, and any colony-wide resource pool.
- Market/trade, sinks, or resource decay.
- Construction/repair consumption of `materials_amount`.
- Energy accumulation in kWh; power stays an instantaneous kW constraint.
- Save files and versioned persistence of stock.

## Current state

- Configuration validates needs (`amount_per_unit` | `amount_per_hour`, plus
  `capacity`), products (`units_per_hour`, plus `capacity`), `storage`, and per-instance
  `stored`
  amounts bounded by the largest capacity of the matching need/product/storage entry.
  An `amount_per_unit` need now requires the first `produces` entry to have a positive
  `units_per_hour` (the reference product), and power attributes are mutually
  exclusive with `always_on` demand zero (phase-2 startup validation). The obsolete
  building `amount_per_resident` field is rejected as an unknown field (phase 3).
- `Building_Instance.stored` is borrowed immutable level metadata that only seeds and
  resets runtime stock; the simulation mutates only the owned runtime table. The
  inspector and overview read the read-only runtime snapshot, never the template.
- `logic.State` owns the flat runtime stock table (`stock_first`/`stock`) resolved from
  each building's definition. Amounts are seeded from the level and change once per
  whole simulated hour.
- `logic.step_need_fulfillment` drives `Need_State.fulfillment` at each whole
  simulated hour from the stock of the building the subject is physically `Inside`
  (phase 3); `logic.step_subject_health` consumes that fraction with its unchanged
  quadratic shortage math.
- `logic.step` advances the warmup/cooldown `level`; `building_staffed` and
  `building_output_gated` gate electrical output, and `step_production` runs the
  hourly recipe behind the same coverage.
- `logic.step_load_shedding` force-stops the greatest active consumer of a negative
  balance in the same tick, cascading until balanced or no candidate remains.

## Goals

- Produce and consume resources in hourly batches at fixed-tick boundaries,
  deterministically and headlessly.
- Honour recipe ratios, hourly rates, capacities, and warmup level.
- Resolve a negative power balance by shedding load deterministically (see
  [Power deficit and automatic load shedding](#power-deficit-and-automatic-load-shedding)).
- Never allocate per tick, never load assets, and never let UI/render decide outcomes.
- Keep the level template pristine so reset and reload restore initial stock.
- Expose read-only stock views and edge-triggered notices through the existing
  contracts and event queue.

## Data model

Replace per-instance borrowed stock with owned, mutable runtime stock, laid out flat
like the staffing slot table for determinism and cache locality:

```text
Stock_Entry {
    resource_id: string, // Borrowed validated catalog/level storage.
    amount: f64,         // Current units, clamped to [0, capacity].
    capacity: f64,       // Resolved max capacity for this resource on this type.
}

State.stock_first: []int   // len(buildings)+1 prefix offsets.
State.stock: []Stock_Entry // Level order, then configured need/product/storage order.
```

- `new_session` resolves each building's resources and capacities from its definition,
  allocates `stock_first`/`stock` with the caller's allocator, and copies initial
  amounts from the level `stored` array.
- `reset` recomputes the layout and restores the level's initial amounts without
  allocating.
- `destroy` frees both arrays.
- `Building_Instance.stored` remains the immutable level template used only to seed and
  reset runtime stock.
- Amounts use `f64`; catalog values stay `f32` and are widened at load, matching power.

Phase 1 implements exactly this layout (`src/logic/stock.odin`). The capacity
resolver `logic.stock_capacity` is shared with `config.decode_level`, so the startup
bound and the materialized table can never disagree. `logic.Stock_Entry` is an alias
of `c.Stock_Snapshot`, so the borrowed accessor needs no copy or layout cast. `reset`
keeps the layout (building order and catalog definitions do not change within a
session) and copies the template amounts back, so it allocates nothing.

Read-only accessors, mirroring `staffing_slot_snapshot`:

```text
stock_snapshot(state, index) -> []c.Stock_Snapshot   // Borrowed; invalidated by the next mutation.
```

`c.Stock_Snapshot` carries `resource_id`, `amount`, `capacity`. The accessor returns
a borrowed subslice of authoritative session storage; it copies nothing and the
consumer must not retain it past the next mutation. A separate
`production_snapshot(state, index)` reports the current per-tick input demand, output
rate, and the blocking reason for the inspector. Neither exposes mutable state.

## Recipe semantics

Production and consumption are **hourly batches**. The step is scheduled at each
whole simulated hour, not every minute: at an hour boundary each operational building
either runs the whole hour's recipe or does nothing. This matches the readable
catalog values ("0.1 proteins per hour"), makes the result independent of clock
speed, and pairs naturally with the all-or-nothing rule below.

For one building, at an hour boundary:

- **Reference product.** The per-unit needs are tied to the **first entry of
  `produces`**. Reordering `produces` changes which product defines the ratios, so the
  catalog keeps the intended product first. No schema change is required. The manage
  editor documents and surfaces this convention beside `needs` and `produces`, so an
  author can see which product drives the per-unit ratios.
- **Output per hour.** Every product yields `units_per_hour`.
- **Input per hour.** Every need consumes exactly one of:
  - `amount_per_hour`;
  - `amount_per_unit * reference_product.units_per_hour`.
    Example: `water.amount_per_unit` 30 scales with whatever
    `proteins.units_per_hour` is; at the shipped 10 proteins/hour the farm consumes
    300 water/hour.
- **Deprecated `amount_per_resident`.** The building-level per-resident rate is
  obsolete: individual subject needs already model per-capita consumption. The field
  is removed from `Need` and `Product`, from validation, from the manage schema, and
  from the documentation. The shipped catalog no longer uses it.

Worked example with the shipped `animals_farm` (`proteins` first, then `compost`):

```text
produces: proteins 10/hour (reference), compost 1/hour
needs:    water 30/unit      -> 30 * 10 = 300 water/hour
          vegetables 12/unit -> 12 * 10 = 120 vegetables/hour
```

### All-or-nothing execution

At the hour boundary the recipe runs only when every condition holds:

- every input is available: `stock >= consumed` for each need;
- every output fits after the inputs are applied:
  `stock - consumed + produced <= capacity` for each product.

If any condition fails, the whole recipe is skipped for that hour: no input is
consumed and no output is produced. There is no partial consumption, no partial
production and no scaled-down rate. A skipped hour is a `Production_Blocked`
transition; running again after a skip is `Production_Resumed`. Amounts are
fractional and accumulate; they are not rounded.

## Gating

Production runs at an hour boundary only when the building is operational:

```text
operational = active && level >= 1 && building_staffed(state, index)
```

- `active` is the player's requested state, unchanged by production.
- `level` is the warmup/cooldown ramp. It reaches `1` when warmup completes, matching
  the documented meaning of `warmup_time` ("hours from activation until production
  starts"): no resource is produced while the building is still warming up. The
  electrical output keeps ramping linearly with `level`; only resource production is
  all-or-nothing.
- An enabled but uncovered building consumes nothing and produces nothing while it
  keeps its full `power_need_kw`, does not enter cooldown, and keeps warming up.
- A building with no continuous slots is vacuously staffed.
- `on_demand` slots still create no automatic coverage.

A negative power balance is resolved by the load-shedding rule below, not by scaling
production.

## Power deficit and automatic load shedding

Confirmed rules:

1. Consumption is measured by the configured `power_need_kw`, not by the warmup level.
2. While `available_kw < 0`, immediately force the selected building to a full stop
   (`active = false`, `level = 0`) so its demand disappears in the same tick. It does
   not enter cooldown and stays off until the player re-enables it.
3. Select the active consumer with the greatest `power_need_kw`, tie-broken by lowest
   level index. Repeat (cascade) until `available_kw >= 0` or no eligible building
   remains.
4. Power attributes are mutually exclusive: startup validation requires at least one
   of `power_need_kw` and `power_output_kw` to be zero, so a building either produces
   or consumes power, never both. `always_on` buildings must additionally have
   `power_need_kw = 0`. Eligible buildings for shedding are therefore active
   consumers (`power_need_kw > 0`, `power_output_kw == 0`); generators are never
   selected and the manual generator lock is preserved. Implemented in phase 2: the
   Control Unit and `always_on` types are also excluded, so the pre-existing shutdown
   locks are never overridden. The shipped catalog already satisfies both rules.
5. All sheds of one tick are grouped into a single localized notice that lists the
   affected buildings (localized name plus instance ID). See
   [Notice identity](#notice-identity).

If no eligible building remains and the balance is still negative, the signed balance
is displayed unchanged; the model never invents power.

## Individual needs and fulfillment

Building `amount_per_resident` is removed; the only per-capita consumption is the
subject need now driven by `logic.step_need_fulfillment`
(`src/logic/fulfillment.odin`) and consumed by `step_subject_health` through
`Need_State.fulfillment`.

Wiring rules (confirmed and implemented in phase 3):

1. The hourly fulfillment step sets each individual's `fulfillment` from the stock of
   the building the individual is physically `Inside`, so the existing quadratic
   shortage math runs on real supply. A subject working or resting in a building
   draws from that building; a subject in transit does not draw from anywhere and
   keeps its previous fulfillment.
2. Fulfillment is evaluated at hour boundaries, aligned with building production and
   placed after it: `fulfillment = min(1, available / required)` for the subject's
   hourly `amount_per_hour`. The supplied amount is removed from the building stock;
   the unmet fraction advances the existing shortage clock through the unchanged
   per-tick health step.
3. If a building has no stock entry for the resource, `fulfillment` is set to `1` so
   a level without a stocked supply keeps working, and the gap is reported by
   `config.report_unstocked_resident_needs` as an actionable configuration diagnostic
   instead of silently starving everyone.
4. Aggregate resident counts used for simulation come from physical presence in the
   colony, never from `residents_amount`. `residents_amount` remains the housing
   assignment used for capacity validation and display.

## Events and notices

Reuse the bounded `Event_Queue` and the application notice pipeline. Edge-triggered,
at most once per transition and never per tick:

- `Production_Blocked` / `Production_Resumed`: emitted only when an operational
  building is blocked by a **missing input**. A block caused by full output storage
  publishes no notice; the inspector shows it.
- `Power_Shed`: the automatic load-shedding rule stopped one or more buildings. All
  sheds of one tick are grouped into a single notice listing the affected buildings.

The grouped notice needs a list placeholder, defined together with the notice
identity migration below.

## Notice identity

Confirmed: every building notice names the **localized building name plus the
instance ID** (for example "Meals Factory (MF1)"), replacing the short catalog `code`.
This applies to the existing building notices (`notice_staffing_lost`,
`notice_staffing_restored`, `notice_insufficient_power`,
`notice_generator_required`, `notice_always_on_locked`, `notice_insufficient_health`)
and to the new production and power-shed notices.

`AGENTS.md` and the localization validation now require both the `{name}` and `{id}`
placeholders and reject a building notice template that omits either. The migration
landed as one coordinated change: `AGENTS.md`, the placeholder validation and
required keys, the six building templates in `assets/config/default/localization/en.json`, notice
composition (`build_building_notices` composes the localized `name_key` text and the
level instance ID once per load, without allocating per event) and the regression
tests. The grouped power-shed notice uses the single `{buildings}` list placeholder
with the composed `Localized Name (ID)` fragments joined in shed order. Phase 2
implements it with a preallocated per-session ring of `ui.NOTICE_CAPACITY` buffers
sized to the worst-case joined length, so the bounded notice log keeps borrowing
persistent storage and composition allocates nothing. New notices must not invent a
second convention.

## UI and inspector

- Add a localized stock list to the selected building's inspector: one row per
  resource with `amount/capacity`, plus the per-hour input demand and output rate.
- Show the blocking reason (`missing input`, `output full`, `unstaffed`, `warming up`)
  as localized text.
- Load shedding is an authoritative logic decision; the UI only reflects the
  resulting activity and shows the notice.
- All labels, formats, and notices live in `assets/config/default/localization/en.json`; no hardcoded
  Odin text and no fallback strings.
- Values are read from read-only snapshots; the UI never mutates stock.

Phase 1 implements the stock list half: the inspector shows a localized `Stock`
section with one row per resolved resource (`building_info_stock_header` and the
`building_info_stock` format in `assets/config/default/localization/en.json`), read from
`logic.stock_snapshot`.
Phase 2 adds the resolved per-resource hourly flow (`building_info_stock_flow`) and a
live `Production` line (`building_info_production` plus the six
`production_state_*` labels) derived from `logic.production_status` and
`logic.production_rates`. A full output store is reported here and never as a notice.
Phase 3 removed the obsolete per-resident rate label (`building_info_rate_resident`)
with the schema field; needs and products list only hourly and per-product-unit rates.

## Fixed-tick order

Production is evaluated only at a whole simulated hour boundary, so the recipe stays
hourly and clock-speed independent. Subject need fulfillment shares that boundary
immediately after production, so a building's fresh output is available to its
occupants. Production needs derived staffing, which the order computes after
movement. Implemented placement, keeping the documented health-before-movement
ordering:

```text
step (ramps) -> derive_staffing -> step_production (whole hours only)
  -> step_need_fulfillment (whole hours only)
  -> step_subject_health -> step_medical -> step_shifts -> step_transports
  -> commit_shift_handoffs -> derive_staffing -> step_load_shedding
  -> schedule_staffing -> publish_event_notices
```

`derive_staffing` runs at the start of the tick using the coverage committed at the
end of the previous tick, then again after movement. Production therefore runs on
consistent coverage; the second derivation settles movement before load shedding, so
a coverage loss is paid for in the same tick it happens. The authoritative order and
the logical-tick parameter are recorded in
[Subject Runtime Contracts](subject-runtime-contracts.md#shift-lifecycle-and-physical-handoff),
which owns the tick-order description. One implementation detail differs from an
earlier draft: the clock advances whole frame batches, so `step_production` receives
the reconstructed logical tick index and tests `tick % TICKS_PER_HOUR == 0` instead
of reading the post-frame `clock.ticks`.

## Limits, lifetime, and reload

- Define `STOCK_ENTRY_LIMIT` (buildings times resolved resources) and document the
  overflow policy. Startup configuration bounds it; the session asserts it like
  `STAFFING_SLOT_LIMIT`. **Implemented in phase 1**: the limit is `1024`
  (`logic.STOCK_ENTRY_LIMIT`), startup validation rejects a level whose resolved
  entries exceed it with an actionable diagnostic, and `new_session` asserts the same
  bound. Materialization never truncates.
- Production allocates nothing per tick. **Implemented in phase 2**: the recipe
  metadata borrows catalog slices materialized once per session, the hourly step uses
  only per-building owned bookkeeping (`production_blocked`), and the grouped
  power-shed notice composes into preallocated session storage.
- The event queue keeps its `EVENT_LIMIT` (128) capacity and newest-event drop
  policy. `Power_Shed` queues one event per shed building, so a tick with more sheds
  than the remaining capacity drops the newest shed notices while the authoritative
  shutdowns still happen; `overflowed` stays observable.
- `reset` restores initial amounts; `destroy` frees the arrays; a successful
  development reload builds fresh stock from the new configuration and a failed reload
  preserves the running session and its stock.
- Tracking-allocator tests must prove no block survives reset, destruction, or reload.

## Testing

Headless regression tests, no renderer:

- Recipe math: `amount_per_unit` against the first product, `amount_per_hour`, and
  multiple products where only the reference product drives the ratios.
- All-or-nothing: a shortfall in any single input or a full output store skips the
  entire hour (no partial consumption or production), and the recipe resumes on the
  next hour once conditions hold.
- Hourly scheduling: exactly one evaluation per simulated hour, at hour boundaries,
  independent of clock speed and frame pacing.
- Unstaffed, warming (`level < 1`), cooling, inactive and misconfigured buildings
  neither produce nor consume; a staffing loss does not change `active` or `level`.
- Fractional accumulation over many hours and no drift beyond float tolerance.
- Reset restores initial amounts; destroy and reload free all stock memory.
- Individual `fulfillment` follows the stock of the building the subject is `Inside`,
  evaluated hourly, and drives the existing quadratic shortage maths; a subject in
  transit does not draw.
- Event edge-triggering: one notice per transition, none per tick, correct identity;
  output-full blocks publish nothing; power sheds are grouped per tick.
- Load shedding: greatest `power_need_kw` selection, lowest-index tie-break, cascade
  until balanced, `always_on` need-zero and mutually-exclusive power-attribute
  validation, generators never shed, same-tick demand removal, grouped notice, and
  stability when no eligible consumer remains.
- A chained scenario (water collector -> greenhouse -> meals factory, and a robot
  warehouse residence) with explicit initial stock and asserted end state.

## Implementation phases

0. **Notice identity migration (prerequisite) — complete.** `AGENTS.md`, localization
   validation, the six existing building templates, notice composition and the
   regression tests now use the localized building type name plus the level instance
   ID, for example `Meals Factory (MF1)`. The grouped power-shed `{buildings}` list
   placeholder was reserved for the phase 2 notice, which now implements it.
1. **Runtime stock foundation — complete.** Flat owned stock, capacities, initial
   amounts, `reset`/`destroy`, read-only snapshot, inspector rows, tracking-allocator
   tests. No rates yet, so no gameplay changes. `logic.stock_capacity` is the single
   capacity resolver shared by startup validation and the session; `STOCK_ENTRY_LIMIT`
   is `1024`.
2. **Production and consumption tick — complete.** `logic.production.odin` implements
   the hourly all-or-nothing recipe execution behind the activity/warmup/staffing
   gate, the `Production_Blocked`/`Production_Resumed` edge events, the mutually
   exclusive power startup validation, the automatic load-shedding cascade with the
   grouped `Power_Shed` notice, the inspector production status and resolved hourly
   flow, and the authoritative tick order in
   [Subject Runtime Contracts](subject-runtime-contracts.md#hourly-production-consumption-and-load-shedding-srclogicproductionodin).
   Phase 1's stock list is complemented by the per-resource hourly flow and a live
   blocking-reason line.
3. **Need fulfillment wiring — complete.** `logic.fulfillment.odin` implements the
   hourly individual fulfillment from the building the subject is `Inside` (full,
   partial and zero supply, transit exclusion, hourly alignment), the unstocked-entry
   fallback with the `report_unstocked_resident_needs` startup diagnostic, the
   application call between `step_production` and `step_subject_health`, and the
   removal of the obsolete `amount_per_resident` field from `Need`/`Product`,
   decoding/validation, the manage schema and editor, and the documentation. The
   gameplay smoke drives its shortage episode from real shelter stock instead of the
   retired manual fulfillment placeholder.
4. **Logistics (separate slice, deferred).** Transfers between buildings, including
   the `storage`-only resources that currently have capacity but no source.
   Per-building stock stays the model; a colony pool is not planned.

Do not start phase 4 until phases 0-3 are verified; a production chain is not
playable without logistics, so the acceptance criteria for phase 3 must not claim
playability. Phase 4 (logistics) remains deferred.

## Open decisions

Resolved:

- **1. `amount_per_unit` base:** the first `produces` entry is the reference product;
  needs scale with its `units_per_hour`. No schema change.
- **2. Throttling:** all-or-nothing per hourly batch; nothing is scaled down or
  partially consumed.
- **3. Storage topology:** per building instance; no colony pool. Logistics is a
  later, separate slice.
- **4. Draw source for individual needs:** the building the individual is physically
  `Inside`, evaluated hourly.
- **5. Resident-rate overlap:** the obsolete building `amount_per_resident` rate is
  removed from the schema, validation, manage, catalog, and docs.
- **6. `capacity: 0`:** the catalog was corrected; `0` simply means no stock can be
  held.
- **7. Load shedding:** greatest configured `power_need_kw`; immediate stop; cascade;
  lowest-index tie-break; grouped notice; manual re-enable. Power attributes are
  mutually exclusive (`power_need_kw == 0` or `power_output_kw == 0`), so generators
  are never shed and mixed producer/consumer types are rejected by validation.
- **8. Resident count source:** physical presence in the colony, not
  `residents_amount`.
- **9. Blocked notices:** only for missing input, never for a full output store.
- **10. Notice identity:** localized building name plus instance ID for all building
  notices, with a coordinated `AGENTS.md` and validation migration.
- **Warmup interlock:** confirmed; production starts at `level >= 1` and there is no
  partial material output during warmup.
- **Reference product:** confirmed option A. The first `produces` entry is the
  reference for `amount_per_unit`; the manage editor documents and surfaces the
  convention. No schema change.
- **Grouped notice format:** confirmed `{buildings}` only, one template.

All contracts are now fixed. Phases 0-3 are implemented and verified; phase 4
(logistics) stays deferred.
