# Development configuration reload

Run from the repository root (create `build` first). Verified on Windows with
Odin `dev-2026-01-nightly:7fa05f1` and vendored raylib 5.5:

```sh
odin run src/app -define:DEVELOPMENT_RELOAD=true -out:build/colony-reboot-dev.exe
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
current implementation supports only `assets/levels/level_0.json`; reload keeps
that source, never selects a different level or resets against stale decoded data.
All normal JSON/schema, ID/reference, role, stock, localization and binding-name
validation runs again. Nonempty building and role sprite paths are reloaded into
new GPU textures, even when their path names have not changed.

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
Fresh constructors rebuild game state, clock (hour zero, 1x, no fractional ticks),
station stock/remainders, subjects, ships, reservations, evacuation requests/ownership
and landing FIFO. Failed reload keeps ongoing evacuation intact. Initially
active housing may dispatch fresh missions normally. Menu state, notices, inspector
selection/scroll, transport scroll and camera are recreated; no UI references to
old strings survive. The localized window title is updated. A blank commit frame
pumps input before the new loop, so the same raylib key edge cannot trigger twice.
The window/context and fixed UI font remain alive; there are no per-frame asset
loads. Candidate allocation failure is subject to Odin's normal allocator failure
policy, not a recoverable JSON error. Files are read sequentially, not as an atomic
filesystem snapshot.

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
  failure, preservation of old data and progress, changed valid level data, and
  fresh clock/transport/stock reset.
- Render headless regressions cover focus, disabled mode, press-versus-held input
  and consumption. The existing `SPRITE_GPU_TEST` smoke verifies failed texture
  replacement retains the previous usable cache and releases partial staging.

Further manual checks: edit a localized label, role/sprite or level instance; reload
while the inspector is scrolled and transports are active; verify fresh values and
reset UI. Break a JSON reference or PNG and confirm the existing scene keeps drawing
and playing; repair it and retry. No claim of an exhaustive manual gameplay review
is made by the automated smoke checks.
