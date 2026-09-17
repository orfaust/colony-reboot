package logic

import "core:math"
import "core:mem"
import c "../contracts"

// Text fields are localization keys, not display strings. Definition slices are
// borrowed immutable catalog storage and must outlive any simulation using them.
Resource :: struct {
    id: string,
    name_key, description_key, unit_type_key: string,
    color: c.RGB,
}
// JSON specifies exactly one amount (config "one_of" group). Per-capita consumption
// is modelled only by subject needs; the obsolete building `amount_per_resident`
// rate was removed in the building production plan.
Need :: struct {
    resource_id: string,
    amount_per_unit: f32 `config:"one_of"`, // Resource units consumed per unit of product.
    amount_per_hour: f32 `config:"one_of"`, // Resource units consumed per hour of operation.
    capacity: f32, // Units of this resource the building can hold.
}
// JSON specifies exactly one rate (config "one_of" group): `units_per_hour`.
Product :: struct {
    resource_id: string,
    units_per_hour: f32 `config:"one_of"`, // Resource units produced per hour.
    capacity: f32, // Units the producing building can hold.
}
// Subjects hold no stock: their products have no capacity or stored amount.
Subject_Product :: struct {
    resource_id: string,
    units_per_hour: f32, // Resource units produced per hour.
}
// A resource a building type can hold beyond its needs and products.
Storage :: struct {
    resource_id: string,
    capacity: f32, // Units of this resource the building can hold.
}
Stored_Resource :: struct {
    resource_id: string,
    amount: f32, // Units held by this instance, in [0, capacity] of the matching need or product.
}
// Subjects a building hosts: a subjects.json type ID and how many of them. JSON null decodes
// as the zero value, so an empty `type` means the building hosts no one (see hosts_residents).
Residents :: struct {
    type: string,
    capacity: f32,
}
// Staffing intent for a building role entry. `continuous` keeps every slot covered
// while the building is enabled; `on_demand` waits for a future explicit request.
Staffing_Mode :: enum {
    continuous,
    on_demand,
}
Building_Subject_Role :: struct {
    role_id: Subject_Role,
    quantity: int, // Nonnegative number of individual slots (integer, never fractional).
    staffing_mode: Staffing_Mode, // Replaces the former `required` boolean.
}
Building_Type :: struct {
    id: c.Building_Type_ID,
    name_key, description_key: string,
    sprite: string `config:"optional"`, // Borrowed PNG path; absent/empty uses color, never a GPU resource.
    code: string,
    width, height: f32, // Pixel dimensions at 100% zoom; position identifies the center.
    color: c.RGB,
    power_need_kw, power_output_kw: f32,
    always_on: bool, // Must never be switched off; validated level instances start enabled.
    warmup_time: f32, // Hours from activation until production starts.
    cooldown_time: f32, // Hours from deactivation until the initial state is restored.
    min_operative_health: f32, // Minimum instance health, in [0,1], required to activate.
    materials_amount: f32, // Material units needed to build and to repair.
    subject_roles: []Building_Subject_Role, // Borrowed staffing metadata; not an activation gate.
    residents: Residents `config:"nullable"`, // JSON null: the building hosts no subjects.
    needs: []Need,
    produces: []Product,
    storage: []Storage, // Level instances keep a stored entry for each of these resources too.
}
Building_Instance :: struct {
    id: string,
    building_id: c.Building_Type_ID,
    position: c.Vector2,
    health: f32,
    repairing: bool,
    enable_at_start: bool, // Active when a session starts; Control Units always are.
    stored: []Stored_Resource, // Borrowed immutable level metadata; seeds and restores the runtime stock table.
    residents_amount: Maybe(f32), // Residents living here: set only when the type has residents (JSON null otherwise).
}

// A continuous entry with at least one slot backs a staffing slot that startup
// validation may reference through an initial assignment. Zero-quantity entries
// and on-demand entries have no automatic slot yet.
has_continuous_slot :: proc(definition: Building_Type, role_id: Subject_Role) -> bool {
    return continuous_role_quantity(definition,role_id) > 0
}

