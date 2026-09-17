# Development configuration reload

Run from the repository root (create `build` first). Verified on Windows with
Odin `dev-2026-01-nightly:7fa05f1` and vendored raylib 5.5:

```sh
odin run src/app -define:DEVELOPMENT_RELOAD=true -out:build/colony-reboot-dev.exe
```

Append `-- --config <name>` to develop against another configuration version:

```sh
odin run src/app -define:DEVELOPMENT_RELOAD=true -out:build/colony-reboot-dev.exe -- --config test1
```

With the game focused, **Ctrl+R** reloads configuration and immediately restarts the
current level, including when the menu is open. Hold does not repeat; release R and
press it again for another reload. Either Control key works. The chord is consumed
before menu, inspector, camera, speed and configurable gameplay bindings. There is
no watcher. Save all related files before pressing the shortcut.

## Explicit mode, not debug inference

`odin help run` describes `run` as build followed by execution. Compiler probes
showed `ODIN_BUILD_MODE == Executable` for both `run` and `build`; `ODIN_DEBUG`
only changes with `-debug`. `ODIN_RUN` and `ODIN_COMMAND` were not defined. No direct
run/build discriminator was found in the available compiler interface. We do not
infer the mode from parent processes, executable names or debug information.

`DEVELOPMENT_RELOAD` is an explicit compile-time capability, default **false**.
Bare `odin run src/app`, ordinary builds and `-debug` alone do **not** enable reload.
A build deliberately supplied the define is also a development executable; it is
not a production artifact. `python tools/build.py` does not supply the define and
continues to validate assets and build the normal executable with reload disabled.
The command above is the supported practical development-run contract.

## Transaction and lifetime

Each attempt rereads English localization, resources, buildings, subject roles,
subjects, ships, space stations, key bindings and the current level source. The
selected configuration version stays selected (`assets/config/<version>`), and the
current implementation supports only that version's `levels/level_0.json`; reload
keeps that source, never selects a different version or level, and never resets
against stale decoded data.
All normal JSON/schema, ID/reference, role, stock, localization and binding-name
validation runs again. Nonempty building, subject-type and per-role subject sprite
paths are reloaded into new GPU textures, even when their path names have not changed.

A heap-stable candidate owns a separate 64-byte-aligned arena. No old state is
mutated during JSON/binding validation. The render module stages a separate texture
cache on the graphics thread; missing/undecodable/invalid textures release only the
staged resources. Failures print the offending file/reference or sprite path and a
retry instruction to the developer console. Old configuration, localization, GPU
cache, population and game progress remain usable. A failed attempt cancels a
pending inspector right-click gesture and consumes its input frame, but otherwise
keeps UI state. Disk/GPU staging time is not simulated as catch-up time.

On success, texture replacement commits first, then the old level loop exits and
frees all transport manifests and individual storage before its arena is destroyed.
Fresh constructors rebuild the complete session: the clock (hour zero, 1x, no
fractional ticks), building state, health/need rates and per-need state, the
materialized continuous staffing slots and their derived coverage, reservations,
individuals, station stock/remainders, ships, patients and emergency queues,
reservations, evacuation requests/ownership and landing FIFO. Failed reload keeps
the entire previous playable session intact: active shifts and their coverage,
individual health and need state, pending/hospitalized patients, in-flight medical
missions, evacuation requests and landing order are all preserved. Initially
active housing may dispatch fresh missions normally. Menu state, notices, inspector
selection/scroll, transport scroll and camera are recreated; no UI references to
old strings survive. The localized window title is updated. A blank commit frame
pumps input before the new loop, so the same raylib key edge cannot trigger twice.
The window/context and fixed UI font remain alive; there are no per-frame asset
loads. Candidate allocation failure is subject to Odin's normal allocator failure
policy, not a recoverable JSON error. Files are read sequentially, not as an atomic
filesystem snapshot.

## Capacities, overflow and lifetime

Startup validation on the candidate rejects a level that cannot fit the fixed
runtime tables, with an actionable message instead of silent truncation:
`STAFFING_SLOT_LIMIT` (1024) continuous slots, `SUBJECT_LIMIT` (16384) initial
individuals and `NEED_SLOT_LIMIT` (8) needs per subject type. At runtime the mission
log is bounded by `TRANSPORT_LIMIT` (128): demand stays pending and no stock is
consumed. Medical requests and patients are per-subject state on the individual
record (`MEDICAL_REQUEST_LIMIT`/`PATIENT_LIMIT` alias `SUBJECT_LIMIT`), so there is
no separate table that can overflow, and the event queue is bounded by `EVENT_LIMIT`
(128) with the newest event rejected and `overflowed` observable. A full individual
array rejects a new record explicitly (a removed slot is reused by full overwrite);
no subject is silently removed. Every owned array and manifest is released on
successful reload, on reset, on failed reload (only the candidate is freed) and on
shutdown; the delete paths are exercised by tracking-allocator tests.

The simulation advances only while a session is running: the menu and the
reload-staging frame advance no tick. `advance_clock` ignores zero, negative and NaN
intervals, and bounds one frame to `MAX_FRAME_SECONDS` of real time (at most 480 fixed
one-minute ticks at 32x), so a stall is dropped rather than caught up unboundedly.

## Verified checks

- The development command above was launched, focused and sent Ctrl+R held for two
  seconds: exactly one successful reload was logged and the game closed normally.
  `odin run src/app -out:build/colony-reboot-dev.exe -debug` was also exercised with
  the same held chord: zero reloads, confirming debug alone does not enable it.
- `odin run src/app -define:DEVELOPMENT_RELOAD=true -out:build/reload-smoke.exe -- --reload-smoke`
  opens the real backend, reloads JSON and textures in a new arena, updates the
  title, pumps the commit frame and shuts down. This opt-in smoke argument exists
  only in development mode.
- App headless regressions cover malformed JSON, unknown references, sprite-stage
  failure, preservation of old data and progress (active shifts and coverage,
  individual health and needs, pending patients, evacuation flags, landing order and
  queued events), changed valid level data, fresh clock/transport/stock/staffing
  reset, and that reload candidate arenas are released on success and failure.
- Render headless regressions cover focus, disabled mode, press-versus-held input
  and consumption. The existing `SPRITE_GPU_TEST` smoke verifies failed texture
  replacement retains the previous usable cache and releases partial staging.

Further manual checks: edit a localized label, role/sprite or level instance; reload
while the inspector is scrolled and transports are active; verify fresh values and
reset UI. Break a JSON reference or PNG and confirm the existing scene keeps drawing
and playing; repair it and retry. No claim of an exhaustive manual gameplay review
is made by the automated smoke checks.
