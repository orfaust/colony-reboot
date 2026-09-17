package logic

import "core:mem"
import c "../contracts"

// Hourly building production, consumption and automatic load shedding.
//
// Recipe semantics
// ----------------
// A building either runs its whole hourly recipe or does nothing; there is no
// partial consumption and no scaled rate. The step is scheduled once per whole
// simulated hour, so the result is independent of the clock speed and the frame
// pacing. Every product yields
// `units_per_hour`; every need consumes `amount_per_hour`, or `amount_per_unit`
// scaled by the reference product, which is the first entry of `produces`.
// Per-capita consumption is modelled by subject needs, not by a building rate.
//
// All-or-nothing execution
// ------------------------
// The recipe runs only when every input is available (`stock >= consumed`) and
// every output fits after the inputs are applied
// (`stock - consumed + produced <= capacity`). If either condition fails the whole
// hour is skipped: nothing is consumed and nothing is produced. Amounts are
// fractional and accumulate; they are never rounded.
//
// Gating
// ------
// `operational = active && level >= 1 && building_staffed`. During warmup or
// cooldown (`level < 1`), while the requested activity is off, or while a
// continuous slot is uncovered, no material is produced or consumed. Electrical
// output keeps ramping with `level` independently.
//
// Allocation
// ----------
// The recipe metadata borrows catalog storage materialized once per session; the
// hourly step allocates nothing and never loads assets.
//
// Load shedding
// -------------
// A negative instantaneous balance is resolved by force-stopping the active
// consumer with the greatest configured `power_need_kw` (lowest level index on a
// tie), cascading until the balance is nonnegative or no candidate remains. Each
// shed building is stopped in the same tick (`active = false`, `level = 0`), does
// not enter cooldown and stays off until the player re-enables it. Generators and
// the existing shutdown locks (Control Unit, `always_on`) are never overridden.

// Borrowed immutable recipe metadata of one building instance, in configured order.
// `produces[0]` is the reference product for every `amount_per_unit` need. The
// slices borrow catalog storage, which must outlive the session; nothing is copied
// per tick.
Recipe :: struct {
    needs: []Need,
    produces: []Product,
}

// Relative tolerance for `stock >= consumed` and the capacity bound: the amounts
// are f64 accumulations of f32 catalog values, so an exact equality can carry a
// few ulps of residue. This is not extra stock; a real shortfall is not forgiven.
@(private)
stock_tolerance :: proc(a, b: f64) -> f64 {
    return max(1, max(abs(a), abs(b))) * 1e-9
}

@(private)
stock_covers :: proc(amount, required: f64) -> bool {
    return required <= amount + stock_tolerance(amount, required)
}

@(private)
stock_fits :: proc(amount, consumed, produced, capacity: f64) -> bool {
    value := amount - consumed + produced
    return value <= capacity + stock_tolerance(value, capacity)
}

// Resolves the borrowed recipe metadata of every level instance. Called once by
// new_session; unknown definitions contribute an empty recipe because startup
// validation resolves every level `building_id`.
@(private)
materialize_recipes :: proc(state: ^State, initial: []Building_Instance, definitions: []Building_Type, allocator: mem.Allocator) {
    state.recipes = make([]Recipe, len(initial), allocator)
    state.production_blocked = make([]bool, len(initial), allocator)
    for building, i in initial {
        for definition in definitions {
            if definition.id != building.building_id { continue }
            state.recipes[i] = {needs=definition.needs, produces=definition.produces}
            break
        }
    }
}

@(private)
destroy_recipes :: proc(state: ^State, allocator: mem.Allocator) {
    delete(state.recipes, allocator)
    delete(state.production_blocked, allocator)
    state.recipes = nil
    state.production_blocked = nil
}

// Units of the reference product per hour: the first `produces` entry. Zero when
// the type produces nothing, so its per-unit needs resolve to zero flow; startup
// validation rejects that combination for a building that lists one.
recipe_reference_rate :: proc(recipe: Recipe) -> f64 {
    if len(recipe.produces) == 0 { return 0 }
    return f64(recipe.produces[0].units_per_hour)
}

