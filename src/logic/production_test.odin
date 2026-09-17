package logic

import "core:math"
import "core:mem"
import "core:testing"
import c "../contracts"

// Phase-2 headless regressions for the hourly production tick and automatic load
// shedding. Every test runs without a renderer, a window or a GPU resource, uses no
// wall-clock time and no random seed. Production is driven through the same
// clock-tick/ramp/production prefix the application uses; the tick index is passed
// explicitly because the clock advances whole frame batches.

// One operational building with explicit stock. It declares no staffing slots, so it
// is vacuously staffed and the recipe evaluation is isolated from coverage.
production_state :: proc(definition: Building_Type, stored: []Stored_Resource, allocator: mem.Allocator) -> State {
    definitions := [?]Building_Type{{id="control_unit"},definition}
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1},
        {id="B1",building_id=definition.id,health=1,enable_at_start=true,stored=stored},
    }
    return new_session(initial[:],definitions[:],allocator)
}

// Mirrors the application tick prefix for one building: ramp, then evaluate
// production for the given 1-based logical tick index.
production_run :: proc(state: ^State, ticks: int, first_tick: i64) {
    for i in 0..<ticks {
        step(state)
        step_production(state,first_tick+i64(i)+1)
    }
}

production_amount :: proc(state: ^State, resource_id: string) -> f64 {
    for entry in stock_snapshot(state,1) {
        if entry.resource_id == resource_id { return entry.amount }
    }
    return 0
}

production_rate :: proc(rates: []c.Production_Rate, resource_id: string) -> c.Production_Rate {
    for rate in rates { if rate.resource_id == resource_id { return rate } }
    return {}
}

// --- Recipe math -------------------------------------------------------------

@(test)
recipe_math_scales_per_unit_needs_by_the_first_product :: proc(t: ^testing.T) {
    needs := [?]Need{
        {resource_id="water",amount_per_hour=4,capacity=1000},
        {resource_id="compost",amount_per_unit=2,capacity=1000},
    }
    // `vegetables` is the first entry and therefore the reference product; the second
    // product rate never scales the per-unit needs.
    produces := [?]Product{
        {resource_id="vegetables",units_per_hour=10,capacity=1000},
        {resource_id="seeds",units_per_hour=3,capacity=1000},
    }
    stored := [?]Stored_Resource{
        {resource_id="water",amount=1000},
        {resource_id="compost",amount=1000},
        {resource_id="vegetables",amount=0},
        {resource_id="seeds",amount=0},
    }
    definition := Building_Type{id="farm",needs=needs[:],produces=produces[:]}
    state := production_state(definition,stored[:],context.allocator)
    defer destroy(&state,context.allocator)
    rates: [4]c.Production_Rate
    count := production_rates(&state,1,rates[:])
    testing.expect(t,count == 4)
    testing.expect(t,production_rate(rates[:count],"water").consumed_per_hour == 4,"amount_per_hour is used directly")
    testing.expect(t,production_rate(rates[:count],"compost").consumed_per_hour == 20,"amount_per_unit * first product rate")
    testing.expect(t,production_rate(rates[:count],"vegetables").produced_per_hour == 10)
    testing.expect(t,production_rate(rates[:count],"seeds").produced_per_hour == 3)
    // Nothing is produced before the first whole simulated hour.
    production_run(&state,59,0)
    testing.expect(t,production_amount(&state,"water") == 1000)
    testing.expect(t,production_amount(&state,"vegetables") == 0)
    // The whole recipe runs once at the boundary.
    production_run(&state,1,59)
    testing.expect(t,production_amount(&state,"water") == 996)
    testing.expect(t,production_amount(&state,"compost") == 980)
    testing.expect(t,production_amount(&state,"vegetables") == 10)
    testing.expect(t,production_amount(&state,"seeds") == 3)
    // A second hour compounds exactly.
    production_run(&state,60,60)
    testing.expect(t,production_amount(&state,"water") == 992)
    testing.expect(t,production_amount(&state,"compost") == 960)
    testing.expect(t,production_amount(&state,"vegetables") == 20)
    testing.expect(t,production_amount(&state,"seeds") == 6)
    testing.expect(t,len(pending_events(&state.events)) == 0,"an operational recipe publishes no notice")
}

