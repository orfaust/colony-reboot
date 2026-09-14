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
Need :: struct {
    resource_id: string,
    amount_per_unit: f32, // Resource units consumed per unit of product.
}
Product :: struct {
    resource_id: string,
    time_per_unit: f32, // Hours required to produce one resource unit.
}
Building_Type :: struct {
    id: c.Building_Type_ID,
    name_key, description_key: string,
    code: string,
    width, height: f32, // World units; position identifies the center.
    color: c.RGB,
    power_need_kw, power_output_kw: f32,
    needs: []Need,
    produces: []Product,
}
Building_Instance :: struct {
    id: string,
    building_id: c.Building_Type_ID,
    position: c.Vector2,
    health: f32,
    repairing: bool,
}

valid_instance :: proc(instance: Building_Instance) -> bool {
    return instance.id != "" && instance.building_id != "" &&
        !math.is_nan(instance.health) && instance.health >= 0 && instance.health <= 1 &&
        !math.is_nan(instance.position.x) && !math.is_inf(instance.position.x) &&
        !math.is_nan(instance.position.y) && !math.is_inf(instance.position.y)
}

// The caller owns array storage; strings borrow the immutable startup catalog.
// Activity is runtime state, deliberately not a configurable level field.
State :: struct {
    buildings: []Building_Instance,
    active: []bool,
    power: []Power,
}
Power :: struct { output_kw, need_kw: f64 }

// Only validated startup configuration may be supplied here. No per-command allocation.
new_session :: proc(initial: []Building_Instance, definitions: []Building_Type, allocator: mem.Allocator) -> State {
    state := State{
        buildings = make([]Building_Instance, len(initial), allocator),
        active = make([]bool, len(initial), allocator),
        power = make([]Power, len(initial), allocator),
    }
    for building, i in initial {
        assert(valid_instance(building))
        found := false
        for definition in definitions {
            if definition.id == building.building_id {
                state.power[i] = {f64(definition.power_output_kw), f64(definition.power_need_kw)}
                found = true
                break
            }
        }
        assert(found) // Startup validation resolves every level building_id.
    }
    reset(&state, initial)
    assert(balance(&state).available_kw >= 0) // Config rejects an invalid always-on CU network.
    return state
}

// Use with individually freeable allocators; an arena owner may instead free its arena.
destroy :: proc(state: ^State, allocator: mem.Allocator) {
    delete(state.buildings, allocator)
    delete(state.active, allocator)
    delete(state.power, allocator)
    state^ = {}
}

// Reset from the same level without allocating or modifying the level template.
reset :: proc(state: ^State, initial: []Building_Instance) {
    assert(len(state.buildings) == len(initial))
    copy(state.buildings, initial)
    for building, i in initial { state.active[i] = building.building_id == c.CONTROL_UNIT_ID }
}

// Returned values cannot mutate authoritative state. IDs borrow configuration storage.
snapshot :: proc(state: ^State, index: int) -> c.Building_Snapshot {
    b := state.buildings[index]
    power := state.power[index]
    active := state.active[index]
    return {id=b.id, building_id=b.building_id, position=b.position, health=b.health, repairing=b.repairing,
        active=active, power_output_kw=active ? power.output_kw : 0,
        power_need_kw=active ? power.need_kw : 0}
}

// Instantaneous kW balance, not stored energy in kWh. Inactive buildings contribute zero.
balance :: proc(state: ^State) -> c.Power_Balance {
    result: c.Power_Balance
    for power, i in state.power {
        if state.active[i] {
            result.produced_kw += power.output_kw
            result.consumed_kw += power.need_kw
        }
    }
    result.available_kw = result.produced_kw - result.consumed_kw
    if result.available_kw < 0 && !power_shortage(result.produced_kw, result.consumed_kw) { result.available_kw = 0 }
    return result
}

// Startup eligibility shares the same always-on rule as reset. Building ID references
// must already be validated; no session allocation is needed to check the level.
initial_balance :: proc(initial: []Building_Instance, definitions: []Building_Type) -> f64 {
    produced, consumed: f64
    for building in initial {
        if building.building_id != c.CONTROL_UNIT_ID { continue }
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
// unchanged. Evaluate the entire proposed network so combined producer/consumers
// can start from their own output and shutting down also removes their consumption.
toggle :: proc(state: ^State, command: c.Toggle_Building) -> c.Toggle_Result {
    index := -1
    for building, i in state.buildings {
        if building.id == command.id { index = i; break }
    }
    if index < 0 { return .Unknown_Building }
    if state.buildings[index].building_id == c.CONTROL_UNIT_ID { return .Control_Unit_Locked }
    produced, consumed: f64
    for power, i in state.power {
        enabled := state.active[i]
        if i == index { enabled = !enabled }
        if enabled {
            produced += power.output_kw
            consumed += power.need_kw
        }
    }
    if power_shortage(produced, consumed) {
        if state.active[index] { return .Generator_Required }
        return .Insufficient_Power
    }
    state.active[index] = !state.active[index]
    return .Applied
}
