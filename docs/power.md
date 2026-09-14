# Activity, Power, and Notices

## Rules and display

Every new session (including pressing Play again) activates all instances whose
`building_id` is `control_unit` and leaves every other instance inactive. Activity is runtime
state, not a level JSON property. Control Units cannot be disabled, regardless of
health or available power. Health and repairing do not currently scale power.

Click a building to request a toggle. Only active instances produce their configured
`power_output_kw` and consume their configured `power_need_kw`. This applies to all
types, including producers with their own consumption and the CU. A solar panel
therefore produces 16 kW when active with the current catalog. There is one shared
power network, without distance, wiring, storage, or per-CU capacity limits.

The balance is:

```text
available kW = sum(active outputs) - sum(active consumption)
```

Each CU displays that same available balance, not an additional source of power.
The renderer prints the code, `+... kW` for configured producers, `-... kW` for
consumption, and `... kW free` on the CU. Inactive buildings display zero actual
production/consumption and a black overlay with alpha 128/255 (approximately 50%)
over their entire rectangle and text. The whole text block fits inside the building.
Display values use two decimal places; decisions use unrounded values.

A toggle evaluates the *resulting* network, including both output and consumption
of the affected building. If the result would have a deficit, it is rejected:

- Activation: not enough available power.
- Shutdown: other buildings still need the producer's power.
- CU toggle: the CU must remain active.

For a building that both produces and consumes, its own output can support its
activation; disabling it also removes its demand. No automatic load shedding or
partial activation occurs. Unknown instance IDs are rejected without mutation.
Initial CU-only networks with insufficient power are rejected during level loading.

Powers originate as f32 catalog values and are summed as f64 in level order.
Comparisons allow a relative tolerance of 1e-7 of the larger total to account for
f32 input rounding (for example, 0.1 + 0.2 versus 0.3). This is not a fixed free-power
allowance: a positive load cannot start from zero output. Tiny negative residuals
within tolerance are presented as zero available power.

## Input and notices

The UI resolves clicks in reverse draw order, so only the topmost building reacts
when rectangles overlap. Right/bottom edges are exclusive. A persistent notice
panel occupies the bottom of the window (16 screen-unit margins, 112 units tall)
and consumes clicks even while empty. Clicks
outside buildings, unfocused input, and an Escape frame do not submit commands.
The Play click is consumed by the menu and cannot also toggle a building.

Each warning lasts ten seconds of presentation elapsed time, including time while
unfocused. New warnings append below previous ones without resetting their timers;
repeated warnings remain separate entries. The panel follows the latest four rows,
scrolling older messages upward automatically (no manual scrolling). Messages are
left-aligned and scaled to fit their row; the newest row stays at the bottom.

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
energy in kWh. No time-based simulation is advanced by rendering; this feature
introduces no resource production ticks or energy integration. A bounded fixed-step
simulation loop is still required before implementing time-dependent production,
repair, or storage. Notice timing is cosmetic UI time and does not affect game rules.

## Manual smoke test (pending)

1. Play: only CU is undimmed, all actual power values are zero.
2. Click a consumer first: it stays dimmed and a warning appears for ten seconds.
3. Enable one SP: CU reports 16 kW free. Enable RW and WC: CU reports 6 kW free.
4. Attempt GH (8 kW): it stays inactive. Attempt to disable SP: it stays active.
5. Enable a second SP, then GH: 32 produced, 18 consumed, 14 free.
6. Disable WC, then one SP: 16 produced, 15 consumed, 1 free.
7. Click CU: it remains active. Trigger several warnings: verify separate rows scroll upward and expire independently.
8. Verify the panel consumes clicks and overlapping buildings toggle only once.
9. Resize to 640x360 and maximize: building text remains centered/scaled; the message panel remains bottom-anchored.
10. Return to the menu and Play again: only CU is active and the panel is empty.