@(test)
fractional_rates_accumulate_and_reset_restores_the_template :: proc(t: ^testing.T) {
    needs := [?]Need{{resource_id="water",amount_per_unit=0.5,capacity=100}}
    produces := [?]Product{{resource_id="flour",units_per_hour=0.1,capacity=100}}
    stored := [?]Stored_Resource{{resource_id="water",amount=10},{resource_id="flour",amount=0}}
    definitions := [?]Building_Type{{id="control_unit"},{id="mill",needs=needs[:],produces=produces[:]}}
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1},
        {id="B1",building_id="mill",health=1,enable_at_start=true,stored=stored[:]},
    }
    state := new_session(initial[:],definitions[:],context.allocator)
    defer destroy(&state,context.allocator)
    // 0.1 flour per hour and 0.05 water per hour for 25 hours.
    production_run(&state,25*TICKS_PER_HOUR,0)
    testing.expect(t,abs(production_amount(&state,"flour")-2.5) < 1e-6)
    testing.expect(t,abs(production_amount(&state,"water")-8.75) < 1e-6)
    // Reset restores the level template and clears the transition accounting.
    reset(&state,initial[:])
    testing.expect(t,production_amount(&state,"flour") == 0 && production_amount(&state,"water") == 10)
    testing.expect(t,len(pending_events(&state.events)) == 0)
    testing.expect(t,production_status(&state,1) == .None)
}

// --- All-or-nothing ----------------------------------------------------------

@(test)
all_or_nothing_skips_the_hour_and_resumes_once_inputs_exist :: proc(t: ^testing.T) {
    needs := [?]Need{{resource_id="water",amount_per_hour=5,capacity=100}}
    produces := [?]Product{{resource_id="bread",units_per_hour=2,capacity=100}}
    stored := [?]Stored_Resource{{resource_id="water",amount=4},{resource_id="bread",amount=0}}
    state := production_state(Building_Type{id="bakery",needs=needs[:],produces=produces[:]},stored[:],context.allocator)
    defer destroy(&state,context.allocator)
    // A shortfall of one unit skips the whole hour: no partial consumption and no
    // partial production, and the transition is published exactly once.
    testing.expect(t,production_status(&state,1) == .Missing_Input)
    production_run(&state,60,0)
    testing.expect(t,production_amount(&state,"water") == 4,"a skipped hour consumes nothing")
    testing.expect(t,production_amount(&state,"bread") == 0)
    events := pending_events(&state.events)
    testing.expect(t,len(events) == 1 && events[0].kind == .Production_Blocked && events[0].building_id == "B1")
    // A second skipped hour repeats no notice.
    production_run(&state,60,60)
    testing.expect(t,len(pending_events(&state.events)) == 1)
    testing.expect(t,production_amount(&state,"water") == 4)
    // Refilling the missing input resumes exactly once, on the next hour boundary.
    state.stock[state.stock_first[1]].amount = 10
    production_run(&state,60,120)
    events = pending_events(&state.events)
    testing.expect(t,len(events) == 2 && events[1].kind == .Production_Resumed && events[1].building_id == "B1")
    testing.expect(t,production_amount(&state,"water") == 5 && production_amount(&state,"bread") == 2)
    testing.expect(t,production_status(&state,1) == .None,"a blocked building that ran again is operational")
}

