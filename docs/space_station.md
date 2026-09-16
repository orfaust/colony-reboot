# Ships and Space Stations

The logic package defines `Ship`, `Space_Station`, `Station_Resource`,
`Station_Subject`, and `Station_Ship`. `Transport_State` simulates passenger round
trips requested by active housing, timed handling, platform landing, single-file
walks to housing and whole-subject station replenishment.
The station is separate from building storage and individual level subjects; its
counts are not automatically summed from or synchronized with them.

## Ships

See [Ship and Subject Presentation Metadata](ship-subject-presentation.md) for the
new fields, validation, migration and current data-only scope.

`logic.Ship` has `id`, `code`, `name`, and `type` strings, an RGB `color`, optional
`sprite` path, positive `width`/`height` in world units, plus a `subjects` array of
`Ship_Subject` entries (`subject_id`, `capacity`). IDs are unique stable
identifiers; `type` is a nonempty category identifier such as `transport`, not an
enum with hardcoded categories. `name` is a resolved localized display string.

`assets/config/ships.json` is an array. JSON uses `name_key` instead
of literal display text, in accordance with the game's localization policy:

```json
[
  {
    "id": "shuttle",
    "code": "SH",
    "color": { "r": 80, "g": 170, "b": 240 },
    "name_key": "ship_shuttle_name",
    "type": "transport",
    "sprite": "",
    "width": 1,
    "height": 1,
    "max_speed": 1200.5,
    "max_speed_hours": 1,
    "units_per_hour": 0.25,
    "subjects": [{ "subject_id": "human", "capacity": 100 }]
  }
]
```

To use this example, add `"ship_shuttle_name": "Colony Shuttle"` to
`assets/localization/en.json`. The loader resolves the key into `Ship.name`.
No translation is required for `id`, `code` or `type` identifiers. `code` is a
required nonempty display code, not a reference ID; duplicate codes are allowed.
`color` requires integer `r`, `g`, `b` channels in [0,255].

`subjects` is required; use `[]` for a ship that transports no subjects. Each entry
references a type from `assets/config/subjects.json` through `subject_id`, not
`resource_id`. References are case-sensitive (`human` and `robot`, not `humans` or
`robots`). `capacity` is a finite, nonnegative f32, consistent with station and
resident capacities. Duplicate subject IDs within a ship are rejected. These are
per-ship transport limits, not a passenger manifest. Runtime missions create a
separate homogeneous manifest for one subject type and one destination. Different
subject capacities are independent, and no shared total capacity is implied.

The current catalog defines human transport (capacity 100) and robot transport
(capacity 50). The asset manager's ship form supports adding and editing these rows.

## Space stations

`logic.Space_Station` has a unique stable `id`, a required nonempty display `code`, and a resolved `name` plus three independent arrays:

- `resources`: `{ resource_id, capacity }`
- `subjects`: `{ subject_id, capacity }`
- `ships`: `{ ship_id, units }`

Initial templates are an ordered array in `assets/config/space_stations.json`.
Each defines a localized name, resource/subject capacities and ship counts. An empty catalog
(`[]`) is valid. The former singular file is replaced by this array format.
Example of a populated configuration:

```json
[{
  "id": "space_station",
  "code": "SS",
  "name_key": "space_station_name",
  "resources": [
    { "resource_id": "water", "capacity": 500 }
  ],
  "subjects": [
    { "subject_id": "human", "capacity": 20 }
  ],
  "ships": [
    { "ship_id": "shuttle", "units": 2 }
  ]
}]
```

The example requires the `shuttle` ship definition above, plus the existing `water`
resource and `human` subject types. The station `name_key` is resolved into
`Space_Station.name`; each station requires a nonempty, unique `id`.
The asset manager uses a left-hand list and right-hand properties panel for both
ships and stations, with new, duplicate, delete and reorder controls. Lists show
codes rather than IDs alongside names; ships also show a color swatch. The ID stays
editable in the properties and remains the reference key. New entries derive their
code from the uppercase ID; new ships start with neutral RGB (200,200,200).

### One station instance per level

Every `assets/levels/*.json` requires a `space_station` object selecting one template:

```json
"space_station": {
  "station_id": "space_station",
  "distance": 35000.25,
  "resources": [{ "resource_id": "water", "units": 100, "units_per_hour": 10 }],
  "subjects": [{ "subject_id": "human", "units": 5, "units_per_hour": 0 }]
}
```

