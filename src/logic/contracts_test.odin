package logic

import "core:testing"
import c "../contracts"

// Task 2 contract regressions: snapshots are independent values and event payloads
// carry stable IDs, in a deterministic delivery order.

@(test)
subject_view_is_an_independent_value :: proc(t: ^testing.T) {
	needs := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=6, shortage_max_time=72, satisfied_health_gain_per_hour=0.001, max_shortage_health_loss_per_hour=0.025}}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,needs[:])
	defer health_fixture_destroy(&r)
	subject := health_fixture_subject(&r,0.75,.Working)
	subject.assignment = c.Shift_Assignment{building_id="GH1", role_id=.worker, slot_index=2}
	subject.medical = .Pending_Evacuation
	id := subject.id

	view, found := subject_view(&r.state,id)
	testing.expect(t,found)
	testing.expect(t,view.id == id && view.subject_id == "human" && view.health == 0.75)
	testing.expect(t,view.work_phase == .Working && view.medical == .Pending_Evacuation)
	testing.expect(t,view.need_count == 1 && view.needs[0].resource_id == "water" && view.needs[0].fulfillment == 1)
	assigned, has_assignment := view.assignment.?
	testing.expect(t,has_assignment && assigned.building_id == "GH1" && assigned.role_id == .worker && assigned.slot_index == 2)

	// Mutating the returned copy must not touch authoritative state.
	view.health = 0
	view.subject_id = "robot"
	view.work_phase = .Idle
	view.medical = .None
	view.assignment = nil
	view.need_count = 0
	view.needs[0].resource_id = "meals"
	view.needs[0].fulfillment = 0
	view.needs[0].shortage_hours = 99

	again, found_again := subject_view(&r.state,id)
	testing.expect(t,found_again)
	testing.expect(t,again.health == 0.75 && again.subject_id == "human")
	testing.expect(t,again.work_phase == .Working && again.medical == .Pending_Evacuation)
	testing.expect(t,again.need_count == 1 && again.needs[0].resource_id == "water")
	testing.expect(t,again.needs[0].fulfillment == 1 && again.needs[0].shortage_hours == 0)
	assigned_again, has_assignment_again := again.assignment.?
	testing.expect(t,has_assignment_again && assigned_again == c.Shift_Assignment{building_id="GH1", role_id=.worker, slot_index=2})
	// The legacy logic snapshot is also a value copy.
	copied, _ := subject_snapshot(&r.state,id)
	copied.health = 0
	testing.expect(t,r.state.subjects[0].health == 0.75)
	// Unknown and removed subjects are not exposed.
	_, unknown := subject_view(&r.state,c.Subject_ID(999))
	testing.expect(t,!unknown,"unknown IDs are rejected")
}

@(test)
event_queue_delivers_stable_ids_in_order :: proc(t: ^testing.T) {
	queue: Event_Queue
	testing.expect(t,len(pending_events(&queue)) == 0)
	testing.expect(t,push_event(&queue,.Staffing_Lost,"GH1"))
	testing.expect(t,push_event(&queue,.Medical_Evacuation,"",c.Subject_ID(42)))
	testing.expect(t,push_event(&queue,.Subject_Died,"",c.Subject_ID(7)))
	events := pending_events(&queue)
	testing.expect(t,len(events) == 3)
	testing.expect(t,events[0].kind == .Staffing_Lost && events[0].building_id == "GH1" && events[0].subject_id == 0)
	testing.expect(t,events[1].kind == .Medical_Evacuation && events[1].building_id == "" && events[1].subject_id == 42)
	testing.expect(t,events[2].kind == .Subject_Died && events[2].subject_id == 7)
	testing.expect(t,events[0].sequence == 1 && events[1].sequence == 2 && events[2].sequence == 3)
	clear_events(&queue)
	testing.expect(t,len(pending_events(&queue)) == 0)
	// Sequence numbers stay monotonic across clears.
	testing.expect(t,push_event(&queue,.Staffing_Restored,"GH1"))
	testing.expect(t,pending_events(&queue)[0].sequence == 4)
	clear_events(&queue)
}

@(test)
event_queue_overflow_is_explicit :: proc(t: ^testing.T) {
	queue: Event_Queue
	for i in 0..<EVENT_LIMIT { testing.expect(t,push_event(&queue,.Medical_Return,"",c.Subject_ID(u64(i)+1))) }
	testing.expect(t,queue.overflowed == 0)
	testing.expect(t,!push_event(&queue,.Subject_Died,"",c.Subject_ID(999)))
	testing.expect(t,queue.overflowed == 1)
	events := pending_events(&queue)
	testing.expect(t,len(events) == EVENT_LIMIT)
	// Existing transitions are preserved: the newest event is the one rejected.
	testing.expect(t,events[0].subject_id == 1 && events[EVENT_LIMIT-1].subject_id == EVENT_LIMIT)
	clear_events(&queue)
	testing.expect(t,queue.overflowed == 1, "overflow accounting survives a clear")
}

@(test)
building_snapshot_is_an_independent_value :: proc(t: ^testing.T) {
	definitions := [?]Building_Type{{id="control_unit"}}
	initial := [?]Building_Instance{{id="CU1", building_id="control_unit", health=1}}
	state := new_session(initial[:],definitions[:],context.allocator)
	defer destroy(&state,context.allocator)
	view := snapshot(&state,0)
	view.id = "changed"
	view.health = 0
	view.active = false
	view.level = 0
	view.power_output_kw = 999
	fresh := snapshot(&state,0)
	testing.expect(t,fresh.id == "CU1" && fresh.health == 1 && fresh.active)
	testing.expect(t,fresh.level == 1 && fresh.power_output_kw == state.power[0].output_kw)
}