@(test)
full_output_store_skips_without_a_notice :: proc(t: ^testing.T) {
    needs := [?]Need{{resource_id="water",amount_per_hour=1,capacity=10}}
    produces := [?]Product{{resource_id="bread",units_per_hour=1,capacity=5}}
    stored := [?]Stored_Resource{{resource_id="water",amount=10},{resource_id="bread",amount=5}}
    state := production_state(Building_Type{id="bakery",needs=needs[:],produces=produces[:]},stored[:],context.allocator)
    defer destroy(&state,context.allocator)
    testing.expect(t,production_status(&state,1) == .Output_Full)
    production_run(&state,60,0)
    testing.expect(t,production_amount(&state,"water") == 10,"a full store consumes no input")
    testing.expect(t,production_amount(&state,"bread") == 5)
    testing.expect(t,len(pending_events(&state.events)) == 0,"a full output store publishes no notice")
    // An output that fits exactly after the inputs are applied runs.
    state.stock[state.stock_first[1]+1].amount = 4
    testing.expect(t,production_status(&state,1) == .None)
    production_run(&state,60,60)
    testing.expect(t,production_amount(&state,"water") == 9 && production_amount(&state,"bread") == 5)
    testing.expect(t,len(pending_events(&state.events)) == 0)
    // A missing input outranks a full output store when both conditions apply.
    state.stock[state.stock_first[1]].amount = 0
    testing.expect(t,production_status(&state,1) == .Missing_Input)
}

// --- Hourly scheduling -------------------------------------------------------

@(test)
production_runs_once_per_hour_independent_of_clock_pacing :: proc(t: ^testing.T) {
    needs := [?]Need{{resource_id="water",amount_per_hour=5,capacity=100}}
    produces := [?]Product{{resource_id="bread",units_per_hour=2,capacity=100}}
    stored := [?]Stored_Resource{{resource_id="water",amount=100},{resource_id="bread",amount=0}}
    definition := Building_Type{id="bakery",needs=needs[:],produces=produces[:]}
    direct := production_state(definition,stored[:],context.allocator)
    defer destroy(&direct,context.allocator)
    batched := production_state(definition,stored[:],context.allocator)
    defer destroy(&batched,context.allocator)
    // Four hours, one logical tick at a time.
    production_run(&direct,4*TICKS_PER_HOUR,0)
    // The same four hours at 32x: one 0.125 s frame advances 240 ticks, so the clock
    // holds the post-frame count while the loop reconstructs each logical tick.
    batched.clock.speed_index = 5
    tick: i64
    for _ in 0..<1 {
        steps := advance_clock(&batched.clock,0.125)
        testing.expect(t,steps == 4*TICKS_PER_HOUR,"32x frame batch")
        for _ in 0..<steps {
            tick += 1
            step(&batched)
            step_production(&batched,tick)
        }
    }
    testing.expect(t,production_amount(&direct,"water") == 80 && production_amount(&direct,"bread") == 8)
    testing.expect(t,production_amount(&batched,"water") == production_amount(&direct,"water"))
    testing.expect(t,production_amount(&batched,"bread") == production_amount(&direct,"bread"))
    testing.expect(t,len(pending_events(&direct.events)) == 0 && len(pending_events(&batched.events)) == 0)
    // Exactly four hourly evaluations, never one per minute: a per-tick step would
    // have produced 240 batches and emptied the input.
    testing.expect(t,production_amount(&batched,"water") == 80)
}

// --- Gating ------------------------------------------------------------------