`units` and `units_per_hour` belong exclusively to this level instance and are
rejected in resource/subject template rows. Conversely, the instance cannot
redeclare `capacity`. Each resource and subject in the selected template needs
exactly one instance entry, including zero quantities. Unknown, duplicate and
missing entries fail validation. Empty lists are valid only when the template's
corresponding list is empty. Levels sharing a template have independent stock.
Ship counts remain in the template; they are not overridden by this instance.

In manage, the level form selects a template and edits quantities and signed hourly
rates. **Sync stock with template** preserves matching entries, seeds additions
with zero units/rate, and removes obsolete entries. It never silently clamps values
after capacity changes. Creating a level requires at least one station template.

### Numeric and reference rules

- `Station_Instance.distance` (`space_station.distance` in each level JSON) is the
  distance from that level's colony in **km**. It is required in the level instance
  and rejected in station templates. Levels sharing a template can have different
  distances; transport reset copies the level distance for new missions. `Ship.max_speed` is maximum speed
  in **km per simulated hour**. Both are required finite, nonnegative f32 values;
  fractional values and zero are valid. Missing fields, nulls, strings, negative
  values, and f32 overflow are rejected at startup and by the asset manager.
- Zero speed means stationary and cannot dispatch; zero distance is co-located but
  still requires loading, an available landing platform, landing and unloading.
  Distance is editable in the level station panel. Stock synchronization preserves it.
- `Ship.max_speed_hours` is required, finite and nonnegative: simulated hours to
  reach `max_speed` from rest. The same acceleration magnitude is used for braking.
  Zero explicitly selects instantaneous acceleration/deceleration.
- `Ship.units_per_hour` is required, finite and nonnegative **cargo throughput per
  simulated hour**, including subjects. Handling N units takes `N / units_per_hour`
  hours. At 2/hour, five subjects take 2.5 hours to load and another 2.5 hours to
  unload. A fractional rate is valid (0.25/hour transfers one subject every four
  hours); **zero disables dispatch**, never means instantaneous handling. Both fields
  are editable in manage. Existing numeric asset values are preserved, not silently
  converted from the prototype's former duration interpretation. New ships default
  to a one-hour ramp and 0.25 units/hour; configure throughput deliberately.

- Quantities, capacities and rates retain the f32 storage contract. Resource stock
  may be fractional; **subject `units` must be whole**, validated at startup and by
  manage's integer input. Subject rates may be fractional; usable capacity is floored.
- `units` and `capacity` must be finite and nonnegative, with `units <= capacity`.
  Zero capacity is valid only with zero current units.
- Station stock `units_per_hour` (unlike the ship field) is a finite **net rate per simulated hour**: positive for inflow,
  negative for outflow, zero for no change. Subject rates run every fixed tick;
  resource rates remain metadata. A private f64 remainder accumulates fractions until
  a whole subject can be added/removed (0.5/hour adds one every two hours). Counts
  never become fractional or negative. Saturation discards excess, including the
  remainder, rather than storing a backlog. Undelivered cargo retains capacity in the
  station, so a cancelled trip can always restore it without overflowing or losing
  passengers. Growth uses `floor(capacity) - undelivered_cargo` as its upper bound.
- Ship `units` is a nonnegative whole integer (accepted JSON range 0–2147483647).
- `resource_id` references `resources.json`, `subject_id` references a type in
  `subjects.json` (not an individual level subject), and `ship_id` references
  `ships.json`. References are case-sensitive.
- IDs may appear only once within each station array. Different arrays have separate
  ID namespaces. All fields are required; empty arrays are valid, nulls are not.
- Missing files, malformed JSON, duplicate IDs, invalid ranges, unknown fields, and
  missing references/localization text fail startup with file-specific diagnostics.

## Loading and ownership

Resources, buildings, and subjects are validated first. Ships then load before the
station so all station references can be checked. The resulting immutable initial
data lives in `config.Catalog.ships` and `config.Catalog.space_stations`. Level
stock lives separately in `config.Level.space_station` (`logic.Station_Instance`). Both files
are read before opening the window; restart to apply JSON changes, or use the
explicit [development Ctrl+R reload](development-reload.md). Successful reload
recreates station stock, subjects, fleet and landing queue from fresh configuration;
failed staging leaves the current session intact.

