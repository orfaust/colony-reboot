package logic

import "core:testing"
import c "../contracts"

// Headless task-5 regressions: building operation under staffing loss. Every test
// runs without a renderer, window or GPU resource, uses no wall-clock time and no
// random seed.
//
// Fixture power categories (all start inactive except the Control Unit). Power
// attributes are mutually exclusive, so every type either produces or consumes:
//   0 CU1  control_unit, 0/0, no slots, always active
//   1 P1   producer 16/0, one continuous worker slot, warmup 0
//   2 C1   consumer 0/8, no slots
//   3 C2   consumer 0/9, no slots
//   4 K1   consumer_slots 0/3, one continuous worker slot
//   5 P2   producer 20/0, one continuous worker slot, warmup 2
//   6 W1   consumer 0/4, one continuous worker slot
//   7 G1   producer 12/0, no slots

Operation_Test :: struct {
	definitions: [8]Building_Type,
	initial: [8]Building_Instance,
	worker_slots: [1]Building_Subject_Role,
	role_definitions: [1]Subject_Role_Definition,
	subject_roles: [1]Subject_Role,
	human: [1]Subject_Type,
	game: State,
	fleet: Transport_State,
}

operation_test_init :: proc(r: ^Operation_Test) {
	r.worker_slots = {{role_id=.worker,quantity=1,staffing_mode=.continuous}}
	r.role_definitions = {{role_id=.worker}}
	r.subject_roles = {.worker}
	r.human = {{id="human",roles=r.role_definitions[:],work_time=12,rest_time=12,extra_work_time=4,
		min_work_health=0.4,min_colony_health=0.1,
		health_rates={work_gain_per_hour=0.002,rest_gain_per_hour=0.01,extra_work_loss_per_hour=0.025,
			max_inactivity_loss_per_hour=0.012,inactivity_max_time=72,station_recovery_per_hour=0.04}}}
	r.definitions = {
		{id="control_unit",always_on=true},
		{id="producer",power_output_kw=16,subject_roles=r.worker_slots[:]},
		{id="consumer",power_need_kw=8},
		{id="consumer2",power_need_kw=9},
		{id="consumer_slots",power_need_kw=3,subject_roles=r.worker_slots[:]},
		{id="producer2",power_output_kw=20,warmup_time=2,subject_roles=r.worker_slots[:]},
		{id="workshop_consumer",power_need_kw=4,subject_roles=r.worker_slots[:]},
		{id="generator",power_output_kw=12},
	}
	r.initial = {
		{id="CU1",building_id="control_unit",position={-2,0},health=1,enable_at_start=true},
		{id="P1",building_id="producer",position={2,0},health=1},
		{id="C1",building_id="consumer",position={0,2},health=1},
		{id="C2",building_id="consumer2",position={0,3},health=1},
		{id="K1",building_id="consumer_slots",position={4,0},health=1},
		{id="P2",building_id="producer2",position={6,0},health=1},
		{id="W1",building_id="workshop_consumer",position={-2,2},health=1},
		{id="G1",building_id="generator",position={-4,0},health=1},
	}
	r.game = new_session(r.initial[:],r.definitions[:],context.allocator)
	r.fleet = new_transports({},{},nil,r.initial[:],nil,context.allocator,r.definitions[:],r.human[:])
}

operation_test_destroy :: proc(r: ^Operation_Test) {
	destroy_transports(&r.fleet,context.allocator)
	destroy(&r.game,context.allocator)
}

// Places one worker physically at a building, eligible for the worker role.
operation_person :: proc(r: ^Operation_Test, building_id: string) -> int {
	position, target: c.Vector2
	for building in r.initial {
		if building.id == building_id { position = building.position; target = building.position; break }
	}
	index := add_runtime_subject(&r.fleet,{subject_id="human",roles=r.subject_roles[:],activity=.Inside,
		position=position,target=target,destination=building_id,health=1})
	assert(index >= 0)
	return index
}

// Records a physical assignment, as the future handoff step will.
operation_work :: proc(r: ^Operation_Test, index: int, building_id: string) {
	subject := &r.fleet.subjects[index]
	target := c.Shift_Assignment{building_id=building_id,role_id=.worker,slot_index=0}
	subject.assignment = target
	subject.phase = .Working
}