@(test)
production_is_gated_by_activity_warmup_and_staffing :: proc(t: ^testing.T) {
    needs := [?]Need{{resource_id="water",amount_per_hour=5,capacity=100}}
    produces := [?]Product{{resource_id="bread",units_per_hour=2,capacity=100}}
    stored := [?]Stored_Resource{{resource_id="water",amount=100},{resource_id="bread",amount=0}}
    // Inactive: enabled by the level only when asked, so no hour ever runs.
    definition := Building_Type{id="bakery",needs=needs[:],produces=produces[:],warmup_time=2,cooldown_time=2}
    definitions := [?]Building_Type{{id="control_unit"},definition}
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1},
        {id="B1",building_id="bakery",health=1,enable_at_start=false,stored=stored[:]},
    }
    state := new_session(initial[:],definitions[:],context.allocator)
    defer destroy(&state,context.allocator)
    testing.expect(t,production_status(&state,1) == .Inactive)
    production_run(&state,120,0)
    testing.expect(t,production_amount(&state,"bread") == 0 && production_amount(&state,"water") == 100)
    // Warming up: the first hour boundary lands below level 1, the second completes it.
    testing.expect(t,toggle(&state,{id="B1"}) == .Applied)
    testing.expect(t,state.level[1] == 0)
    production_run(&state,60,120)
    testing.expect(t,abs(state.level[1]-0.5) < 1e-9 && production_status(&state,1) == .Warming_Up)
    testing.expect(t,production_amount(&state,"bread") == 0)
    production_run(&state,60,180)
    testing.expect(t,state.level[1] == 1)
    testing.expect(t,production_amount(&state,"bread") == 2)
    // Cooling: a deactivated building keeps its level while it still consumes power,
    // but the hourly step must not produce or consume material.
    testing.expect(t,toggle(&state,{id="B1"}) == .Applied)
    production_run(&state,60,240)
    testing.expect(t,!state.active[1] && abs(state.level[1]-0.5) < 1e-9)
    testing.expect(t,production_status(&state,1) == .Inactive)
    testing.expect(t,production_amount(&state,"bread") == 2 && production_amount(&state,"water") == 95)
    // Unstaffed: an enabled building with an uncovered continuous slot produces
    // nothing, keeps its activity and never starts cooldown.
    worker_slot := [?]Building_Subject_Role{{role_id=.worker,quantity=1,staffing_mode=.continuous}}
    staffed_definition := Building_Type{id="staffed_bakery",needs=needs[:],produces=produces[:],subject_roles=worker_slot[:]}
    staffed_definitions := [?]Building_Type{{id="control_unit"},staffed_definition}
    staffed_initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1},
        {id="B1",building_id="staffed_bakery",health=1,enable_at_start=true,stored=stored[:]},
    }
    unstaffed := new_session(staffed_initial[:],staffed_definitions[:],context.allocator)
    defer destroy(&unstaffed,context.allocator)
    testing.expect(t,!building_staffed(&unstaffed,1))
    testing.expect(t,production_status(&unstaffed,1) == .Unstaffed)
    production_run(&unstaffed,60,0)
    testing.expect(t,production_amount(&unstaffed,"bread") == 0 && production_amount(&unstaffed,"water") == 100)
    testing.expect(t,unstaffed.active[1] && unstaffed.level[1] == 1,"a staffing loss never disables the building")
}

// --- Load shedding -----------------------------------------------------------

Load_Shed_Test :: struct {
    definitions: [8]Building_Type,
    initial: [8]Building_Instance,
    worker_slots: [1]Building_Subject_Role,
    role_definitions: [1]Subject_Role_Definition,
    subject_roles: [1]Subject_Role,
    human: [1]Subject_Type,
    game: State,
    fleet: Transport_State,
}

load_shed_init :: proc(r: ^Load_Shed_Test) {
    r.worker_slots = {{role_id=.worker,quantity=1,staffing_mode=.continuous}}
    r.role_definitions = {{role_id=.worker}}
    r.subject_roles = {.worker}
    r.human = {{id="human",roles=r.role_definitions[:],work_time=12,rest_time=12,extra_work_time=4,
        min_work_health=0.4,min_colony_health=0.1,
        health_rates={work_gain_per_hour=0.002,rest_gain_per_hour=0.01,extra_work_loss_per_hour=0.025,
            max_inactivity_loss_per_hour=0.012,inactivity_max_time=72,station_recovery_per_hour=0.04}}}
    r.definitions = {
        {id="control_unit"},
        {id="gen1",power_output_kw=20,subject_roles=r.worker_slots[:]},
        {id="gen2",power_output_kw=30,subject_roles=r.worker_slots[:]},
        {id="solar",power_output_kw=20},
        {id="big",power_need_kw=20},
        {id="mid",power_need_kw=20},
        {id="mid2",power_need_kw=20},
        {id="small",power_need_kw=10},
    }
    r.initial = {
        {id="CU1",building_id="control_unit",position={-2,0},health=1,enable_at_start=true},
        {id="GEN1",building_id="gen1",position={2,0},health=1,enable_at_start=true},
        {id="GEN2",building_id="gen2",position={4,0},health=1,enable_at_start=true},
        {id="SP1",building_id="solar",position={6,0},health=1,enable_at_start=true},
        {id="BIG",building_id="big",position={0,2},health=1},
        {id="MID",building_id="mid",position={0,3},health=1},
        {id="MID2",building_id="mid2",position={0,4},health=1},
        {id="SMALL",building_id="small",position={0,5},health=1},
    }
    r.game = new_session(r.initial[:],r.definitions[:],context.allocator)
    r.fleet = new_transports({},{},nil,r.initial[:],nil,context.allocator,r.definitions[:],r.human[:])
}