valid_instance :: proc(instance: Building_Instance) -> bool {
    return instance.id != "" && instance.building_id != "" &&
        !math.is_nan(instance.health) && instance.health >= 0 && instance.health <= 1 &&
        !math.is_nan(instance.position.x) && !math.is_inf(instance.position.x) &&
        !math.is_nan(instance.position.y) && !math.is_inf(instance.position.y)
}

// A validated non-null residents object always has a nonempty subject type.
hosts_residents :: proc(definition: Building_Type) -> bool {
    return definition.residents.type != ""
}

// Control Units are always active; other buildings start active only when the level asks.
starts_active :: proc(instance: Building_Instance) -> bool {
    return instance.building_id == c.CONTROL_UNIT_ID || instance.enable_at_start
}

// The caller owns array storage; strings borrow the immutable startup catalog.
// Initial activity comes from the level (see starts_active); afterwards it is runtime state.
State :: struct {
    buildings: []Building_Instance,
    active: []bool,
    always_on: []bool, // Immutable per-instance shutdown policy copied from the catalog.
    power: []Power,
    min_operative_health: []f32,
    timing: []Timing,
    // Per-instance startup progress in [0,1]; it scales power output only. It moves
    // toward `active` on each tick, over warmup_hours up and cooldown_hours down.
    // Consumption does not ramp: active or still-cooling buildings draw full need.
    level: []f64,
    // Materialized continuous staffing slots and their derived coverage. Slots are
    // rebuilt from the same level template on reset; claims are cleared by reset
    // and rebuilt by derive_staffing from the authoritative subject state.
    staffing: Staffing,
    // Owned per-instance runtime stock, flat like the staffing table: `stock_first`
    // is a len(buildings)+1 prefix index into `stock`, which holds the resolved
    // resource entries in level order, then configured need/product/storage order.
    // Allocated by new_session, restored by reset without allocating and freed by
    // destroy; amounts are seeded from the immutable level `stored` template.
    stock_first: []int,
    stock: []Stock_Entry,
    // Borrowed immutable recipe metadata per instance, resolved once at session
    // creation (see production.odin). `produces[0]` is the reference product for
    // every `amount_per_unit` need; the slices must outlive the session.
    recipes: []Recipe,
    // Edge-triggered accounting for the hourly production step: true while the
    // building is operational but skipping hours for a missing input. Restored to
    // false by reset and freed by destroy; no allocation after construction.
    production_blocked: []bool,
    // Shift scheduler bookkeeping: rotating cursors and deferral accounting.
    scheduler: Scheduler,
    clock: Clock,
    // Edge-triggered transition log for the application. Fixed capacity and
    // allocation-free; see events.odin for delivery order and overflow behavior.
    events: Event_Queue,
}
Power :: struct { output_kw, need_kw: f64 }
Timing :: struct { warmup_hours, cooldown_hours: f64 }

// Only validated startup configuration may be supplied here. No per-command allocation.
new_session :: proc(initial: []Building_Instance, definitions: []Building_Type, allocator: mem.Allocator) -> State {
    state := State{
        buildings = make([]Building_Instance, len(initial), allocator),
        active = make([]bool, len(initial), allocator),
        always_on = make([]bool, len(initial), allocator),
        power = make([]Power, len(initial), allocator),
        min_operative_health = make([]f32, len(initial), allocator),
        timing = make([]Timing, len(initial), allocator),
        level = make([]f64, len(initial), allocator),
    }
    for building, i in initial {
        assert(valid_instance(building))
        found := false
        for definition in definitions {
            if definition.id == building.building_id {
                // Startup validation guarantees these two invariants; a fixture that
                // breaks them would silently change toggle and load-shedding behavior.
                assert(definition.power_need_kw == 0 || definition.power_output_kw == 0)
                assert(!definition.always_on || definition.power_need_kw == 0)
                state.power[i] = {f64(definition.power_output_kw), f64(definition.power_need_kw)}
                state.always_on[i] = definition.always_on
                state.min_operative_health[i] = definition.min_operative_health
                state.timing[i] = {f64(definition.warmup_time), f64(definition.cooldown_time)}
                found = true
                break
            }
        }
        assert(found) // Startup validation resolves every level building_id.
    }
    assert(continuous_slot_count(initial,definitions) <= STAFFING_SLOT_LIMIT) // Config rejects larger levels.
    assert(stock_entry_count(initial,definitions) <= STOCK_ENTRY_LIMIT) // Config rejects larger levels.
    materialize_staffing(&state.staffing,initial,definitions,allocator)
    materialize_stock(&state,initial,definitions,allocator)
    materialize_recipes(&state,initial,definitions,allocator)
    reset(&state, initial)
    // Config rejects an invalid initial network; coverage is derived from the level's
    // initial assignments after construction, so this assertion checks the configured
    // quantities before the runtime staffing gate can apply.
    assert(power_balance(&state,false).available_kw >= 0)
    return state
}

