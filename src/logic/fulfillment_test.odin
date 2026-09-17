package logic

import "core:mem"
import "core:testing"

// Phase-3 headless regressions for hourly individual need fulfillment from the
// building the subject is physically inside. No renderer, window, GPU resource,
// wall-clock time or random seed is involved. The step is driven through the same
// 1-based logical tick index as `step_production`.

// One resident home with explicit runtime stock, plus a Control Unit so the session
// power balance is valid. The fixture owns every borrowed slice for the whole test.
Fulfillment_Test :: struct {
	storage:     [2]Storage,
	stored:      [2]Stored_Resource,
	definitions: [2]Building_Type,
	initial:     [2]Building_Instance,
	roles:       [1]Subject_Role_Definition,
	needs:       [2]Subject_Need,
	types:       [1]Subject_Type,
	state:       State,
	fleet:       Transport_State,
}

fulfillment_init :: proc(r: ^Fulfillment_Test, water, meals: f32) {
	r.storage = {{resource_id="water",capacity=100},{resource_id="meals",capacity=100}}
	r.stored = {{resource_id="water",amount=water},{resource_id="meals",amount=meals}}
	r.definitions = {
		{id="control_unit"},
		{id="home",residents={type="human",capacity=8},storage=r.storage[:]},
	}
	r.initial = {
		{id="CU1",building_id="control_unit",health=1,enable_at_start=true},
		{id="H1",building_id="home",health=1,enable_at_start=true,stored=r.stored[:]},
	}
	r.roles = {{role_id=.worker}}
	r.needs = {
		{resource_id="water",amount_per_hour=2},
		{resource_id="meals",amount_per_hour=1},
	}
	r.types = {{id="human",roles=r.roles[:],needs=r.needs[:]}}
	r.state = new_session(r.initial[:],r.definitions[:],context.allocator)
	r.fleet = new_transports({},{},nil,r.initial[:],nil,context.allocator,r.definitions[:],r.types[:])
}

fulfillment_destroy :: proc(r: ^Fulfillment_Test) {
	destroy_transports(&r.fleet,context.allocator)
	destroy(&r.state,context.allocator)
}

// Adds one human physically inside the home. Its needs are materialized from the
// subject type with full initial fulfillment.
fulfillment_resident :: proc(r: ^Fulfillment_Test, activity: Subject_Activity = .Inside) -> int {
	index := add_runtime_subject(&r.fleet,{subject_id="human",residence="H1",destination="H1",activity=activity,health=1})
	assert(index >= 0)
	return index
}

// Stock amount of one resource on the home (level index 1).
fulfillment_stock :: proc(r: ^Fulfillment_Test, resource_id: string) -> f64 {
	for entry in stock_snapshot(&r.state,1) {
		if entry.resource_id == resource_id { return entry.amount }
	}
	return 0
}

@(test)
need_fulfillment_draws_from_the_inside_building_stock :: proc(t: ^testing.T) {
	r: Fulfillment_Test
	fulfillment_init(&r,1,4)
	defer fulfillment_destroy(&r)
	index := fulfillment_resident(&r)
	// One hour: 2 water required against 1 available -> half; 1 meal required against
	// 4 available -> full. The supplied amount is removed from the building stock.
	step_need_fulfillment(&r.state,&r.fleet,TICKS_PER_HOUR)
	testing.expect(t,abs(f64(r.fleet.subjects[index].needs[0].fulfillment)-0.5) < 1e-6)
	testing.expect(t,r.fleet.subjects[index].needs[1].fulfillment == 1)
	testing.expect(t,fulfillment_stock(&r,"water") == 0)
	testing.expect(t,fulfillment_stock(&r,"meals") == 3)
	// The unmet fraction advances the existing shortage clock through the unchanged
	// health step; the fully supplied need clears it.
	step_subject_health(&r.fleet)
	testing.expect(t,abs(r.fleet.subjects[index].needs[0].shortage_hours-TICK_HOURS) < 1e-9)
	testing.expect(t,r.fleet.subjects[index].needs[1].shortage_hours == 0)
}

@(test)
zero_stock_sets_zero_fulfillment_without_going_negative :: proc(t: ^testing.T) {
	r: Fulfillment_Test
	fulfillment_init(&r,0,0)
	defer fulfillment_destroy(&r)
	index := fulfillment_resident(&r)
	step_need_fulfillment(&r.state,&r.fleet,TICKS_PER_HOUR)
	testing.expect(t,r.fleet.subjects[index].needs[0].fulfillment == 0)
	testing.expect(t,r.fleet.subjects[index].needs[1].fulfillment == 0)
	// An empty store never goes negative.
	testing.expect(t,fulfillment_stock(&r,"water") == 0 && fulfillment_stock(&r,"meals") == 0)
}