// Hourly consumption one need demands: the configured hourly amount, or the
// per-unit amount scaled by the reference product's hourly rate.
need_per_hour :: proc(need: Need, reference_rate: f64) -> f64 {
    if need.amount_per_hour > 0 { return f64(need.amount_per_hour) }
    if need.amount_per_unit > 0 { return f64(need.amount_per_unit)*reference_rate }
    return 0
}

// Hourly production one product yields.
product_per_hour :: proc(product: Product) -> f64 {
    return f64(product.units_per_hour)
}

// Hourly flow of one resource of one recipe. Needs and products that share a
// resource are aggregated in configured order, so a store that is both consumed
// and produced is checked once, after both sides are applied.
recipe_flow :: proc(recipe: Recipe, resource_id: string) -> (consumed, produced: f64) {
    reference := recipe_reference_rate(recipe)
    for need in recipe.needs {
        if need.resource_id == resource_id { consumed += need_per_hour(need, reference) }
    }
    for product in recipe.produces {
        if product.resource_id == resource_id { produced += product_per_hour(product) }
    }
    return
}

// True when the building is allowed to run its recipe: the player requested
// activity, warmup reached its end and every continuous slot is physically
// covered. `on_demand` entries never gate.
production_operational :: proc(state: ^State, index: int) -> bool {
    return state.active[index] && state.level[index] >= 1 && building_staffed(state,index)
}

// Evaluates one recipe against the authoritative stock without mutating it.
// `fits` is false when the whole hour must be skipped; `reason` then carries the
// blocking condition, with a missing input taking precedence over a full output
// store. Also reports whether the building has anything to simulate at all.
recipe_fits :: proc(state: ^State, index: int, recipe: Recipe) -> (fits: bool, reason: c.Production_Block, relevant: bool) {
    relevant = len(recipe.needs) > 0 || len(recipe.produces) > 0
    if !relevant { return true, .None, false }
    reason = .None
    for j in state.stock_first[index]..<state.stock_first[index+1] {
        entry := state.stock[j]
        consumed, produced := recipe_flow(recipe,entry.resource_id)
        if consumed == 0 && produced == 0 { continue }
        if consumed > 0 && !stock_covers(entry.amount,consumed) {
            return false, .Missing_Input, true
        }
        if produced > 0 && !stock_fits(entry.amount,consumed,produced,entry.capacity) {
            reason = .Output_Full
        }
    }
    return reason == .None, reason, true
}

// Applies one hour of the recipe: every resolved store receives
// `amount - consumed + produced`, clamped to [0, capacity]. Clamping is float
// hygiene only; recipe_fits already guaranteed the bound.
@(private)
apply_recipe :: proc(state: ^State, index: int, recipe: Recipe) {
    for j in state.stock_first[index]..<state.stock_first[index+1] {
        entry := &state.stock[j]
        consumed, produced := recipe_flow(recipe,entry.resource_id)
        if consumed == 0 && produced == 0 { continue }
        entry.amount = clamp(entry.amount-consumed+produced,0,entry.capacity)
    }
}

// Live blocking reason for one building, evaluated without mutating anything and
// usable on any tick. Order is the presentation precedence.
production_status :: proc(state: ^State, index: int) -> c.Production_Block {
    assert(index >= 0 && index < len(state.recipes))
    if !state.active[index] { return .Inactive }
    if state.level[index] < 1 { return .Warming_Up }
    if !building_staffed(state,index) { return .Unstaffed }
    _, reason, relevant := recipe_fits(state,index,state.recipes[index])
    if !relevant { return .None }
    return reason
}