// Use with individually freeable allocators; an arena owner may instead free its arena.
destroy :: proc(state: ^State, allocator: mem.Allocator) {
    delete(state.buildings, allocator)
    delete(state.active, allocator)
    delete(state.always_on, allocator)
    delete(state.power, allocator)
    delete(state.min_operative_health, allocator)
    delete(state.timing, allocator)
    delete(state.level, allocator)
    destroy_staffing(&state.staffing,allocator)
    destroy_stock(state,allocator)
    destroy_recipes(state,allocator)
    state^ = {}
}

// Reset from the same level without allocating or modifying the level template.
reset :: proc(state: ^State, initial: []Building_Instance) {
    assert(len(state.buildings) == len(initial))
    copy(state.buildings, initial)
    // Buildings active at start are already fully running; there is no initial warmup.
    for building, i in initial {
        state.active[i] = starts_active(building)
        state.level[i] = state.active[i] ? 1 : 0
    }
    // Runtime stock is restored from the copied level template without allocating.
    reset_stock(state)
    for &blocked in state.production_blocked { blocked = false }
    state.clock = {}
    state.events = {}
    clear_staffing_claims(&state.staffing)
    state.scheduler = {}
}

// Advances every warmup/cooldown by one clock tick. Call once per tick from
// advance_clock, never per frame. Ramps are linear and may reverse mid-way.
step :: proc(state: ^State) {
    for &level, i in state.level {
        timing := state.timing[i]
        if state.active[i] && level < 1 {
            level = ramp_toward(level, 1, timing.warmup_hours)
        } else if !state.active[i] && level > 0 {
            level = ramp_toward(level, 0, timing.cooldown_hours)
        }
    }
}

@(private)
ramp_toward :: proc(level, target, hours: f64) -> f64 {
    if hours <= 0 { return target }
    delta := 1 / (hours * TICKS_PER_HOUR)
    // Snap float residue so a ramp of N hours completes in exactly N*TICKS_PER_HOUR ticks.
    if abs(target-level) <= delta*(1+1e-9) { return target }
    return target > level ? level+delta : level-delta
}

// Returned values cannot mutate authoritative state. IDs borrow configuration storage.
// Output is ramped and gated by staffing: an enabled building whose continuous slots
// are not fully covered produces nothing. Energized means active or not yet fully
// cooled; it controls full electrical demand and presentation, not command/request
// eligibility, and it is never gated by staffing.
energized :: proc(state: ^State, index: int) -> bool {
    return state.active[index] || state.level[index] > 0
}

snapshot :: proc(state: ^State, index: int) -> c.Building_Snapshot {
    b := state.buildings[index]
    power := state.power[index]
    level := state.level[index]
    active := state.active[index]
    is_energized := energized(state,index)
    return {id=b.id, building_id=b.building_id, position=b.position, health=b.health, repairing=b.repairing,
        active=active, staffed=building_staffed(state,index), energized=is_energized, level=level,
        power_output_kw=building_output_gated(state,index) ? 0 : power.output_kw*level,
        power_need_kw=is_energized ? power.need_kw : 0}
}

// Instantaneous kW balance with ramped output, not stored energy in kWh. An enabled
// building whose continuous staffing is not fully covered produces nothing while it
// keeps consuming its full demand. Staffing loss can therefore make the balance
// negative; `step_load_shedding` resolves it in the same tick by force-stopping the
// greatest active consumer, unless no eligible building remains. Disabled buildings
// still cooling are not affected by the gate and are never shed candidates.
balance :: proc(state: ^State) -> c.Power_Balance {
    return power_balance(state,true)
}