Decoded strings and arrays, including partial results on failure, belong to the
supplied startup allocator. Resolved display names borrow localization storage.
The application-owned arena outlives catalog use and is freed after window shutdown;
individual storage is reserved once. Each dispatch allocates one owned manifest,
freed on reset/shutdown; per-person stepping does not allocate. IDs and catalog
metadata are borrowed from startup storage.
Presentation strings use frame-temporary memory, released after drawing.

The game presentation shows only the level's selected station, combining the
localized template name, capacities and ship counts with level quantities/rates.
Templates and decoded level instances remain immutable startup data. Transport
simulation clones subject stock and ship counts into session-owned arrays. The
station panel displays live remaining stock and available ships, not initial counts.
Subject stock updates create/remove actual station instances, then individual
movement advances, then transports progress and pending requests dispatch. Newly
discharged subjects begin moving on the next fixed tick.
New whole subjects can fill pending requests that same tick. Menu pause stops
accrual; simulation speed and bounded catch-up apply. Play also resets the fractional
remainders. The station UI prints subject quantities as integers, with fractional
rates still visible. Resource stock is not advanced.

## Housing dispatch and travel

- Health and power validation happens before activation; rejected commands neither
  reserve housing nor remove station stock. Successful activation reconciles housing
  immediately. Startup-active buildings are reconciled on Play too.
- Active housing advertises `residents.capacity` minus current residents and inbound
  reservations. The initial population is the greater of `residents_amount` and the
  number of explicit level subjects assigned to the residence (not their sum).
- Requests are processed in level building order, then station ship order. A suitable
  ship has `type: "transport"`, positive `max_speed` and `units_per_hour`, an available unit, and capacity
  for the housing's `residents.type`. Boarding takes the minimum of free housing,
  station stock and ship capacity, rounded down to whole passengers. Fractional
  production is private until a whole subject accrues. Multiple ships may fill one request.
- A request atomically reserves passengers, a ship and destination seats. The ship
  remains at the station during `Loading` for `units / units_per_hour` hours. The
  manifest references individual runtime subjects; reservation is not boarding.
  Every completed `1 / units_per_hour` hours moves the next person from `Reserved`
  to `Onboard`. Only a fully boarded manifest can depart. Repeated reconciliation
  cannot double-book seats. Pending demand is retried each tick.
- Travel acceleration in km/h² is `max_speed / max_speed_hours`. Long routes reach
  the configured maximum; short routes use a triangular profile without exceeding it.
  Position and speed are analytic, not accumulated per frame. The outbound flight
  ends at rest at `max(0, distance - 1)` km from the station. The final <=1 km is the
  landing procedure rather than another cruise leg.
- Advance once per fixed clock tick after building transitions. Menu time pauses
  travel; all speed multipliers and the existing bounded catch-up policy apply.
- At <=1 km the ship waits for an **active `landing_platform`**, chosen in level
  order. Missing, inactive or occupied platforms cause a hold without unloading;
  the UI reports a pending ETA. Logic assigns a monotonic FIFO ticket on entering
  `Waiting_Landing`; entries processed in the same fixed tick use mission order as
  the tie-break. New arrivals cannot overtake older ships eligible for a free pad.
  A pickup tied to an inactive pad does not block traffic to other available pads. Clearance is retried
  every fixed tick, including after takeoff frees a pad; a release processed later
  than a waiting ship is observed on its next tick. Cancellation removes the ship
  from contention immediately. The queue uses the existing bounded mission storage
  (128 entries), allocates nothing, and resets on Play. Descent, unloading and takeoff reserve the
  platform exclusively. A platform disabled after descent begins retains this
  reservation until the procedure finishes, avoiding mid-air relocation.
- `Landing` takes one simulated hour (`LANDING_HOURS`), including approach clearance.
  A 32×32 screen-pixel ship enters from the top of the current viewport (rectangle
  Y=-32, bottom edge at Y=0) and descends to the projected platform center with
  smoothstep easing. Takeoff traverses the same full path backwards until the ship
  exits above the viewport; cancelled descent reverses from its current progress
  without a position jump. The platform center is reprojected every frame using the
  current camera/zoom and viewport dimensions, never cached in simulation. Offscreen
  platforms are not clamped or relocated; GPU clipping handles their presentation.
  Waiting ships retain separate visible holding slots 96 screen pixels above the
  platform (clamped to the viewport), independent of the transit endpoints. On
  clearance they start the viewport-edge descent; holding is not a shortened landing
  trajectory. Their cargo and FIFO tickets remain unchanged. Logic supplies
  `holding_platform_id`, a borrowed stable visual anchor (first active platform,
  otherwise first configured platform), distinct from the exclusive `platform_id`
  reservation. With no platform configured there is no world anchor; the waiting
  card remains visible. Slot layout, camera projection and resizing never grant
  landing clearance. Menu pause and time scaling apply to the animation;
  high speed can skip visible intermediate poses. It is not tied to frame count.