operation_test_ticks :: proc(r: ^Operation_Test, ticks: int) {
	for _ in 0..<ticks { step(&r.game) }
}

@(test)
unstaffed_enabled_producer_outputs_nothing_and_keeps_consuming :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	testing.expect(t,snapshot(&r.game,1).level == 1 && snapshot(&r.game,1).power_output_kw == 0)
	testing.expect(t,balance(&r.game).produced_kw == 0)
	// Missing personnel cannot power new load during the tick.
	testing.expect(t,toggle(&r.game,{id="C1"}) == .Insufficient_Power)
	// Staffing the producer restores its output at the already-reached level.
	worker := operation_person(&r,"P1")
	operation_work(&r,worker,"P1")
	derive_staffing(&r.game,&r.fleet)
	view := snapshot(&r.game,1)
	testing.expect(t,view.staffed && view.power_output_kw == 16 && view.power_need_kw == 0)
	testing.expect(t,toggle(&r.game,{id="C1"}) == .Applied)
	testing.expect(t,balance(&r.game).produced_kw == 16 && balance(&r.game).available_kw == 8)
	// A loss keeps the building enabled and energized, keeps full demand, but
	// produces nothing. Cooldown never starts.
	r.fleet.subjects[worker].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	view = snapshot(&r.game,1)
	testing.expect(t,view.active && view.energized && !view.staffed)
	testing.expect(t,view.level == 1,"staffing loss never advances or reverses cooldown")
	testing.expect(t,view.power_output_kw == 0 && view.power_need_kw == 0)
	net := balance(&r.game)
	testing.expect(t,net.produced_kw == 0 && net.consumed_kw == 8 && net.available_kw < 0)
	testing.expect(t,snapshot(&r.game,2).active,"a staffing loss never disables a consumer")
}

@(test)
warmup_and_cooldown_stay_tied_to_real_activation :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P2"}) == .Applied)
	operation_test_ticks(&r,60)
	testing.expect(t,abs(r.game.level[5]-0.5) < 1e-9 && snapshot(&r.game,5).power_output_kw == 0)
	worker := operation_person(&r,"P2")
	operation_work(&r,worker,"P2")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,abs(snapshot(&r.game,5).power_output_kw-10) < 1e-6,"output follows the current warmup level")
	// The ramp keeps rising while unstaffed; it is not a cooldown.
	r.fleet.subjects[worker].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	operation_test_ticks(&r,60)
	view := snapshot(&r.game,5)
	testing.expect(t,view.active && !view.staffed && view.level == 1 && view.power_output_kw == 0)
	// Coverage returns immediately at full output without a new warmup.
	replacement := operation_person(&r,"P2")
	operation_work(&r,replacement,"P2")
	derive_staffing(&r.game,&r.fleet)
	view = snapshot(&r.game,5)
	testing.expect(t,view.staffed && view.level == 1 && view.power_output_kw == 20)
}

@(test)
consumer_with_continuous_slots_keeps_demand_while_unstaffed :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	// K1 has a continuous slot: an uncovered consumer still needs external power and
	// keeps its full demand; only a producer's output is gated by staffing.
	testing.expect(t,toggle(&r.game,{id="K1"}) == .Insufficient_Power)
	testing.expect(t,!snapshot(&r.game,4).active)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	producer_worker := operation_person(&r,"P1")
	operation_work(&r,producer_worker,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,toggle(&r.game,{id="K1"}) == .Applied)
	view := snapshot(&r.game,4)
	testing.expect(t,view.active && !view.staffed && view.power_output_kw == 0 && view.power_need_kw == 3)
	// Staffing it changes neither activity nor demand: the gate never gates needs.
	consumer_worker := operation_person(&r,"K1")
	operation_work(&r,consumer_worker,"K1")
	derive_staffing(&r.game,&r.fleet)
	view = snapshot(&r.game,4)
	testing.expect(t,view.staffed && view.power_output_kw == 0 && view.power_need_kw == 3)
	// Losing its staffing leaves the demand untouched and never disables it.
	r.fleet.subjects[consumer_worker].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	view = snapshot(&r.game,4)
	testing.expect(t,view.active && !view.staffed && view.power_output_kw == 0 && view.power_need_kw == 3)
	testing.expect(t,r.game.level[4] == 1)
}