// The same summation without the staffing gate: the configured network that startup
// validation checks before any coverage has been derived.
@(private)
power_balance :: proc(state: ^State, apply_staffing: bool) -> c.Power_Balance {
    result: c.Power_Balance
    for power, i in state.power {
        if !apply_staffing || !building_output_gated(state,i) { result.produced_kw += power.output_kw*state.level[i] }
        if energized(state,i) { result.consumed_kw += power.need_kw }
    }
    result.available_kw = result.produced_kw - result.consumed_kw
    if result.available_kw < 0 && !power_shortage(result.produced_kw, result.consumed_kw) { result.available_kw = 0 }
    return result
}

// Startup eligibility shares the same starts_active rule as reset. Building ID references
// must already be validated; no session allocation is needed to check the level.
initial_balance :: proc(initial: []Building_Instance, definitions: []Building_Type) -> f64 {
    produced, consumed: f64
    for building in initial {
        if !starts_active(building) { continue }
        for definition in definitions {
            if definition.id == building.building_id {
                produced += f64(definition.power_output_kw)
                consumed += f64(definition.power_need_kw)
                break
            }
        }
    }
    if !power_shortage(produced, consumed) { return max(f64(0), produced-consumed) }
    return produced - consumed
}

// Catalog powers are f32; tolerate only relative input-rounding error, not a
// fixed free-power allowance. A positive demand with zero output still fails.
power_shortage :: proc(produced, consumed: f64) -> bool {
    return consumed-produced > max(produced,consumed)*1e-7
}

// Commands are delivered synchronously in input order. Rejections leave all state
// unchanged. Power attributes are mutually exclusive at startup, so a building is
// either a producer or a consumer and no consumer can start from its own output.
// Active producers cannot be shut down, even
// during warmup or when damaged. Health gates activation only for other buildings.
// Output ramps are reserved pessimistically so an accepted command never creates a
// deficit: a warming building offers only its current output (it only rises while
// active), a cooling building offers nothing, and a building that is (or becomes)
// enabled without full coverage offers nothing because staffing does not change on
// a toggle. Need stays reserved in full until level zero.
toggle :: proc(state: ^State, command: c.Toggle_Building) -> c.Toggle_Result {
    index := -1
    for building, i in state.buildings {
        if building.id == command.id { index = i; break }
    }
    if index < 0 { return .Unknown_Building }
    if state.buildings[index].building_id == c.CONTROL_UNIT_ID { return .Control_Unit_Locked }
    if state.active[index] && state.always_on[index] { return .Always_On_Locked }
    if state.active[index] && state.power[index].output_kw > 0 { return .Generator_Required }
    if !state.active[index] && state.buildings[index].health < state.min_operative_health[index] {
        return .Insufficient_Health
    }
    produced, consumed: f64
    for power, i in state.power {
        enabled := state.active[i]
        if i == index { enabled = !enabled }
        if enabled {
            output := power.output_kw * (state.timing[i].warmup_hours <= 0 ? 1 : state.level[i])
            // The staffing gate follows the post-command enabled state: a building
            // that remains (or becomes) enabled while not fully covered offers no
            // output, so a command can never start a network on missing personnel.
            if !building_staffed(state,i) { output = 0 }
            produced += output
        }
        // Evaluate post-command demand, including every pending shutdown. Only a
        // zero-duration shutdown releases its remaining demand immediately.
        level := state.level[i]
        if i == index && !enabled && state.timing[i].cooldown_hours <= 0 { level = 0 }
        if enabled || level > 0 { consumed += power.need_kw }
    }
    if power_shortage(produced, consumed) {
        return .Insufficient_Power
    }
    state.active[index] = !state.active[index]
    // Zero-length transitions complete immediately rather than on the next tick.
    timing := state.timing[index]
    if state.active[index] && timing.warmup_hours <= 0 { state.level[index] = 1 }
    if !state.active[index] && timing.cooldown_hours <= 0 { state.level[index] = 0 }
    return .Applied
}