load_shed_destroy :: proc(r: ^Load_Shed_Test) {
    destroy_transports(&r.fleet,context.allocator)
    destroy(&r.game,context.allocator)
}

// Places one worker physically at a building and starts its shift.
load_shed_worker :: proc(r: ^Load_Shed_Test, building_id: string) -> int {
    position, target: c.Vector2
    for building in r.initial {
        if building.id == building_id { position = building.position; target = building.position; break }
    }
    index := add_runtime_subject(&r.fleet,{subject_id="human",roles=r.subject_roles[:],activity=.Inside,
        position=position,target=target,destination=building_id,health=1})
    assert(index >= 0)
    subject := &r.fleet.subjects[index]
    subject.assignment = c.Shift_Assignment{building_id=building_id,role_id=.worker,slot_index=0}
    subject.phase = .Working
    return index
}

// Adds a replacement worker after a staffing loss released the previous occupant.
load_shed_worker_takeover :: proc(r: ^Load_Shed_Test, building_id: string) {
    _ = load_shed_worker(r,building_id)
}

@(test)
load_shedding_cascades_greatest_demand_first_with_lowest_index_tie_break :: proc(t: ^testing.T) {
    r: Load_Shed_Test
    load_shed_init(&r)
    defer load_shed_destroy(&r)
    gen1 := load_shed_worker(&r,"GEN1")
    gen2 := load_shed_worker(&r,"GEN2")
    derive_staffing(&r.game,&r.fleet)
    testing.expect(t,balance(&r.game).produced_kw == 70)
    // Consumers are activated in reverse level order, so a tie-break cannot be an
    // artifact of the activation order.
    testing.expect(t,toggle(&r.game,{id="SMALL"}) == .Applied)
    testing.expect(t,toggle(&r.game,{id="MID2"}) == .Applied)
    testing.expect(t,toggle(&r.game,{id="MID"}) == .Applied)
    testing.expect(t,toggle(&r.game,{id="BIG"}) == .Applied)
    testing.expect(t,balance(&r.game).available_kw == 0)
    // Both generators lose coverage in one tick: 20 kW of solar against 70 kW of load.
    r.fleet.subjects[gen1].health = 0.1
    r.fleet.subjects[gen2].health = 0.1
    derive_staffing(&r.game,&r.fleet)
    testing.expect(t,balance(&r.game).available_kw == -50)
    step_load_shedding(&r.game)
    // Greatest configured demand first; BIG, MID and MID2 are tied at 20 kW and are
    // shed by ascending level index. SMALL (10 kW) stays active once balanced. The
    // same tick also published the two staffing losses of the generators.
    shed_order: [4]string
    shed_count := 0
    for event in pending_events(&r.game.events) {
        if event.kind != .Power_Shed { continue }
        shed_order[shed_count] = event.building_id
        shed_count += 1
    }
    testing.expect(t,shed_count == 3)
    testing.expect(t,shed_order[0] == "BIG" && shed_order[1] == "MID" && shed_order[2] == "MID2")
    testing.expect(t,!r.game.active[4] && r.game.level[4] == 0)
    testing.expect(t,!r.game.active[5] && r.game.level[5] == 0)
    testing.expect(t,!r.game.active[6] && r.game.level[6] == 0)
    testing.expect(t,balance(&r.game).consumed_kw == 10,"the same tick drops every shed demand")
    testing.expect(t,balance(&r.game).available_kw == 10)
    // Generators are never shed, even while their output is gated by staffing.
    testing.expect(t,r.game.active[1] && r.game.active[2] && r.game.active[3])
    // A balanced network is stable: re-running the step publishes nothing.
    step_load_shedding(&r.game)
    total := 0
    for event in pending_events(&r.game.events) { if event.kind == .Power_Shed { total += 1 } }
    testing.expect(t,total == 3)
    // A shed building stays off until the player re-enables it, even after coverage
    // returns through replacements; the generator lock still protects producers.
    load_shed_worker_takeover(&r,"GEN1")
    load_shed_worker_takeover(&r,"GEN2")
    derive_staffing(&r.game,&r.fleet)
    testing.expect(t,!r.game.active[4] && !r.game.active[5] && !r.game.active[6])
    testing.expect(t,balance(&r.game).available_kw == 60)
    testing.expect(t,toggle(&r.game,{id="GEN1"}) == .Generator_Required)
    testing.expect(t,toggle(&r.game,{id="BIG"}) == .Applied)
    testing.expect(t,balance(&r.game).available_kw == 40)
}