- On touchdown, unloading transfers the same individuals at `units_per_hour`, one
  whole person per completed service interval. The ship cannot take off until its
  manifest is empty. Each discharge releases one reservation and increases assigned
  `residents_amount` by one; walking into housing does not count that person again.
  Each subject has independent movement state, position, speed and destination (see
  below). The renderer displays their actual positions, not synthetic cohort markers.
- Successful unloading initiates takeoff (one simulated hour), keeping the platform
  reserved until departure, then the normal accelerated/braked return flight. The
  empty ship becomes available immediately on reaching the station and is marked
  `Completed`; it needs no cargo-unloading delay. Pending requests may reuse it that
  tick. Returned cargo on cancelled trips still requires unloading. Resource transport
  remains out of scope.

### Request withdrawal and cargo return

Every successful toggle reconciles requests immediately, before another tick.
Disabling a requesting residence removes exactly its outstanding, undelivered
reservation, once. Each mission currently serves one residence, so its requested
quantity becomes zero; other residences' requests are untouched. Delivered subjects
remain assigned residents until actual evacuation boarding, described below.
Reactivation never redirects an ordinary returning ship; new immigration demand
waits while a committed evacuation still has residents to board.

- During loading: cancel departure, immediately release unboarded individuals back
  to available stock, and unload only people already aboard at the configured rate.
  The ship becomes available after its last passenger exits.
- During outbound flight: brake with the configured acceleration (retaining position
  and velocity continuity), then start an accelerated/decelerated return leg from the
  stopping point. Waiting ships return directly from the approach point.
- During landing/unloading: stop further deliveries, reverse the vertical animation
  into takeoff, release the platform, then return from the approach point.
- At the station: `Return_Unloading` takes `remaining_cargo / units_per_hour` hours.
  Restore each undelivered individual's availability progressively, exactly once,
  preserving identity. After the final passenger exits, release the ship and mark
  `Cancelled`.
  Partial unload conserves passengers: station stock + aboard + delivered is unchanged.
  Returned ships are eligible for pending requests, subject to the session log limit.

Each mission advances at most 16 phase transitions per fixed tick; unused tick time
carries across boundaries, including zero-hour phases. Waiting for a platform does
not consume a fictitious ETA. Runtime arrays own mutations; snapshot procedures
return values with borrowed stable IDs. Rendering cannot change requests or deliver
passengers.
- A session retains at most **128 missions**, including arrivals. At the limit new
  demand stays pending: no ship or passengers are lost. Play resets missions, housing,
  ship counts and stock to the level's initial state. Mission index is stable within
  a session; all cross-object references use stable string IDs.

## Residence evacuation

A successful active-to-inactive transition records an evacuation request immediately
through `reconcile_transports`, independently of inbound-trip cancellation. Rejected
commands do not create requests. Initial inactive residences are not automatically
evacuated: the trigger is a deactivation command. Requests are bounded per building,
and repeated reconciliation cannot reserve a person twice.

- **During cooldown:** current residents may remain at home; no pickup is dispatched
  yet. Existing movement can finish normally. Full consumption and brightness last
  until zero as before. Reactivation before zero cancels the pending evacuation,
  retaining residents and their existing movement state.
- **At zero:** evacuation commits. Each resident receives a logic-owned walk order
  to the first active landing platform, in level order. People depart with spacing
  from their actual positions and keep their individual IDs, roles and speed. With
  no active platform, they remain safely in place until one becomes available. A
  chosen platform remains their target if later disabled; without existing ship
  clearance it must be reactivated, rather than teleporting walkers or silently
  redirecting them. Already reserved landing/service procedures may finish, as for
  ordinary transports. Movement commands
  cannot override evacuation ownership.
- **No ship yet:** people can reach and wait inside the platform while still counted
  as assigned residents of their old home. Missing/speed-zero/throughput-zero ships,
  unsupported subject types, full station capacity and the 128-mission log limit
  leave the request pending. Nobody is deleted, converted to stock or marked aboard.
