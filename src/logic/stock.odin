package logic

import "core:mem"
import c "../contracts"

// Owned, mutable per-instance runtime stock, laid out flat like the staffing slot
// table for determinism and cache locality. One entry per resource a building type
// resolves from its needs, products and storage entries, ordered by level order and
// then configured need/product/storage order. `Building_Instance.stored` stays the
// immutable level template: it seeds the runtime amounts and never changes.
//
// Capacity and overflow behavior
// ------------------------------
// STOCK_ENTRY_LIMIT bounds the session stock table (buildings times resolved
// resources). Startup validation (config.decode_level) rejects a level whose
// resolved entries exceed the limit with an actionable diagnostic, so
// materialization never truncates and no stock entry is silently dropped.
// new_session asserts the bound because it is a caller invariant, not malformed
// external data. The shipped level resolves 24 entries; the limit leaves headroom
// for a much larger colony while keeping the fixed table bounded.
STOCK_ENTRY_LIMIT :: 1024

// Authoritative runtime record for one resource held by one building instance.
// The layout is exactly the read-only contract value, so stock_snapshot can return
// a borrowed subslice without copying or allocating. resource_id borrows validated
// catalog/level storage; amount is seeded from the level template by reset and is
// otherwise owned by the session.
Stock_Entry :: c.Stock_Snapshot

// Resolved maximum capacity for one resource on one building type: the largest
// `capacity` across its matching need, product and storage entries. `found` is
// false when the type neither needs, produces, nor stores that resource. Shared
// with config level validation so startup and runtime resolve identical bounds.
stock_capacity :: proc(definition: Building_Type, resource_id: string) -> (capacity: f32, found: bool) {
    for need in definition.needs {
        if need.resource_id != resource_id { continue }
        capacity = found ? max(capacity, need.capacity) : need.capacity
        found = true
    }
    for product in definition.produces {
        if product.resource_id != resource_id { continue }
        capacity = found ? max(capacity, product.capacity) : product.capacity
        found = true
    }
    for stock in definition.storage {
        if stock.resource_id != resource_id { continue }
        capacity = found ? max(capacity, stock.capacity) : stock.capacity
        found = true
    }
    return
}

// Total resolved stock entries a level materializes: building order, then distinct
// resources in configured need/product/storage order. Used by startup validation
// before a session exists; unknown definitions contribute nothing.
stock_entry_count :: proc(initial: []Building_Instance, definitions: []Building_Type) -> int {
    total := 0
    for building in initial {
        for definition in definitions {
            if definition.id != building.building_id { continue }
            total += definition_stock_count(definition)
            break
        }
    }
    return total
}

// Number of configured resource positions a type exposes: needs, then products,
// then storage, in array order.
@(private)
definition_resource_positions :: proc(definition: Building_Type) -> int {
    return len(definition.needs)+len(definition.produces)+len(definition.storage)
}

// Resource at one configured position, or "" past the end. Positions are
// contiguous: needs, then products, then storage.
@(private)
definition_resource_at :: proc(definition: Building_Type, position: int) -> string {
    index := position
    if index < len(definition.needs) { return definition.needs[index].resource_id }
    index -= len(definition.needs)
    if index < len(definition.produces) { return definition.produces[index].resource_id }
    index -= len(definition.produces)
    if index < len(definition.storage) { return definition.storage[index].resource_id }
    return ""
}

// Distinct resources a type resolves. A resource that appears in several lists is
// counted once, at its first configured position. Allocation-free.
@(private)
definition_stock_count :: proc(definition: Building_Type) -> int {
    count := 0
    for position in 0..<definition_resource_positions(definition) {
        resource_id := definition_resource_at(definition,position)
        duplicate := false
        for earlier in 0..<position {
            if definition_resource_at(definition,earlier) == resource_id { duplicate = true; break }
        }
        if !duplicate { count += 1 }
    }
    return count
}

// Allocates the flat stock table once and resolves capacities from the definitions.
// Amounts start at zero; reset seeds them from the level template immediately after
// construction, so a materialized session is never partially initialized.
@(private)
materialize_stock :: proc(state: ^State, initial: []Building_Instance, definitions: []Building_Type, allocator: mem.Allocator) {
    state.stock_first = make([]int,len(initial)+1,allocator)
    state.stock = make([]Stock_Entry,stock_entry_count(initial,definitions),allocator)
    next := 0
    for building, i in initial {
        state.stock_first[i] = next
        for definition in definitions {
            if definition.id != building.building_id { continue }
            for position in 0..<definition_resource_positions(definition) {
                resource_id := definition_resource_at(definition,position)
                duplicate := false
                for j in state.stock_first[i]..<next {
                    if state.stock[j].resource_id == resource_id { duplicate = true; break }
                }
                if duplicate { continue }
                capacity, _ := stock_capacity(definition,resource_id)
                state.stock[next] = {resource_id=resource_id,capacity=f64(capacity)}
                next += 1
            }
            break
        }
    }
    state.stock_first[len(initial)] = next
}

@(private)
destroy_stock :: proc(state: ^State, allocator: mem.Allocator) {
    delete(state.stock_first,allocator)
    delete(state.stock,allocator)
    state.stock_first = nil
    state.stock = nil
}

// Restores the level template's initial amounts for the existing layout without
// allocating. The layout is stable for the session (catalog definitions and
// building order never change), so reset only copies amounts; capacities stay the
// definition-resolved values. The caller has already copied the level instances
// into state.buildings, whose `stored` slices still borrow level storage.
@(private)
reset_stock :: proc(state: ^State) {
    if len(state.stock_first) == 0 { return }
    for i in 0..<len(state.stock_first)-1 {
        stored := state.buildings[i].stored
        for j in state.stock_first[i]..<state.stock_first[i+1] {
            entry := &state.stock[j]
            entry.amount = 0
            for candidate in stored {
                if candidate.resource_id == entry.resource_id {
                    entry.amount = f64(candidate.amount)
                    break
                }
            }
        }
    }
}

// Read-only borrowed view of one building's runtime stock, in configured order.
// The slice points at authoritative session storage and is invalidated by the next
// mutation (simulation step, reset or destroy); consumers must not retain it or
// write through it. Empty for a building that resolves no resources.
stock_snapshot :: proc(state: ^State, index: int) -> []c.Stock_Snapshot {
    assert(index >= 0 && index+1 < len(state.stock_first))
    return state.stock[state.stock_first[index]:state.stock_first[index+1]]
}