@(test)
missing_stock_entry_keeps_full_fulfillment :: proc(t: ^testing.T) {
	// The building resolves only water: meals has no stock entry at all. A level
	// without that supply keeps working instead of silently starving the resident.
	storage := [?]Storage{{resource_id="water",capacity=100}}
	stored := [?]Stored_Resource{{resource_id="water",amount=50}}
	definitions := [?]Building_Type{{id="control_unit"},{id="home",residents={type="human",capacity=8},storage=storage[:]}}
	initial := [?]Building_Instance{
		{id="CU1",building_id="control_unit",health=1,enable_at_start=true},
		{id="H1",building_id="home",health=1,enable_at_start=true,stored=stored[:]},
	}
	roles := [?]Subject_Role_Definition{{role_id=.worker}}
	needs := [?]Subject_Need{{resource_id="water",amount_per_hour=2},{resource_id="meals",amount_per_hour=1}}
	types := [?]Subject_Type{{id="human",roles=roles[:],needs=needs[:]}}
	state := new_session(initial[:],definitions[:],context.allocator)
	defer destroy(&state,context.allocator)
	fleet := new_transports({},{},nil,initial[:],nil,context.allocator,definitions[:],types[:])
	defer destroy_transports(&fleet,context.allocator)
	index := add_runtime_subject(&fleet,{subject_id="human",residence="H1",destination="H1",activity=.Inside,health=1})
	assert(index >= 0)
	// A stale partial value is restored to full fulfillment, not left in shortage.
	fleet.subjects[index].needs[1].fulfillment = 0.25
	step_need_fulfillment(&state,&fleet,TICKS_PER_HOUR)
	testing.expect(t,fleet.subjects[index].needs[0].fulfillment == 1,"the stocked need draws normally")
	testing.expect(t,fleet.subjects[index].needs[1].fulfillment == 1,"an unstocked need stays fully satisfied")
	amount: f64
	for entry in stock_snapshot(&state,1) { if entry.resource_id == "water" { amount = entry.amount } }
	testing.expect(t,amount == 48,"only the stocked resource is consumed")
}

@(test)
transit_subjects_keep_their_previous_fulfillment :: proc(t: ^testing.T) {
	for activity in ([?]Subject_Activity{.Station,.Reserved,.Onboard,.Waiting,.Moving}) {
		r: Fulfillment_Test
		fulfillment_init(&r,10,10)
		index := fulfillment_resident(&r,activity)
		// A subject that was previously only half supplied keeps that fraction while it
		// travels or waits; it draws nothing from anywhere.
		r.fleet.subjects[index].needs[0].fulfillment = 0.5
		r.fleet.subjects[index].needs[1].fulfillment = 0.25
		step_need_fulfillment(&r.state,&r.fleet,TICKS_PER_HOUR)
		testing.expectf(t,r.fleet.subjects[index].needs[0].fulfillment == 0.5,"activity %v must not draw",activity)
		testing.expectf(t,r.fleet.subjects[index].needs[1].fulfillment == 0.25,"activity %v must not draw",activity)
		testing.expectf(t,fulfillment_stock(&r,"water") == 10 && fulfillment_stock(&r,"meals") == 10,"activity %v must not consume stock",activity)
		fulfillment_destroy(&r)
	}
}

@(test)
fulfillment_runs_once_per_hour_at_the_production_boundary :: proc(t: ^testing.T) {
	r: Fulfillment_Test
	fulfillment_init(&r,10,10)
	defer fulfillment_destroy(&r)
	index := fulfillment_resident(&r)
	r.fleet.subjects[index].needs[0].fulfillment = 0.75
	// Any tick that is not a whole simulated hour leaves stock and fulfillment alone.
	step_need_fulfillment(&r.state,&r.fleet,TICKS_PER_HOUR-1)
	testing.expect(t,fulfillment_stock(&r,"water") == 10 && r.fleet.subjects[index].needs[0].fulfillment == 0.75)
	// A whole hour draws exactly once, and the same boundary with no stock left draws
	// nothing more.
	step_need_fulfillment(&r.state,&r.fleet,TICKS_PER_HOUR)
	testing.expect(t,fulfillment_stock(&r,"water") == 8 && r.fleet.subjects[index].needs[0].fulfillment == 1)
	step_need_fulfillment(&r.state,&r.fleet,2*TICKS_PER_HOUR)
	testing.expect(t,fulfillment_stock(&r,"water") == 6)
	// A very large tick index still evaluates exactly one boundary.
	step_need_fulfillment(&r.state,&r.fleet,1000*TICKS_PER_HOUR)
	testing.expect(t,fulfillment_stock(&r,"water") == 4)
}

// The fulfillment step must stay allocation-free across the hourly boundary.
@(test)
fulfillment_step_allocates_nothing :: proc(t: ^testing.T) {
	backing := context.allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track,backing)
	track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	r: Fulfillment_Test
	fulfillment_init(&r,10,10)
	defer fulfillment_destroy(&r)
	_ = fulfillment_resident(&r)
	built := len(track.allocation_map)
	for hour in 1..=4 { step_need_fulfillment(&r.state,&r.fleet,i64(hour)*TICKS_PER_HOUR) }
	testing.expectf(t,len(track.allocation_map) == built,"fulfillment allocated %d new block(s)",len(track.allocation_map)-built)
	testing.expect(t,len(track.bad_free_array) == 0)
}
