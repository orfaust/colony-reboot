package logic

import "core:mem"
import "core:testing"
import c "../contracts"

// Task-12 lifetime and limit regressions. The fixture builds the complete session
// (building state plus transport state) on a caller-supplied allocator, so a
// tracking allocator can prove every owned array and manifest is released by reset
// and destruction. Capacity overflow is checked explicitly: the runtime never grows
// past its fixed limit and a removed slot is reused instead of dropping anyone.

Lifetime_Test :: struct {
	definitions: [2]Building_Type,
	initial:     [2]Building_Instance,
	passengers:  [1]Ship_Subject,
	ships:       [1]Ship,
	units:       [1]Station_Ship,
	stock:       [1]Station_Subject_Stock,
	instance:    Station_Instance,
}

lifetime_test_setup :: proc(r: ^Lifetime_Test) {
	r.definitions = {{id="control_unit"},{id="home",residents={type="human",capacity=4}}}
	r.initial = {
		{id="CU",building_id="control_unit",health=1,enable_at_start=true},
		{id="H",building_id="home",health=1,enable_at_start=true,residents_amount=f32(0)},
	}
	r.passengers = {{subject_id="human",capacity=4}}
	r.ships = {{id="shuttle",type="transport",max_speed=3600,max_speed_hours=1,units_per_hour=4,subjects=r.passengers[:]}}
	r.units = {{ship_id="shuttle",units=1}}
	r.stock = {{subject_id="human",units=2,units_per_hour=0}}
	r.instance = {distance=100,subjects=r.stock[:]}
}

@(test)
session_owned_arrays_and_manifests_are_released_on_reset_and_destroy :: proc(t: ^testing.T) {
	backing := context.allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track,backing)
	track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	defer mem.tracking_allocator_destroy(&track)
	allocator := mem.tracking_allocator(&track)

	r: Lifetime_Test
	lifetime_test_setup(&r)
	game := new_session(r.initial[:],r.definitions[:],allocator)
	fleet := new_transports({ships=r.units[:]},r.instance,r.ships[:],r.initial[:],nil,allocator,r.definitions[:])

	// Dispatch an ordinary mission so a manifest allocation exists, then advance.
	dispatch_transports(&fleet,&game,r.definitions[:])
	testing.expect(t,fleet.count == 1)
	testing.expect(t,len(fleet.missions[0].manifest) == 2)
	for _ in 0..<3 { step(&game); step_transports(&fleet,&game,r.definitions[:]) }

	// Reset must free the manifest and rebuild the owned arrays without losing the
	// allocator contract; destruction then frees every remaining block.
	reset(&game,r.initial[:])
	reset_transports(&fleet,r.instance,r.initial[:],nil)
	testing.expect(t,fleet.count == 0)
	testing.expect(t,len(fleet.missions[0].manifest) == 0)
	destroy_transports(&fleet,allocator)
	destroy(&game,allocator)

	leaks := 0
	for _, entry in track.allocation_map {
		_ = entry
		leaks += 1
	}
	testing.expectf(t,leaks == 0,"%d allocation(s) survived reset/destroy",leaks)
	testing.expect(t,len(track.bad_free_array) == 0)
}

@(test)
subject_capacity_overflow_is_explicit_and_removed_slots_are_reused :: proc(t: ^testing.T) {
	fleet: Transport_State
	defer delete(fleet.subjects)
	for i in 0..<SUBJECT_LIMIT { append(&fleet.subjects,Runtime_Subject{id=c.Subject_ID(u64(i)+1)}) }
	testing.expect(t,len(fleet.subjects) == SUBJECT_LIMIT)
	// Full capacity is rejected explicitly (the caller sees -1) and never grows the
	// array or silently discards the new subject.
	testing.expect(t,add_runtime_subject(&fleet,{subject_id="human"}) == -1)
	testing.expect(t,len(fleet.subjects) == SUBJECT_LIMIT)
	// A removed slot is reused by fully overwriting the record: population is
	// conserved and no live subject is evicted.
	fleet.subjects[7].activity = .Removed
	index := add_runtime_subject(&fleet,{subject_id="human",health=0.5})
	testing.expect(t,index == 7)
	testing.expect(t,len(fleet.subjects) == SUBJECT_LIMIT)
	testing.expect(t,fleet.subjects[7].health == 0.5 && fleet.subjects[7].activity != .Removed)
}

// Medical requests and patients are per-subject state, so their capacity is the
// individual array itself; there is no separate table that can overflow.
@(test)
medical_request_capacity_is_bounded_by_the_subject_array :: proc(t: ^testing.T) {
	testing.expect(t,MEDICAL_REQUEST_LIMIT == SUBJECT_LIMIT)
	testing.expect(t,PATIENT_LIMIT == SUBJECT_LIMIT)
}