- **Pickup dispatch:** once committed, requests have priority over new immigration
  without preempting assigned missions. Available ships fly empty; there is no fake
  station loading or stock withdrawal. Each homogeneous manifest reserves distinct
  individuals, ship seats and station capacity. Flights and the landing FIFO are
  shared with ordinary transports, using the walkers' required platform. The pad
  stays exclusive through landing, boarding and takeoff.
- **Boarding:** the existing service phase (`Unloading` internally) means loading
  for an evacuation and is shown using the localized loading status. The next
  manifest person must physically arrive before their service interval can accrue.
  One whole person boards per `1 / ship.units_per_hour` hours; only then does the
  residence count decrease and the person's residence/occupation assignment clear.
  The ship waits for every manifest member and never banks handling credit while
  waiting for walkers. The box shows only actual onboard people and unknown ETA
  before pickup completes. `Transport.arrived` means colony service completed: for
  a pickup, fully boarded, not yet back at station.
- **Return:** unchanged top-of-viewport takeoff and return profiles apply. At base,
  subjects unload individually at throughput into available stock with the same
  IDs, exactly once. Station capacity remains reserved until each person unloads,
  so replenishment cannot fill their reserved places. The ship is reusable only
  after the last person exits. The mission card still hides at base as before.
- **Reactivation after zero:** committed evacuation continues, including people
  waiting for ships or station room. New immigration to that residence is suppressed
  until all outgoing people board; normal active-housing demand can then resume.
  This policy avoids reversing loaded manifests or simultaneously replacing people
  who still occupy the residence's assignment slots.

`Transport_State` owns request/commit flags and observed activity per building;
`Runtime_Subject` owns evacuation movement/manifest flags and a borrowed stable pad
ID. A manifest contains owned internal subject-slot indices; public identities stay
stable. `residents_amount` remains assigned occupancy, not a sensor of physical
presence. Walking and waiting never subtract residents a second time. Completed
mission history retains no control over returned people subsequently reused by
another trip. Play resets flags, people, clock and queues; successful development
reload constructs them afresh, while failed reload preserves the old evacuation.
There are no evacuation-specific GPU resources. Request/movement/boarding stepping
does not allocate; each dispatch allocates its manifest, freed on reset/shutdown.

Headless regressions cover cooldown cancellation and exact completion, waiting
without ships, missing/occupied platforms, full station/ship capacities, mixed FIFO
traffic, progressive boarding, replenishment reservation, repeated requests,
post-commit reactivation, mission limit, identity/count conservation and reset/reload.
Manual scenario (not yet performed): deactivate occupied housing, watch the bar
reach zero, follow individual walkers to the platform, observe pickup loading and
station unloading, and compare population before/after. Repeat with no free ship,
a busy pad and a full station; then provide the missing capacity and verify resumption.

## Individual subjects and colony commands

`Transport_State.subjects` owns `Runtime_Subject` instances: unique session `Subject_ID`,
optional original level `source_id`, type ID, roles, residence, occupation, current
activity, world position, target, speed and individual queue timer. Initial level
subjects preserve their configured identity metadata and speed. Any additional
`residents_amount` occupants and initial station stock are also materialized as
individuals. Initial stock and resident amounts must be whole; counts are caches for
housing/stock views, not substitutes for people. Positive station rates create people;
negative rates remove only available station people, never reserved/in-flight ones.

Activities are `Station`, `Reserved`, `Onboard`, `Waiting`, `Moving`, `Inside`, and
`Removed`. Delivery issues an individual home movement order. Equal-speed people
leave the platform in single file, with 0.25 world units of departure spacing, at
`2 * speed` world units/hour. They follow a straight route and become `Inside` at the
target; they are retained in the simulation, not deleted when their marker disappears.
Movement continues independently of their former transport's lifecycle. Screen
markers remain 9×16 pixels; all moving subjects are eligible for drawing, with viewport
culling rather than a per-mission population cap.

`subject_snapshot(state, id)` returns an independent value (role slices/strings remain
borrowed read-only). `move_subject(state, game, Move_Subject{id, destination})` validates
both IDs and the subject's availability, then updates only that individual's target.
It returns `Applied`, `Unknown_Subject`, `Unknown_Destination`, or `Unavailable`.
Transport-owned subjects cannot be redirected before discharge. Commands are applied
synchronously, in caller order; no hidden callbacks or queues. Residence remains the
housing assignment when a separate movement destination changes. Autonomous work,
needs/rest cycles, collision avoidance and pathfinding are not implemented by this
change; the current automatic colony request is housing delivery.