@(test)
load_shedding_respects_locks_and_never_invents_power :: proc(t: ^testing.T) {
    // The Control Unit and always_on types are never shed candidates, and a building
    // with no configured demand cannot reduce the deficit at all.
    definitions := [?]Building_Type{
        {id="control_unit"},
        {id="solar",power_output_kw=5,always_on=true},
        {id="warehouse",power_need_kw=3,always_on=false},
    }
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1,enable_at_start=true},
        {id="SP1",building_id="solar",health=1,enable_at_start=true},
        {id="W1",building_id="warehouse",health=1,enable_at_start=true},
    }
    state := new_session(initial[:],definitions[:],context.allocator)
    defer destroy(&state,context.allocator)
    // An external output loss is modelled directly: the consumer is the only
    // candidate, so exactly one shed balances 0 kW against 3 kW.
    state.level[1] = 0
    testing.expect(t,balance(&state).available_kw == -3)
    step_load_shedding(&state)
    events := pending_events(&state.events)
    testing.expect(t,len(events) == 1 && events[0].building_id == "W1")
    testing.expect(t,state.active[0] && state.active[1],"locks and generators are never shed")
    testing.expect(t,balance(&state).available_kw == 0)
    // With no candidate left the signed balance is displayed unchanged: a disabled
    // building that is still cooling keeps consuming and is never force-stopped twice.
    state.active[2] = false
    state.level[2] = 1
    state.level[1] = 0
    testing.expect(t,balance(&state).available_kw == -3)
    step_load_shedding(&state)
    testing.expect(t,len(pending_events(&state.events)) == 1,"no candidate left, no new shed")
    testing.expect(t,balance(&state).available_kw == -3,"the model never invents power")
}

// --- Chained scenario --------------------------------------------------------