@(test)
power_cascade_blocks_new_load_until_coverage_returns :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	worker := operation_person(&r,"P1")
	operation_work(&r,worker,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,toggle(&r.game,{id="C1"}) == .Applied)
	testing.expect(t,balance(&r.game).available_kw == 8)
	// The generator loses coverage: its output cascades away, existing load stays.
	r.fleet.subjects[worker].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,balance(&r.game).available_kw == -8)
	testing.expect(t,snapshot(&r.game,2).active)
	// New load is refused while the cascade lasts; shedding load is still allowed.
	testing.expect(t,toggle(&r.game,{id="C2"}) == .Insufficient_Power)
	testing.expect(t,!snapshot(&r.game,3).active)
	testing.expect(t,toggle(&r.game,{id="C1"}) == .Applied)
	testing.expect(t,balance(&r.game).available_kw == 0)
	// Coverage returns: the network recovers without touching requested activity.
	replacement := operation_person(&r,"P1")
	operation_work(&r,replacement,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,balance(&r.game).available_kw == 16)
	testing.expect(t,toggle(&r.game,{id="C1"}) == .Applied)
	testing.expect(t,balance(&r.game).available_kw == 8)
	testing.expect(t,toggle(&r.game,{id="C2"}) == .Insufficient_Power,"8 kW free cannot cover a 9 kW load")
	// The generator lock outlives staffing loss.
	r.fleet.subjects[replacement].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Generator_Required)
	testing.expect(t,snapshot(&r.game,1).active)
}

@(test)
staffing_transitions_publish_one_edge_triggered_event_each :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	worker := operation_person(&r,"P1")
	operation_work(&r,worker,"P1")
	// The first derivation after a reset baselines; a session never reports every
	// building that simply starts unstaffed.
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,len(pending_events(&r.game.events)) == 0)
	testing.expect(t,snapshot(&r.game,1).staffed)
	// A real loss publishes exactly one event, and only once.
	r.fleet.subjects[worker].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	events := pending_events(&r.game.events)
	testing.expect(t,len(events) == 1 && events[0].kind == .Staffing_Lost)
	testing.expect(t,events[0].building_id == "P1" && events[0].subject_id == 0)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,len(pending_events(&r.game.events)) == 1,"re-derivation repeats nothing")
	// Restoration publishes exactly one matching event.
	replacement := operation_person(&r,"P1")
	operation_work(&r,replacement,"P1")
	derive_staffing(&r.game,&r.fleet)
	events = pending_events(&r.game.events)
	testing.expect(t,len(events) == 2 && events[1].kind == .Staffing_Restored)
	testing.expect(t,events[0].sequence < events[1].sequence && events[1].building_id == "P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,len(pending_events(&r.game.events)) == 2)
	// Enabling a building and staffing it for the first time is not a recovery
	// notice, because no loss was ever published for it.
	testing.expect(t,toggle(&r.game,{id="W1"}) == .Applied)
	shell := operation_person(&r,"W1")
	operation_work(&r,shell,"W1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,snapshot(&r.game,6).staffed)
	testing.expect(t,len(pending_events(&r.game.events)) == 2)
	// Disabling and re-enabling is a player command, not a staffing incident.
	testing.expect(t,toggle(&r.game,{id="W1"}) == .Applied)
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,!snapshot(&r.game,6).staffed)
	testing.expect(t,len(pending_events(&r.game.events)) == 2,"disabling is not a staffing loss")
	testing.expect(t,toggle(&r.game,{id="W1"}) == .Applied)
	again := operation_person(&r,"W1")
	operation_work(&r,again,"W1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,snapshot(&r.game,6).staffed)
	testing.expect(t,len(pending_events(&r.game.events)) == 2)
}

@(test)
same_tick_handoff_never_gates_a_nonzero_network :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	incumbent := operation_person(&r,"P1")
	operation_work(&r,incumbent,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,snapshot(&r.game,1).power_output_kw == 16)
	// Within one fixed tick the incumbent becomes ineligible while a replacement is
	// already physically present and assigned. The single tick-end derivation commits
	// the handoff, so coverage and output never dip and no loss is published.
	r.fleet.subjects[incumbent].health = 0.1
	replacement := operation_person(&r,"P1")
	operation_work(&r,replacement,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,snapshot(&r.game,1).staffed && snapshot(&r.game,1).power_output_kw == 16)
	// The fixture has no slots before P1, so P1's worker slot is table index 0.
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == r.fleet.subjects[replacement].id)
	testing.expect(t,r.fleet.subjects[incumbent].assignment == nil && r.fleet.subjects[incumbent].phase == .Resting)
	testing.expect(t,len(pending_events(&r.game.events)) == 0,"an atomic handoff publishes no loss")
}

