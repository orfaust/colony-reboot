package logic

import "core:mem"
import "core:testing"
import c "../contracts"

// Runtime stock foundation regressions: capacity resolution, seed order and
// amounts, restore-on-reset, owned-memory lifetime and the borrowed read-only view.
// No renderer or graphics context is required.

// Two buildings: one resolves no resources, the other resolves three from a need,
// a product and a storage entry, with a duplicate resource appearing in all lists.
// `stored` is deliberately listed in a different order from the configured recipe to
// prove the runtime layout follows need/product/storage order, not the level order.
// The arrays live in the fixture struct (not as procedure locals) so the borrowed
// slices stay valid for the whole test, matching how a level borrows catalog data.
Stock_Test :: struct {
	needs:       [1]Need,
	products:    [2]Product,
	storage:     [2]Storage,
	stored:      [3]Stored_Resource,
	definitions: [2]Building_Type,
	initial:     [2]Building_Instance,
}

stock_test_setup :: proc(r: ^Stock_Test) {
	r.needs = {{resource_id="water",amount_per_hour=1,capacity=10}}
	r.products = {
		{resource_id="water",units_per_hour=1,capacity=100},
		{resource_id="meals",units_per_hour=1,capacity=40},
	}
	r.storage = {{resource_id="materials",capacity=500},{resource_id="water",capacity=25}}
	r.stored = {
		{resource_id="meals",amount=4},
		{resource_id="water",amount=12.5},
		{resource_id="materials",amount=200},
	}
	r.definitions = {
		{id="control_unit"},
		{id="farm",needs=r.needs[:],produces=r.products[:],storage=r.storage[:]},
	}
	r.initial = {
		{id="CU",building_id="control_unit",health=1,enable_at_start=true},
		{id="F1",building_id="farm",health=1,stored=r.stored[:]},
	}
}

@(test)
stock_capacity_resolves_the_largest_configured_bound :: proc(t: ^testing.T) {
	needs := [?]Need{{resource_id="water",amount_per_hour=1,capacity=10}}
	products := [?]Product{
		{resource_id="water",units_per_hour=1,capacity=100},
		{resource_id="meals",units_per_hour=1,capacity=40},
	}
	storage := [?]Storage{{resource_id="water",capacity=25},{resource_id="materials",capacity=500}}
	definition := Building_Type{id="farm",needs=needs[:],produces=products[:],storage=storage[:]}
	// The largest capacity wins across all matching need/product/storage entries.
	capacity, found := stock_capacity(definition,"water")
	testing.expect(t,found && capacity == 100)
	capacity, found = stock_capacity(definition,"meals")
	testing.expect(t,found && capacity == 40)
	// A storage-only resource is resolvable and keeps its own bound.
	capacity, found = stock_capacity(definition,"materials")
	testing.expect(t,found && capacity == 500)
	_, found = stock_capacity(definition,"unlisted")
	testing.expect(t,!found)
}

@(test)
runtime_stock_seeds_amounts_in_configured_order :: proc(t: ^testing.T) {
	r: Stock_Test
	stock_test_setup(&r)
	state := new_session(r.initial[:],r.definitions[:],context.allocator)
	defer destroy(&state,context.allocator)

	// One resolved entry per distinct resource, ordered by need, then product, then
	// storage; the duplicate water appear once at its first position.
	testing.expect(t,stock_entry_count(r.initial[:],r.definitions[:]) == 3)
	testing.expect(t,len(stock_snapshot(&state,0)) == 0)
	stock := stock_snapshot(&state,1)
	testing.expect(t,len(stock) == 3)
	testing.expect(t,stock[0].resource_id == "water" && stock[1].resource_id == "meals" && stock[2].resource_id == "materials")
	// Amounts are copied from the level template and widened to f64; capacities come
	// from the definition resolution, not from the stored entry.
	testing.expect(t,stock[0].amount == f64(12.5) && stock[0].capacity == 100)
	testing.expect(t,stock[1].amount == f64(4) && stock[1].capacity == 40)
	testing.expect(t,stock[2].amount == f64(200) && stock[2].capacity == 500)
	// The level template stays immutable.
	testing.expect(t,r.initial[1].stored[0].amount == 4 && r.initial[1].stored[1].amount == 12.5)
}

@(test)
reset_restores_initial_amounts_without_touching_the_template :: proc(t: ^testing.T) {
	r: Stock_Test
	stock_test_setup(&r)
	state := new_session(r.initial[:],r.definitions[:],context.allocator)
	defer destroy(&state,context.allocator)

	// Simulate a session mutation (a future production/consumption step).
	state.stock[state.stock_first[1]].amount = 0
	state.stock[state.stock_first[1]+1].amount = 40
	state.stock[state.stock_first[1]+2].amount = 0
	reset(&state,r.initial[:])
	stock := stock_snapshot(&state,1)
	testing.expect(t,stock[0].amount == f64(12.5) && stock[1].amount == f64(4) && stock[2].amount == f64(200))
	testing.expect(t,r.initial[1].stored[1].amount == 12.5)
}

// The snapshot is a borrow of authoritative session storage, so a value captured
// before a reset observes the restored amount. It is invalidated by the next
// mutation rather than copied.
@(test)
stock_snapshot_is_a_borrowed_view_of_the_session :: proc(t: ^testing.T) {
	r: Stock_Test
	stock_test_setup(&r)
	state := new_session(r.initial[:],r.definitions[:],context.allocator)
	defer destroy(&state,context.allocator)

	stock := stock_snapshot(&state,1)
	state.stock[state.stock_first[1]].amount = 0
	reset(&state,r.initial[:])
	testing.expect(t,stock[0].amount == f64(12.5))
	// Resolved capacities are fixed for the session and never re-derived by reset.
	testing.expect(t,stock[0].capacity == 100)
}

@(test)
stock_arrays_are_freed_by_destroy_and_reset_allocates_nothing :: proc(t: ^testing.T) {
	backing := context.allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track,backing)
	track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	r: Stock_Test
	stock_test_setup(&r)
	state := new_session(r.initial[:],r.definitions[:],allocator)
	built := len(track.allocation_map)
	reset(&state,r.initial[:])
	testing.expectf(t,len(track.allocation_map) == built,"reset allocated %d new block(s)",len(track.allocation_map)-built)
	destroy(&state,allocator)
	leaks := 0
	for _, entry in track.allocation_map {
		_ = entry
		leaks += 1
	}
	testing.expectf(t,leaks == 0,"%d stock allocation(s) survived destroy",leaks)
	testing.expect(t,len(track.bad_free_array) == 0)
}

// The session asserts the same fixed bound startup validation enforces; the shared
// count must therefore agree with the materialized layout.
@(test)
stock_entry_count_matches_the_materialized_table :: proc(t: ^testing.T) {
	r: Stock_Test
	stock_test_setup(&r)
	state := new_session(r.initial[:],r.definitions[:],context.allocator)
	defer destroy(&state,context.allocator)
	testing.expect(t,len(state.stock) == stock_entry_count(r.initial[:],r.definitions[:]))
	testing.expect(t,len(state.stock) <= STOCK_ENTRY_LIMIT && state.stock_first[len(state.buildings)] == len(state.stock))
}
