# Gameplay Integration Smoke

Status: **task-13 integration smoke implemented and verified**.

`tools/gameplay_smoke` is a headless, deterministic multi-day run of the composed
simulation. It builds a colony from the shipped tuning values (human `work_time` 12h /
`rest_time` 12h / `extra_work_time` 4h and robot 20h / 4h / 8h, shipped health, need
and station-recovery rates), steps it through exactly the fixed-tick order used by
`run_level` in `src/app/main.odin`, prints the observed outcomes and exits non-zero if
an integration invariant is not demonstrated. No window, GPU, asset or random source
is involved.

```sh
odin run tools/gameplay_smoke -out:build/gameplay-smoke.exe
```

The same scenario runs inside the automated suite as
`src/app/gameplay_smoke_test.odin` (`odin test src/app`), so the invariants are
enforced by the documented checks.

## Scenario

One `generator` (continuous worker slot, `power_output_kw` 30) and one `workshop`
(continuous worker slot, `power_need_kw` 5) run beside a solar panel, a human and a
robot residence, an empty shelter and a landing platform. Seven explicit individuals
start the session:

| Subject | Type | Residence | Start |
| --- | --- | --- | --- |
| H1 | human | human home | on shift at the generator |
| H2 | human | human home | unassigned, a long walk from the generator |
| H3 | human | human home | unassigned (medical evacuation) |
| H4 | human | human home | unassigned (death while waiting) |
| H5 | human | human home | isolated in the empty shelter (simultaneous shortages) |
| R1 | robot | robot home | on shift at the workshop |
| R2 | robot | robot home | unassigned, near the workshop |

One `emergency` ship with human/robot capacity is docked at a station 5000 km away;
there is no ordinary cargo or immigration traffic, so population changes only through
the medical rules and death.

### Scripted input

The shortage episode is no longer a manual fulfillment placeholder: the scenario now
carries real per-building runtime stock (homes stock the needs of the subjects they
host; the shelter is deliberately left empty). Inputs stand in for systems that
remain deferred or are player-adjacent, and are applied before the fixed-tick steps
without bypassing them:

- **Need fulfillment** is driven by `logic.step_need_fulfillment` at each hour
  boundary. H5 is placed inside the unstocked `shelter` at hour 0 (with its roles
  cleared so the scheduler cannot move it to a stocked workplace), so both needs stay
  in shortage until the store is refilled by hand at hour 36, representing the
  deferred logistics phase. No `fulfillment` value is set directly.
- **Health events** drive the medical timing deterministically: H3's health is set to
  `0.05` (below its `min_colony_health` of 0.1) at hour 30, H4's health to `0.05` at
  hour 40, and H4's health to zero at hour 42 while it is still
  `Pending_Evacuation` on the platform.

Everything else (scheduling, reservations, movement, handoff, overtime, staffing
gating, power balance, stock-driven fulfillment, dispatch, landing priority, station
recovery, return) is resolved by the simulation itself.

## Observed outcomes (one 72-hour run)

```
Gameplay smoke: 72 simulated hours (4320 fixed ticks)
  population        : 7 -> 6 (deaths 1, conserved true)
  shift handoffs    : 5, overtime entries 1
  staffing events   : lost 3, restored 3
  generator unstaffed: 11.0 h, power-gated ticks 661, min available 15.00 kW
  simultaneous shortage ticks: 2219, health 1.000 -> min 0.760
  medical          : evacuations 2, returns 1, hospitalized true, returned home true
  death while waiting: true, medical landing priority true
```

How each required phenomenon appears:

- **Shift rotation** — R1 and R2 trade the workshop slot on time (robot 20h shifts)
  and H1/H2 rotate the generator slot; five physical occupant handoffs occur with no
  uncovered tick between consecutive shifts.
- **Late replacement** — H2 starts far from the generator, so the just-in-time
  scheduler cannot place it before the shift ends. H1 enters overtime and the
  generator stays unstaffed until H2 arrives (one overtime entry recorded).
- **Staffing-based power suspension** — while the enabled generator is unstaffed its
  output is gated to zero (`power-gated ticks` 661 ≈ 11.0 h); the workshop keeps its
  5 kW demand and the network shows 15.00 kW available instead of 45 kW.
  `Staffing_Lost`/`Staffing_Restored` fire once per transition (three cycles).
- **Simultaneous shortages** — H5 carries water and meals shortages at the same time
  for 2219 ticks; health falls from 1.000 to a minimum of 0.760 and recovers after the
  shelter is resupplied and the next hour boundary restores full fulfillment.
- **Medical evacuation** — H3 crosses `min_colony_health`, walks to the platform and
  boards the emergency ship (`Medical_Evacuation`).
- **Station recovery** — H3 is hospitalized as an identified patient and recovers at
  the configured rate until it reaches `min_work_health`.
- **Return** — H3 requests a return, flies back on the emergency ship, lands and is
  discharged at its original residence (`Medical_Return`), unassigned and rested.
- **Emergency-priority landing** — the focused episode holds the only pad with a busy
  mission and queues an ordinary waiter (earlier ticket 1) and a medical mission
  (ticket 2): the medical mission is admitted to the pad first, as required by the
  non-preemptive two-class rule.
- **Death while waiting** — H4 is removed at zero health while `Pending_Evacuation`
  on the platform (`Subject_Died`); population is conserved at `start - deaths`.

These are balance outcomes of a single controlled run, not final tuning. The health
trajectories depend on the shelter stock episode above; need `fulfillment` is now
driven by real building stock rather than by the retired placeholder.

## Manual verification

The smoke is headless and does not open a window: it proves the simulation-level
integration, not interaction. Interactive play (clicking buildings, resizing,
scrolling the inspector, watching the notices) still requires the manual checklist in
[the README](../README.md#building-inspector) and the offscreen capture in
`tools/info_smoke`; those were not re-run as an interactive session for this task.

## Limits and determinism

The scenario uses only fixed-size session storage: the 4320-tick run needs no
per-tick allocation beyond subsystem manifests, and all random behaviour is absent
(candidate ordering is by role, health, forecast arrival, work time, distance and
stable subject ID). Population conservation (`population_start - deaths ==
population_end`) is asserted so no subject can be silently removed.