// Resolved hourly consumption and production of every resource the building holds,
// written into caller storage in stock order (level order, then configured
// need/product/storage order). Returns the number of entries written; the slice is
// authoritative caller storage, so an undersized slice truncates only presentation
// and reports the count instead of allocating.
production_rates :: proc(state: ^State, index: int, out: []c.Production_Rate) -> int {
    assert(index >= 0 && index < len(state.recipes))
    written := 0
    for j in state.stock_first[index]..<state.stock_first[index+1] {
        if written >= len(out) { break }
        entry := state.stock[j]
        consumed, produced := recipe_flow(state.recipes[index],entry.resource_id)
        out[written] = {resource_id=entry.resource_id, consumed_per_hour=consumed, produced_per_hour=produced}
        written += 1
    }
    return written
}

// Runs the hourly production step for every operational building. `tick` is the
// 1-based index of the fixed step being simulated, and the step runs only when it is
// a whole simulated hour (`tick % TICKS_PER_HOUR == 0`). The tick is passed
// explicitly because `advance_clock` advances whole frame batches: the clock already
// holds the post-frame count inside the per-tick loop, so the modulo of
// `clock.ticks` would run production once per loop iteration or not at all depending
// on where a frame starts. This keeps exactly one evaluation per simulated hour at
// every clock speed and frame pacing. Must be called once per fixed tick; nothing is
// evaluated outside hour boundaries. Edge-triggered: `Production_Blocked` is
// published only when an operational building starts skipping hours for a missing
// input, `Production_Resumed` only when a previously blocked building runs again. A
// full output store never publishes a notice.
step_production :: proc(state: ^State, tick: i64) {
    if tick % TICKS_PER_HOUR != 0 { return }
    for i in 0..<len(state.buildings) {
        recipe := state.recipes[i]
        relevant := len(recipe.needs) > 0 || len(recipe.produces) > 0
        if !relevant {
            state.production_blocked[i] = false
            continue
        }
        if !production_operational(state,i) {
            // Leaving operation (disable, staffing loss, warmup) ends the blocked
            // sequence: re-entering operation later publishes a fresh transition.
            state.production_blocked[i] = false
            continue
        }
        fits, reason, _ := recipe_fits(state,i,recipe)
        if !fits {
            if reason == .Missing_Input && !state.production_blocked[i] {
                state.production_blocked[i] = true
                push_event(&state.events,.Production_Blocked,state.buildings[i].id)
            }
            continue
        }
        if state.production_blocked[i] {
            state.production_blocked[i] = false
            push_event(&state.events,.Production_Resumed,state.buildings[i].id)
        }
        apply_recipe(state,i,recipe)
    }
}

// True when automatic load shedding may stop this building: it is an active
// consumer (positive configured demand, no configured output). Generators are
// never shed, and the pre-existing shutdown locks (Control Unit, `always_on`) are
// never overridden by shedding.
shed_candidate :: proc(state: ^State, index: int) -> bool {
    if !state.active[index] { return false }
    if state.power[index].output_kw > 0 { return false }
    if state.power[index].need_kw <= 0 { return false }
    if state.always_on[index] { return false }
    return state.buildings[index].building_id != c.CONTROL_UNIT_ID
}

// Resolves a negative instantaneous balance by force-stopping the active consumer
// with the greatest configured demand, lowest level index first on a tie, and
// cascading until the balance is nonnegative or no candidate remains. Each shed is
// complete in the same tick: demand disappears immediately and the building does
// not enter cooldown. Every shed appends one `Power_Shed` event in shed order; the
// application groups all events of one tick into a single notice. If no candidate
// remains and the balance is still negative the signed balance is displayed
// unchanged, because the model never invents power.
step_load_shedding :: proc(state: ^State) {
    for balance(state).available_kw < 0 {
        index := -1
        for i in 0..<len(state.buildings) {
            if !shed_candidate(state,i) { continue }
            if index < 0 || state.power[i].need_kw > state.power[index].need_kw { index = i }
        }
        if index < 0 { break }
        state.active[index] = false
        state.level[index] = 0
        push_event(&state.events,.Power_Shed,state.buildings[index].id)
    }
}
