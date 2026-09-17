# Agent Guidelines

## Scope and Project Direction

These guidelines apply to the entire repository.

- Develop a 2D video game using animated PNG sprites (individual frames or sprite sheets).
- Implement the engine in Odin.
- Keep the logic, UI, and render modules separate, while allowing them to communicate through explicit contracts.
- Support the possibility of a future 3D renderer without coupling game rules or UI behavior to the current 2D implementation. Do not implement speculative 3D systems now.
- Write all documentation and code comments in English. Use English identifiers as well.
- Store every player-facing UI text in a separate localization JSON file, never in Odin code. This includes window titles, menu labels, messages, tooltips, and future widgets. For now, support English only through `localization/en.json` of the active configuration version (`assets/config/default/localization/en.json` by default) using stable named keys.
- Load and validate localization once at startup; keep its strings alive while the UI uses them. Missing files, invalid JSON, or missing/empty required text must produce actionable diagnostics rather than hardcoded UI fallbacks. Developer-only console diagnostics are not UI text.

## Configuration Versions

- Keep every JSON configuration file of a version inside `assets/config/<version>`: the catalogs (`buildings.json`, `resources.json`, `subjects.json`, `subject_roles.json`, `ships.json`, `space_stations.json`, `key_bindings.json`), the levels (`levels/level_*.json`) and the localization (`localization/en.json`). Sprites and fonts stay shared under `assets/sprites` and `assets/fonts`.
- `default` is the shipped version and the loader fallback. Create another version only by copying `default`, and edit it through the asset manager or by hand; never split one version across directories.
- Version names are one safe path segment (1-64 letters, digits, `-`, `_`). Reject anything else before building a path, so a mistyped argument cannot escape `assets/config`.
- Select the version at runtime; do not hardcode it. New code reads paths through `config.Profile`/`config.profile_path` rather than spelling `assets/config/...` inline, and error messages name the file, not a fixed version directory.

The project starts with a window and main menu using Odin's vendored raylib. The architecture below also defines expectations for future gameplay; do not assume unimplemented systems already exist. See README.md for the current toolchain and verified commands.

## Architecture and Module Boundaries

Use distinct Odin packages for the three primary modules. Keep dependencies acyclic and public APIs small.

### Logic Module

- Own authoritative game state, rules, simulation, and interactions between gameplay components.
- Validate and apply player or system commands; publish results through events or read-only snapshots.
- Keep gameplay collision, movement constraints, and other simulation decisions here, not in rendering.
- Remain independent of UI widgets, windowing, graphics APIs, textures, and GPU resources.
- Allow simulation and tests to run headlessly.

### UI Module

- Own interactive controls, menus, HUD behavior, focus, and UI-local state.
- Convert input into semantic actions or commands instead of directly mutating game state.
- Consume read-only game views and events through explicit contracts.
- Produce presentation data for rendering; do not issue backend graphics calls from widget behavior.
- Define input consumption and focus rules so interactions with UI do not unintentionally trigger gameplay actions.

### Render Module

- Own presentation, draw submission, cameras, graphical resources, and graphics-backend integration.
- Initially draw animated PNG sprites and UI presentation data.
- Consume explicit render descriptions; never decide gameplay outcomes or mutate authoritative simulation state.
- Hide backend types, texture handles, and GPU resource lifetimes behind its API.
- Keep sprite-specific structures within the 2D presentation path. A future 3D path may introduce its own data without changing gameplay command contracts.

### Composition and Communication

- Use an application/composition layer to initialize modules, route input and commands, advance simulation, build presentation views, and shut down resources.
- Put only genuinely shared contracts in a small, dependency-free package: IDs, commands, events, and necessary value types. Do not turn it into a miscellaneous utilities package.
- Prefer typed procedure APIs and explicit data flow over global mutable state, hidden callbacks, or a universal event bus.
- The primary modules must not import one another's implementation packages. Use shared contracts and application-level adapters where translation is needed.
- Document ownership, mutability, lifetime, delivery order, and error behavior at module boundaries. Define queue limits and overflow behavior if queues are introduced.
- Use stable IDs across boundaries rather than pointers into another module's mutable storage.

Expected data flow:

```text
Platform input -> UI / action mapping -> Commands -> Logic
Logic -> Read-only views and events -> Application adapters / UI
Application adapters + UI -> Render descriptions -> Render backend
```

## Game Loop and Time

- Advance gameplay with a fixed simulation timestep, independently of rendering frequency.
- Use a bounded accumulator/catch-up policy to avoid unbounded work after a stall. Document pause, resume, and time-scaling behavior.
- Interpolate presentation between simulation states where appropriate; never write interpolated values back into authoritative state.
- Drive sprite animation by elapsed time or simulation ticks, never by rendered frame count.
- Keep gameplay-relevant animation timing in the simulation. Cosmetic animation may use presentation time.
- Make random seeds explicit in simulation tests. Do not claim cross-platform determinism without verification.

## Sprites and Asset Pipeline

- Keep source assets separate from generated atlases and build outputs. Document how generated assets are reproduced.
- Define animation metadata explicitly: frame rectangles, frame durations, loop behavior, pivots, and animation names or IDs.
- Validate image dimensions, frame bounds, positive durations, and asset references during loading or asset processing.
- Document world units, screen coordinates, axis directions, sprite pivots, draw ordering, and alpha-blending conventions.
- Choose filtering and scaling deliberately. Use nearest-neighbor sampling and pixel alignment when the art direction is pixel art, not merely because assets are PNGs.
- Cache decoded assets and GPU resources; do not load or decode images in the per-frame hot path.
- Define useful error messages and fallback behavior for missing or invalid assets.
- Track third-party asset licenses and attribution. Do not add assets of unknown provenance.

