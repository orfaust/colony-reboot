# Activity, Power, and Notices

## Rules and display

Every new session (including pressing Play again) activates all instances whose
`building_id` is `control_unit` and every instance whose level entry has
`enable_at_start: true`; every other instance starts inactive. After that, activity is
runtime state. Control Units cannot be disabled, regardless of health or available
power. Any active building with configured `power_output_kw > 0` also cannot be
disabled, including during warmup, at zero actual output, with surplus energy, or
when damaged. This includes mixed producer/consumer types, not just solar panels.
Inactive generators may still be activated normally; startup flags are unchanged.
Health and repairing do not currently scale power.

Click a building to request a toggle. Output follows the startup level; full
`power_need_kw` is consumed while active or while shutdown has not reached zero. This applies to all
types, including producers with their own consumption and the CU. A solar panel
therefore produces 16 kW when active with the current catalog. There is one shared
power network, without distance, wiring, storage, or per-CU capacity limits.

The balance is:

```text
available kW = sum(ramped outputs) - sum(active and still-cooling consumption)
```

Each CU displays that same available balance, not an additional source of power.
The renderer prints the code, `+... kW` for configured producers, `-... kW` for
configured consumers (a zero `power_need_kw`, as on the Solar Panel and CU, shows no
consumption line), and `... kW free` on the CU. Only fully stopped buildings
(inactive AND level zero) display zero consumption and a black overlay with alpha
128/255 (approximately 50%)
over their entire rectangle and text. The whole text block fits inside the building.
Display power uses up to two decimal places without trailing zeros. Fractions below
one keep three significant digits (including scientific notation for tiny nonzero
values); decisions use unrounded values.

A toggle evaluates the *resulting* network, including both output and consumption
of the affected building. If the result would have a deficit, it is rejected:

- Activation below the type's `min_operative_health`: the building is too damaged.
  This is checked before power; shutting a building down is never blocked by health.
- Activation: not enough available power.
- Shutdown of an active producer: always rejected (`Generator_Required`), before
  health or network evaluation, with a localized message explaining the lock.
- CU toggle: the CU must remain active.

For a building that both produces and consumes, its own output can support its
activation only when its `warmup_time` is 0; once active it cannot be disabled. No automatic load shedding or
partial activation occurs. Unknown instance IDs are rejected without mutation.
Level loading rejects initial networks (Control Units plus `enable_at_start` buildings)
with insufficient power, and `enable_at_start` buildings below their `min_operative_health`.

Powers originate as f32 catalog values and are summed as f64 in level order.
Comparisons allow a relative tolerance of 1e-7 of the larger total to account for
f32 input rounding (for example, 0.1 + 0.2 versus 0.3). This is not a fixed free-power
allowance: a positive load cannot start from zero output. Tiny negative residuals
within tolerance are presented as zero available power.

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
  active, so the balance never shows a deficit.
  A producer that also consumes therefore needs other power while it warms up.

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
Warnings and power format strings are loaded from `assets/localization/en.json`.
Each power format requires the literal `{value}` placeholder, replaced with the
formatted numeric value; localization strings are not executed as printf formats.

## Ownership and timing

- `logic.State` owns separate instance, activity, and per-instance power arrays.
  The caller supplies their allocator. IDs borrow immutable startup configuration.
- `logic.toggle` takes a stable ID and returns a typed result synchronously. Commands
  are applied in delivery order, with no queue and no per-command allocations.
  Rejections leave all authoritative state unchanged.
- Snapshots contain activity and actual per-instance power values; the application
  reads the global balance and creates presentation descriptions after the command.
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
- The clock runs while the window is unfocused. It does not run on the menu; leaving
  the scene and pressing Play starts a new session at hour 0. There is no pause yet.
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
9. Resize to 640x360 and maximize: building text remains centered/scaled; the message panel remains bottom-anchored.
10. Return to the menu and Play again: only CU is active and the panel is empty.
