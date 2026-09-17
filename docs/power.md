# Activity, Power, and Notices

## Rules and display

Every new session (including pressing Play again) activates all instances whose
`building_id` is `control_unit` and every instance whose level entry has
`enable_at_start: true`; every other instance starts inactive. After that, activity is
runtime state. Control Units cannot be disabled, regardless of health or available
power. Any active building with configured `power_output_kw > 0` also cannot be
disabled, including during warmup, at zero actual output, with surplus energy, or
when damaged. Inactive generators may still be activated normally; startup flags are
unchanged. Health and repairing do not currently scale power.

Power attributes are mutually exclusive: `power_need_kw` and `power_output_kw` cannot
both be positive, so a building is either a generator or a consumer, never both.
`always_on` types must additionally have `power_need_kw == 0`, because they can never
be stopped. Startup validation rejects either violation with an actionable message,
so generators are never automatic load-shedding candidates.

Click a building to request a toggle. Output follows the startup level once the
building is fully covered (see [Staffing](#staffing)); full
`power_need_kw` is consumed while active or while shutdown has not reached zero. This applies to every
consumer, including the CU when it is configured with a demand. A solar panel
therefore produces 16 kW when active with the current catalog. There is one shared
power network, without distance, wiring, storage, or per-CU capacity limits.

The balance is:

```text
available kW = sum(staffing-gated ramped outputs) - sum(active and still-cooling consumption)
```

Each CU contributes that same available balance, not an additional source of power.
Buildings no longer draw their code or power values over the sprite: the power
balance is available in the inspector and the overview grid. Only fully stopped
buildings (inactive AND level zero) show a black overlay with alpha
128/255 (approximately 50%)
over their entire sprite. Display power uses up to two decimal places without trailing zeros. Fractions below
one keep three significant digits (including scientific notation for tiny nonzero
values); decisions use unrounded values.

A toggle evaluates the *resulting* network, including the output or consumption
of the affected building. If the result would have a deficit, it is rejected:

- Activation below the type's `min_operative_health`: the building is too damaged.
  This is checked before power; shutting a building down is never blocked by health.
- Activation: not enough available power.
- Shutdown of an active producer: always rejected (`Generator_Required`), before
  health or network evaluation, with a localized message explaining the lock.
- CU toggle: the CU must remain active.

Because power attributes are mutually exclusive, no building can power its own
activation: a consumer always needs enough free generation in the resulting network,
and a generator never consumes. There is no partial activation. Unknown instance IDs
are rejected without mutation.
Level loading rejects initial networks (Control Units plus `enable_at_start` buildings)
with insufficient power, and `enable_at_start` buildings below their `min_operative_health`.

Powers originate as f32 catalog values and are summed as f64 in level order.
Comparisons allow a relative tolerance of 1e-7 of the larger total to account for
f32 input rounding (for example, 0.1 + 0.2 versus 0.3). This is not a fixed free-power
allowance: a positive load cannot start from zero output. Tiny negative residuals
within tolerance are presented as zero available power.

## Staffing

Building state keeps three separate values: `active` is the player-requested
activity, `staffed` is derived coverage (every continuous staffing slot physically
covered) and output is the electrical result. An **enabled** building whose
continuous slots are not fully covered produces nothing, but it stays enabled, keeps
consuming its full `power_need_kw`, does not start cooldown and keeps warming up: a
staffing loss is not a deactivation. Coverage is derived from the moved and healthy
subject state before power is evaluated each fixed tick, so missing personnel cannot
produce power during that tick. When coverage returns, output resumes immediately at
the already-reached startup level, without warmup, because the building was never
disabled. Buildings with no continuous slots are vacuously staffed and never gated;
`on_demand` entries still create no automatic slot. See
[Building staffing](building-staffing.md).

The gate applies to displayed output and to command evaluation. A toggle evaluates
the resulting network with enabled-but-uncovered buildings at zero output, so a
command cannot start a network on missing personnel. Locks are unchanged: an active
configured producer still cannot be disabled (`Generator_Required`), health still
gates activation and the Control Unit stays locked. A staffing loss can therefore
make `available_kw` negative while existing load stays enabled; the same tick's
automatic load shedding resolves it (see [Automatic load shedding](#automatic-load-shedding)),
and if no eligible consumer remains the Control Unit displays the signed balance
unchanged.

Coverage transitions publish `Staffing_Lost` and `Staffing_Restored` simulation
events, at most once per transition and never once per tick. Only buildings that
stay enabled across the derivation publish them: disabling or enabling a building is
a player command, not a staffing incident. The first derivation after a reset
baselines without publishing, so a new session never reports every building that
simply starts unstaffed, and a restoration is published only after a loss that was
not yet recovered. The application drains the pending events once per fixed tick,
in sequence order, and shows one localized notice per transition (see [Subject
Runtime Contracts](subject-runtime-contracts.md)); the queue is then cleared so it
cannot fill and drop newer transitions.
Resource production runs hourly behind the same derived coverage, so an unstaffed
building consumes nothing and produces nothing while it keeps its full demand; see
[Building production](building-production.md#gating).

## Warmup and Cooldown

Requested activity switches immediately on a click. Consumption starts immediately
at full `power_need_kw` on activation and stays full throughout cooldown after
deactivation. It drops to zero only when the level reaches zero; it does not fade
proportionally with the level. Visual brightness is independent: deactivation
immediately applies the existing 50% black overlay to the sprite and its text,
including throughout cooldown. Reactivation restores brightness immediately. Zero-duration shutdowns,
or shutdown before any warmup progress, complete immediately. Production follows a startup level in [0,1] instead: displayed and
balanced output is `power_output_kw` times that level, so `+ kW` lines and the CU's
`kW free` change progressively.

- While active, the level rises linearly to 1 over the type's `warmup_time` hours;
  while inactive, it falls to 0 over `cooldown_time` hours. A value of `0` completes
  the transition as soon as the toggle is applied.
- The ramp advances once per clock tick (one simulated minute), so it speeds up with
  the clock and does not advance on the menu. Toggling mid-ramp reverses it from the
  current level for non-producers; active producers cannot enter cooldown through
  toggles. Reactivation keeps the current level and the existing full demand (no
  double reservation). Health checks and gameplay eligibility still use requested
  activity; housing requests are withdrawn immediately, not delayed by illumination.
- Buildings with `always_on=false` show the level as a vertical yellow bar just outside their right
  edge (width 8% of the building on screen, clamped to 3–12 units, over a dark
  track), filling bottom-up. It is not dimmed and does not consume clicks.
  Buildings with `always_on=true` hide both the fill and track. Logic rejects their
  shutdown with `Always_On_Locked` before changing activity, power or cooldown; the
  UI displays a localized notice. The Control Unit retains its dedicated lock.
  Visual check: in Play, verify always-on buildings have no activity bar while
  other buildings still show it, including during warmup and cooldown.
- Buildings active when a session starts begin at full level, without warmup.
- Toggle checks reserve output pessimistically: a warming building offers only its
  current output (full output if `warmup_time` is 0), and a cooling building offers
  nothing, even though its displayed output fades out. Need is reserved in full from
  activation through the final cooldown tick. New activation checks include every
  cooling consumer, so power cannot be reused prematurely. Levels only rise while
  active, so a toggle never creates a deficit. A consumer always needs other
  generation, because no building may produce and consume at the same time.

`Building_Snapshot.active` remains the command/request state. The separate read-only
`energized` value is `active || level > 0`, even for types with zero configured demand.
Logic uses it for snapshot demand and network totals; app maps `active && energized`
to render's `Building_Draw.illuminated`. Render only applies the overlay, never decides electrical
eligibility. Resource needs/products, producer locks and transition durations are
unchanged. Residence evacuation is a separate request: people stay through cooldown
and leave once zero is reached; see [Residence evacuation](space_station.md#residence-evacuation).

Regression checks cover intermediate shutdown, the final tick, budget contention,
reactivation, cancellation before warmup progress and zero-duration transitions.
Visual check: disable a warmed consumer; confirm its sprite/text dim immediately
while its full kW demand remains displayed and the undimmed yellow bar drains.
At zero, demand drops to zero and the building stays dim. Re-enable midway and
confirm brightness returns without a level reset.

## Automatic load shedding

A negative balance is resolved by logic in the same fixed tick that created it (a
staffing loss, for example):

1. Consumption is measured by the configured `power_need_kw`, not by the warmup level.
2. While `available_kw < 0`, the active consumer with the greatest configured demand
   is force-stopped (`active = false`, `level = 0`), lowest level index first on a
   tie. The step repeats until the balance is nonnegative or no eligible building
   remains.
3. Generators (`power_output_kw > 0`), `always_on` types and the Control Unit are never
   shed: their demand is validated to be zero or their existing shutdown lock wins.
4. A shed building does not enter cooldown. It stays off until the player re-enables
   it, and re-enabling is evaluated against the resulting network like any other
   toggle.
5. Every shed appends one edge-triggered `Power_Shed` event in shed order. All sheds
   of one tick are grouped into a single localized notice that lists the affected
   buildings as `Localized Name (ID)`, for example `Meals Factory (MF1)`.

If no eligible building remains and the balance is still negative, the signed balance
is displayed unchanged; the model never invents power. A disabled building that is
still cooling keeps consuming until its level reaches zero and is never a shed
candidate, because it is already off.

## Input and notices

The UI resolves clicks in reverse draw order, so only the topmost building reacts
when rectangles overlap. Right/bottom edges are exclusive. A persistent notice
panel occupies the bottom of the window (16 screen-unit margins, 144 units tall)
and consumes clicks even while empty. Clicks
outside buildings, unfocused input, and an Escape frame do not submit commands.
The Play click is consumed by the menu and cannot also toggle a building.

Each warning lasts ten seconds of presentation elapsed time, including time while
unfocused. New warnings append below previous ones without resetting their timers;
repeated warnings remain separate entries. The panel grows to fit wrapped rows
from the four newest messages, within the viewport. If extreme content still
exceeds the available height, it follows the newest visible rows (no manual
scrolling). Station and transport panels reserve this measured notification area. Messages are left-aligned at the shared fixed 24-pixel font
size, not scaled down. The persistent warning buffer and expiration remain unchanged.

UI owns a fixed 32-entry chronological buffer, with no heap allocations. Overflow
drops the oldest entry, even if it has not expired. Expiration compacts the buffer
without changing order. Large elapsed times expire all elapsed entries immediately;
negative/NaN intervals are ignored. Play clears the entire log. The renderer receives
a value snapshot of the visible rows; text borrows persistent localization storage.
Staffing loss/restoration, production blocked/resumed, medical dispatch/return and
death each add one edge-triggered notice when their simulation event is published, in
event order; automatic load shedding adds one grouped notice per tick.
Warnings and power format strings are loaded from `assets/config/default/localization/en.json`.
Each power format requires the literal `{value}` placeholder, replaced with the
formatted numeric value; localization strings are not executed as printf formats.

## Ownership and timing

- `logic.State` owns separate instance, activity, and per-instance power arrays.
  The caller supplies their allocator. IDs borrow immutable startup configuration.
- `logic.toggle` takes a stable ID and returns a typed result synchronously. Commands
  are applied in delivery order, with no queue and no per-command allocations.
  Rejections leave all authoritative state unchanged.
- Snapshots contain activity, derived staffing and actual per-instance power values;
  the application reads the global balance and creates presentation descriptions after
  the command.
- Staffing coverage is session state derived from the subject simulation; power and
  production never write it back, and a staffing loss never changes requested
  activity or warmup/cooldown progress.
- `Staffing_Lost`/`Staffing_Restored` events are queued in the session's bounded event
  log in deterministic building order; delivery and overflow behavior follow
  [Subject Runtime Contracts](subject-runtime-contracts.md). The application drains
  them once per fixed tick and converts each to a localized notice; medical and death
  events use the same path and order.
- UI owns notice lifetime and pointer hit testing; it returns semantic toggle
  commands and cannot mutate logic. Renderer owns only drawing, including dimming.
- Notice text borrows persistent localization strings. Numeric display strings use
  frame-temporary storage and are discarded immediately after synchronous drawing.

Power is an instantaneous, command-driven constraint in **kW**, not accumulated
energy in kWh. This feature introduces no resource production ticks or energy
integration. Notice timing is cosmetic UI time and does not affect game rules.

## Game Clock

- `logic.Clock` lives in `logic.State` and is reset by Play. Simulation time moves
  in fixed ticks of one simulated minute (`TICKS_PER_HOUR = 60`); at 1× one simulated
  hour passes per real second, independent of the frame rate.
- `advance_clock` turns real frame time into whole ticks and keeps the fraction for
  later frames. It returns the tick count; future time-based rules must run once per
  tick, never per frame. Negative, zero, and NaN intervals advance nothing.
- Catch-up is bounded: at most 0.25 real seconds per frame are simulated, so one frame
  runs at most 480 ticks (at 32×). Longer stalls are dropped, not replayed.
- Speed levels are 1×, 2×, 4×, 8×, 16×, and 32× simulated hours per real second.
  `speed_up`/`slow_down` (E/Q by default) step one level per press and saturate at
  both ends. UI turns input into a `Speed_Change` command only when focused, not on
  an Escape frame, and not when both are pressed. The change applies before that
  frame's time is advanced, keeping pending fractional progress.
- The clock runs while the window is unfocused. It does not run on the menu; the
  menu is the pause screen. Escape leaves the scene and freezes the clock; Resume
  Game continues from hour and speed unchanged, while Play starts a new session at
  hour 0. Both are menu actions, not configurable bindings. Frame time while paused
  is discarded rather than accumulated (`session_ticks` returns zero), so resuming
  never catches up; only the sub-tick remainder is preserved.
- The top-left HUD panel (16-unit margin, 260×40 normally, growing vertically when
  its text wraps at the fixed font size) shows `hud_clock_format` from
  `en.json`, which requires `{hours}` (whole elapsed hours) and `{speed}`. Like the
  notice panel, it consumes clicks and wheel zoom, but not an ongoing pan drag.

## Manual smoke test (pending)

1. Play: only CU is undimmed, all actual power values are zero.
2. Click a consumer first: it stays dimmed and a warning appears for ten seconds.
3. Enable one SP: CU reports 16 kW free. Enable RW and WC: CU reports 6 kW free.
4. Attempt GH (8 kW): it stays inactive. Attempt to disable SP: it stays active.
5. Enable a second SP, then GH: 32 produced, 18 consumed, 14 free.
6. Disable WC, then attempt to disable one SP: it remains active, with a producer-lock
   warning; 32 produced, 15 consumed, 17 free. Disable all consumers and verify both
   SPs still reject shutdown.
7. Click CU: it remains active. Trigger several warnings: verify separate rows scroll upward and expire independently.
8. Verify the panel consumes clicks and overlapping buildings toggle only once.
9. Resize to 640x360 and maximize: building sprites and activity bars stay aligned and centered; the message panel remains bottom-anchored.
10. Return to the menu and Play again: only CU is active and the panel is empty.