// Water collector -> greenhouse -> meals factory with explicit per-building initial
// stock and the shipped rates. Inter-building logistics is a later phase, so the
// intermediate stores are refilled by hand where the scenario needs it; the
// production and consumption rates still compose end to end.
@(test)
chained_production_scenario_with_explicit_initial_stock :: proc(t: ^testing.T) {
    water_produces := [?]Product{{resource_id="water",units_per_hour=50,capacity=6000}}
    greenhouse_needs := [?]Need{
        {resource_id="water",amount_per_unit=3,capacity=1200},
        {resource_id="compost",amount_per_unit=6,capacity=300},
    }
    greenhouse_produces := [?]Product{{resource_id="vegetables",units_per_hour=0.16667,capacity=600}}
    factory_needs := [?]Need{
        {resource_id="vegetables",amount_per_unit=0.6,capacity=150},
        {resource_id="water",amount_per_unit=0.5,capacity=200},
        {resource_id="proteins",amount_per_unit=0.2,capacity=50},
    }
    factory_produces := [?]Product{{resource_id="meals",units_per_hour=0.33333,capacity=1200}}
    definitions := [?]Building_Type{
        {id="control_unit"},
        {id="water_collector",produces=water_produces[:]},
        {id="greenhouse",needs=greenhouse_needs[:],produces=greenhouse_produces[:]},
        {id="meals_factory",needs=factory_needs[:],produces=factory_produces[:]},
    }
    collector_stock := [?]Stored_Resource{{resource_id="water",amount=0}}
    greenhouse_stock := [?]Stored_Resource{
        {resource_id="water",amount=100},
        {resource_id="compost",amount=100},
        {resource_id="vegetables",amount=0},
    }
    factory_stock := [?]Stored_Resource{
        {resource_id="vegetables",amount=100},
        {resource_id="water",amount=100},
        {resource_id="proteins",amount=100},
        {resource_id="meals",amount=0},
    }
    initial := [?]Building_Instance{
        {id="CU1",building_id="control_unit",health=1,enable_at_start=true},
        {id="WC1",building_id="water_collector",health=1,enable_at_start=true,stored=collector_stock[:]},
        {id="GH1",building_id="greenhouse",health=1,enable_at_start=true,stored=greenhouse_stock[:]},
        {id="MF1",building_id="meals_factory",health=1,enable_at_start=true,stored=factory_stock[:]},
    }
    state := new_session(initial[:],definitions[:],context.allocator)
    defer destroy(&state,context.allocator)
    // Ten hours at the shipped ratios: 500 water, ~5.0001 water and ~10.0002 compost
    // consumed by the greenhouse, ~1.6667 vegetables grown there, and ~0.2
    // vegetables, ~0.16665 water and ~0.06666 proteins consumed by the factory.
    production_run(&state,10*TICKS_PER_HOUR,0)
    testing.expect(t,abs(stock_amount(&state,1,"water")-500) < 1e-6)
    testing.expect(t,abs(stock_amount(&state,2,"water")-94.9999) < 1e-3)
    testing.expect(t,abs(stock_amount(&state,2,"compost")-89.9998) < 1e-3)
    testing.expect(t,abs(stock_amount(&state,2,"vegetables")-1.6667) < 1e-3)
    testing.expect(t,abs(stock_amount(&state,3,"vegetables")-98) < 1e-2)
    testing.expect(t,abs(stock_amount(&state,3,"water")-98.33335) < 1e-3)
    testing.expect(t,abs(stock_amount(&state,3,"meals")-3.3333) < 1e-3)
    // A starved link stops that building alone: the greenhouse skips its hours and
    // publishes one blocked notice, while the collector and factory keep running.
    state.stock[state.stock_first[2]+1].amount = 0 // compost
    production_run(&state,60,600)
    testing.expect(t,abs(stock_amount(&state,2,"vegetables")-1.6667) < 1e-3,"a starved link skips its whole hour")
    events := pending_events(&state.events)
    testing.expect(t,len(events) == 1 && events[0].kind == .Production_Blocked && events[0].building_id == "GH1")
    testing.expect(t,abs(stock_amount(&state,1,"water")-550) < 1e-6)
    testing.expect(t,abs(stock_amount(&state,3,"meals")-3.6666) < 1e-3)
    // The deferred logistics phase would refill the intermediate store; doing it by
    // hand resumes the link on the next hour boundary.
    state.stock[state.stock_first[2]+1].amount = 10
    production_run(&state,60,660)
    events = pending_events(&state.events)
    testing.expect(t,len(events) == 2 && events[1].kind == .Production_Resumed && events[1].building_id == "GH1")
    testing.expect(t,stock_amount(&state,2,"vegetables") > 1.6667)
}

// Stock amount of one resource on one building index, resolved by ID.
stock_amount :: proc(state: ^State, index: int, resource_id: string) -> f64 {
    for entry in stock_snapshot(state,index) {
        if entry.resource_id == resource_id { return entry.amount }
    }
    return 0
}