## Odin Coding and Memory Practices

- Follow idiomatic Odin and maintain consistent naming and formatting within each package.
- Prefer simple procedures, explicit data structures, and composition. Introduce an ECS or other framework only when requirements justify it.
- Make allocation and ownership explicit. Distinguish persistent state, level/session storage, and frame-temporary memory.
- Never retain pointers, slices, or strings backed by temporary allocators beyond their lifetime.
- Pair allocations and resource creation with cleanup on success, failure, and shutdown paths; use `defer` where appropriate.
- Avoid unnecessary allocations in simulation and render hot paths. Measure before introducing complex optimizations.
- Check fallible operations and return meaningful errors. Reserve assertions for programmer invariants, not malformed external data.
- Keep unsafe code, foreign bindings, and platform-specific code isolated and documented.
- Do not add concurrency without defining data ownership, synchronization, and graphics-thread constraints.

## Quality, Testing, and Performance

- Add headless unit tests for game rules, component interactions, command validation, and state transitions.
- Test module contracts and command/event ordering without requiring a real renderer.
- Test animation timing, looping, invalid metadata, pause behavior, and large elapsed-time values.
- Exercise UI focus, input consumption, resizing, coordinate conversion, and supported scaling modes.
- Use visual smoke tests for rendering changes; screenshots or golden-image tests may supplement, not replace, logic tests.
- Add regression tests for fixed bugs where practical.
- Profile representative scenes before optimizing. Track frame time, simulation time, allocations, draw calls, and resource usage against documented target hardware and budgets.
- Prefer batching and appropriate culling when measurements justify them. Preserve correct transparency and draw order.
- Keep diagnostics actionable and avoid logging every frame in normal operation.

## Build, Dependencies, and Documentation

- Record the supported Odin compiler version, platforms, graphics backend, and dependency versions when selected.
- Provide reproducible build, run, and test commands in the README once the project structure exists. Do not document unverified commands as working.
- Prefer Odin's standard and vendor libraries when suitable. Justify additional dependencies and check their licenses and platform support.
- Keep generated files, local configuration, caches, and binaries out of version control unless explicitly required.
- Document significant architectural decisions, public contracts, and non-obvious constraints in English. Comments should explain intent and invariants rather than restate code.
- Keep build instructions and architecture documentation synchronized with implementation changes.
- If save files are introduced, use a versioned format and validate loaded data; do not serialize raw pointers or GPU handles.

## Manage List Editor Convention

- For every new or substantially changed list-of-elements editor in `manage`, use
  the existing master-detail interaction: selectable list on the left and only the
  selected element's properties on the right. Reuse `master-detail`, `list-panel`,
  `item-list`, and `detail-panel` styling and its responsive stacking behavior.
- Keep creation and ordering controls with the list, and selected-element actions
  with the detail panel. Preserve selection when reordering either the selected
  element or a neighbor; select newly created elements and handle empty/deleted
  selections explicitly. Respect domain restrictions (for example, required role
  IDs cannot be duplicated to create arbitrary new roles).
- Preserve validation, localization references, unknown fields, undo/history keys,
  and malformed-data repair paths. Do not silently normalize loaded data.
- Apply this convention going forward, including nested element editors when they
  are introduced or redesigned. Do not rewrite unrelated existing editors merely
  to enforce it; any migration must stay within the requested task's scope.

## Player-Facing Notice Convention

- A notice that reports an event about a specific entity must name that entity
  with its stable display identifier, never a generic "a building", "this
  building" or "a subject" phrase. Building notices use the localized building
  type name plus the level instance ID, for example
  `{name} ({id}) lost its staffing...` rendering as `Meals Factory (MF1)`; the
  short catalog `code` is not a notice identity.
- Localization templates for such notices declare the placeholders (`{name}` and
  `{id}` today) and validation rejects a template without either. A template that
  still contains a placeholder must never reach `ui.show_notice` uncomposed.
- Compose per-entity text once at load time (`build_building_notices` and
  `BUILDING_NOTICE_KEYS`) so the bounded notice log keeps borrowing persistent
  arena/localization storage and never allocates per event. Adding a new
  building-specific template means adding its key there, plus the `{name}` and
  `{id}` validation and schema/metadata entries.
- A grouped notice that reports one event affecting several entities uses a single
  list placeholder (`{buildings}` for automatic load shedding), lists the affected
  entities in event order using the same stable identity as the per-entity notices,
  and is emitted once per tick, never once per entity. Compose it into preallocated
  session storage (the `Power_Shed_Notices` ring): a grouped notice must not allocate
  per event either.
- Subject-specific notices name the subject by its localized type name and runtime
  ID. If a new subject notice needs that, extend the same precomposition pattern
  rather than formatting into frame-temporary memory, which would dangle once the
  frame ends.
- Apply this going forward: new notices follow the convention, and existing generic
  notices are migrated only when the change is in scope.

## Agent Workflow and Definition of Done

- Inspect existing code and applicable instructions before changing files. Preserve unrelated user changes.
- Keep changes focused; do not introduce unrequested frameworks, speculative systems, or repository-wide rewrites.
- For changes spanning modules, define the contracts and ownership first, then implement each side independently.
- Run the relevant available build checks and tests. Report exact checks performed, failures, and anything not run; never imply unexecuted tests passed.
- A change is complete when its behavior is verified, module boundaries remain intact, resource lifetimes are handled, and affected English documentation and tests are updated.