Storage is bounded to 16,384 live subject slots. Startup overflows fail validation
in Odin and manage. Replenishment pauses at the limit without creating phantom stock;
removed slots may be reused with new IDs. Play resets individuals and their IDs
alongside the level. Mission manifests use internal stable slots; only subject IDs
cross the public command boundary.

## Transport panel and smoke test

Departures appear in a left-hand scrollable panel below the clock. Each card contains
an opaque **24×24 screen-pixel** ship square in its bottom icon strip, its localized name, full cargo count and
destination ID, remaining km, current/maximum speed in km/h, ETA and status.
Distance, speed, cargo destination, and ETA/status occupy separate logical lines.
Cards are at least 176 pixels high and grow to fit actual wrapping at the shared
24-pixel font size. Text is never reduced to fit. Remaining distance
is clamped to zero at arrival. The `transport_trip_format` localization template
requires `{remaining}`; `transport_speed_format` requires `{speed}` and
`{max_speed}`. Known ETA uses `transport_hours_format` (`{value}`); unknown ETA
uses its localized status without an hours suffix. Distance, current/maximum speed
and known ETA hours are rounded to whole numbers for display, with no decimal
places or scientific notation. Values below half a unit display zero; simulation
values keep their full precision. The maximum is the ship's configured limit, not the route's peak speed. Subject placeholders are
**9×16 screen-pixel** colored rectangles using the subject type color. Visible icons
are capped to card space (up to 20); text reports the actual full onboard count:
`loaded - delivered - returned`. It starts at zero, rises while boarding and falls
while unloading. Reserved people not yet boarded do not appear as onboard cargo.
Wheel over the panel scrolls measured card content by pixels, including within tall
cards, rather than zooming the world; clicks do not
activate buildings underneath. Each active mission has its own card, including
empty return flights and cancelled trips returning cargo. Cards disappear on reaching
the station (before return unloading); finished history does not occupy panel slots.
Scrolling and overlay bounds use only visible missions, and clamp when cards disappear.

Presentation regression smoke (verified with the real raylib backend):

```sh
odin run tools/landing_smoke -out:build/landing-smoke.exe
```

It renders `build/viewport-travel-smoke.png`: six panels show partial top-edge
entry, mid-descent, touchdown, mid-takeoff, partial top-edge exit, and independent
holding. The contact sheet was visually inspected. Headless app tests also cover
multiple viewport sizes, pan/zoom, reversed/cancelled paths and unchanged FIFO data.
This does not replace a full interactive gameplay smoke test.

Manual gameplay smoke test (not yet performed):

1. Configure `max_speed: 3600`, `max_speed_hours: 1`, `units_per_hour: 20`, level
   `space_station.distance: 3601`, positive matching subject stock and an active
   landing platform. Alternatively start with zero stock and positive subject
   `units_per_hour`; whole subjects accrue during play. Restart and use clock speed 1×.
2. Activate healthy powered housing for a five-person manifest: Loading lasts
   0.25 h at 20 units/hour, outbound flight lasts 2 h, descent starts at 1 km and
   lasts 1 h, then unloading lasts 0.25 h. Check onboard counts rise/fall individually.
   Verify descending ship, passenger exit, resident counts and remaining stock.
   Watch the file enter its assigned home while the ship takes off, returns and
   becomes available. At 0.5 subjects/hour, verify one new subject every two hours,
   saturation without fractional counts, menu pause and remainder reset on Play.
3. Disable housing while loading, cruising, descending and midway through unloading.
   Verify cancellation, braking/takeoff as applicable, return, station unloading and
   restoration of only undelivered cargo. Repeated toggles must never duplicate stock.
4. Disable/remove the landing platform before approach: ships wait; enabling a
   platform admits one ship at a time. Send at least three transports to one pad:
   verify visible hovering while it is occupied through unloading and takeoff, FIFO
   resumption without cargo loss, and cancellation of a waiter without blocking
   followers. Confirm a damaged residence produces only the
   existing health warning and no request.
5. Test menu pause, speed scaling, resize/pan/zoom, overlay consumption, scrolling,
   partial discharge and Play reset. Check the landing anchor follows the platform.
