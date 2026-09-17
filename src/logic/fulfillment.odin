package logic

// Hourly individual need fulfillment from per-building runtime stock.
//
// Once per whole simulated hour, aligned with `step_production` and placed before
// the fixed-tick health step, every live subject physically `Inside` a building
// draws its configured `amount_per_hour` from that building's runtime stock. The
// supplied fraction becomes the need's `fulfillment`, so the unchanged quadratic
// shortage math in `subject_health.odin` keeps working on real supply: a fully
// supplied need clears its shortage clock, a partial supply advances it and scales
// the satisfied gain.
//
// Draw source and transit
// -----------------------
// The draw source is the building the subject physically arrived at (`activity`
// `.Inside` and `destination` naming a level building instance). A subject in
// transit (`.Station`, `.Onboard`, `.Waiting`, `.Moving` and station-side
// `.Reserved`) draws nothing and keeps its previous fulfillment; the health step
// keeps applying the last known fraction while it travels.
//
// Unstocked supplies
// ------------------
// A building that resolves no stock entry for a needed resource leaves
// `fulfillment` at `1`, so a level without a stocked supply keeps working instead
// of silently starving its subjects. `config.load` reports that gap once at startup
// as an actionable configuration diagnostic for resident buildings.
//
// Allocation and scheduling
// -------------------------
// The step allocates nothing, retains no catalog storage past the call and never
// rounds: amounts are fractional `f64` accumulations. It is scheduled at the same
// whole simulated hour boundary as production, so it must receive the same 1-based
// logical tick index and be called once per fixed tick. Nothing is evaluated
// outside hour boundaries.

// Index of the level building instance the subject is physically inside, or -1 for
// an unknown destination and for any subject that is not `Inside`. Only the stable
// walking destination identifies the building; a subject in transit has no draw
// source even when its position still overlaps a building.
@(private)
subject_building_index :: proc(state: ^State, subject: ^Runtime_Subject) -> int {
    if subject.activity != .Inside || subject.destination == "" { return -1 }
    for building, i in state.buildings {
        if building.id == subject.destination { return i }
    }
    return -1
}

// Index of one building's runtime stock entry for a resource, or -1 when the
// building resolves no entry for it. The stock table is bounded and ordered, so no
// search structure or allocation is needed.
@(private)
stock_entry_for_resource :: proc(state: ^State, building_index: int, resource_id: string) -> int {
    for j in state.stock_first[building_index]..<state.stock_first[building_index+1] {
        if state.stock[j].resource_id == resource_id { return j }
    }
    return -1
}

// Runs the hourly need fulfillment for every live subject physically `Inside` a
// building. For one need the requirement is the configured `amount_per_hour`, the
// available amount is the containing building's stock, and
// `fulfillment = clamp(available / required, 0, 1)`; the supplied amount
// (`required * fulfillment`) is removed from the stock. The unmet fraction is left
// to advance the existing shortage clock in `step_subject_health`, which owns all
// shortage and health math. A building without a stock entry for the resource keeps
// `fulfillment` at `1` instead of starving the subject.
step_need_fulfillment :: proc(state: ^State, fleet: ^Transport_State, tick: i64) {
    if tick % TICKS_PER_HOUR != 0 { return }
    for &subject in fleet.subjects {
        if subject.activity != .Inside { continue }
        definition, found := find_subject_type(fleet,subject.subject_id)
        if !found { continue }
        building_index := subject_building_index(state,&subject)
        if building_index < 0 { continue }
        count := min(subject.need_count,len(definition.needs))
        for i in 0..<count {
            need := &subject.needs[i]
            entry := stock_entry_for_resource(state,building_index,need.resource_id)
            if entry < 0 {
                // Unstocked supply: keep the level running at full fulfillment. The
                // startup diagnostic in config.load reports the configuration gap.
                need.fulfillment = 1
                continue
            }
            required := f64(definition.needs[i].amount_per_hour)
            stock := &state.stock[entry]
            supplied := min(required,stock.amount)
            need.fulfillment = required > 0 ? f32(clamp(supplied/required,0,1)) : 1
            stock.amount = clamp(stock.amount-supplied,0,stock.capacity)
        }
    }
}