@(test)
buildings_without_continuous_slots_are_never_gated :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="G1"}) == .Applied)
	testing.expect(t,snapshot(&r.game,7).staffed,"a building with no continuous slots is vacuously staffed")
	testing.expect(t,snapshot(&r.game,7).power_output_kw == 12)
	testing.expect(t,balance(&r.game).produced_kw == 12 && balance(&r.game).available_kw == 12)
	testing.expect(t,snapshot(&r.game,0).staffed && snapshot(&r.game,0).power_output_kw == 0)
}

@(test)
multiple_staffing_losses_publish_in_deterministic_building_order :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	testing.expect(t,toggle(&r.game,{id="P2"}) == .Applied)
	p1 := operation_person(&r,"P1")
	operation_work(&r,p1,"P1")
	p2 := operation_person(&r,"P2")
	operation_work(&r,p2,"P2")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,len(pending_events(&r.game.events)) == 0)
	r.fleet.subjects[p1].health = 0.1
	r.fleet.subjects[p2].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	events := pending_events(&r.game.events)
	testing.expect(t,len(events) == 2)
	testing.expect(t,events[0].kind == .Staffing_Lost && events[0].building_id == "P1")
	testing.expect(t,events[1].kind == .Staffing_Lost && events[1].building_id == "P2")
	testing.expect(t,events[0].sequence < events[1].sequence)
}

@(test)
same_tick_loss_and_restoration_publishes_both_events :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	worker := operation_person(&r,"P1")
	operation_work(&r,worker,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,balance(&r.game).produced_kw == 16)
	// Loss and restoration within one simulated tick: the last derivation is what
	// power evaluation reads, and each transition is still published exactly once.
	r.fleet.subjects[worker].health = 0.1
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,balance(&r.game).produced_kw == 0)
	replacement := operation_person(&r,"P1")
	operation_work(&r,replacement,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,balance(&r.game).produced_kw == 16)
	events := pending_events(&r.game.events)
	testing.expect(t,len(events) == 2)
	testing.expect(t,events[0].kind == .Staffing_Lost && events[1].kind == .Staffing_Restored)
	testing.expect(t,events[0].sequence < events[1].sequence)
}

@(test)
staffing_gate_follows_the_derived_state_within_one_tick :: proc(t: ^testing.T) {
	r: Operation_Test
	operation_test_init(&r)
	defer operation_test_destroy(&r)
	testing.expect(t,toggle(&r.game,{id="P1"}) == .Applied)
	producer_worker := operation_person(&r,"P1")
	operation_work(&r,producer_worker,"P1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,toggle(&r.game,{id="K1"}) == .Applied)
	consumer_worker := operation_person(&r,"K1")
	operation_work(&r,consumer_worker,"K1")
	derive_staffing(&r.game,&r.fleet)
	testing.expect(t,snapshot(&r.game,4).staffed && snapshot(&r.game,4).power_need_kw == 3)
	// A full app-order tick: health, transport/movement, then one staffing derivation;
	// snapshots and the balance read the post-derivation state.
	r.fleet.subjects[consumer_worker].health = 0.1
	step(&r.game)
	step_subject_health(&r.fleet)
	step_transports(&r.fleet,&r.game,r.definitions[:])
	derive_staffing(&r.game,&r.fleet)
	view := snapshot(&r.game,4)
	testing.expect(t,view.active && !view.staffed)
	testing.expect(t,view.power_output_kw == 0 && view.power_need_kw == 3)
	testing.expect(t,balance(&r.game).produced_kw == 16 && balance(&r.game).consumed_kw == 3)
	events := pending_events(&r.game.events)
	testing.expect(t,len(events) == 1 && events[0].kind == .Staffing_Lost && events[0].building_id == "K1")
}
