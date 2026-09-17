package logic

import "core:math"

// Station reservations cover ordinary undelivered cargo and evacuation manifests,
// including people still walking. Capacity is released only on delivery/discharge.
station_reserved_subjects :: proc(state: ^Transport_State, subject_id: string) -> f64 {
    reserved: f64
    for mission in state.missions[:state.count] {
        // Medical patients enter the station as identified individuals, not stock,
        // so they never reserve stock replenishment capacity.
        if mission.medical { continue }
        if mission.subject_id == subject_id && mission.phase != .Completed && mission.phase != .Cancelled {
            reserved += f64(mission.units-mission.delivered-mission.returned)
        }
    }
    return reserved
}

// Once per simulation tick, before missions and dispatch. Reserved station capacity
// prevents replenishment from losing passengers on cancellation or evacuation.
// Fractional rates accumulate privately; saturation discards excess, not a backlog.
step_station_subjects :: proc(state: ^Transport_State) {
    for &stock, i in state.stock {
        capacity: f64
        for definition in state.station.subjects {
            if definition.subject_id == stock.subject_id { capacity = math.floor(f64(definition.capacity)); break }
        }
        limit := max(f64(0),capacity-station_reserved_subjects(state,stock.subject_id))
        rate := f64(stock.units_per_hour)
        if rate == 0 { continue }
        total := state.stock_fraction[i]+rate/TICKS_PER_HOUR
        whole := total >= 0 ? math.floor(total+1e-10) : math.ceil(total-1e-10)
        next := clamp(f64(stock.units)+whole,0,limit)
        state.stock_fraction[i] = total-whole
        if (rate > 0 && next >= limit) || (rate < 0 && next <= 0) { state.stock_fraction[i] = 0 }
        // Catalog capacities/rates may exceed machine integer range; work is
        // bounded by the individual pool before converting or iterating.
        change := int(clamp(next-f64(stock.units),-f64(SUBJECT_LIMIT),f64(SUBJECT_LIMIT)))
        if change > 0 {
            for _ in 0..<change {
                if add_runtime_subject(state,{subject_id=stock.subject_id,health=1,activity=.Station}) < 0 {
                    state.stock_fraction[i] = 0
                    break
                }
                stock.units += 1
            }
        } else if change < 0 {
            for &subject in state.subjects {
                if subject.subject_id != stock.subject_id || subject.activity != .Station || subject.medical != .None { continue }
                subject.activity = .Removed
                stock.units -= 1
                change += 1
                if change == 0 { break }
            }
        }
    }
}

// Handling is throughput, not hours per operation. Dispatch rejects a zero rate.
handling_duration :: proc(units: f32, rate: f64) -> f64 {
    if units <= 0 { return 0 }
    assert(rate > 0) // Dispatch never starts handling with a zero throughput.
    return f64(units)/rate
}
transport_cargo :: proc(mission: Transport) -> f32 {
    return max(f32(0),mission.loaded-mission.delivered-mission.returned)
}
