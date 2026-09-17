package logic

import c "../contracts"

// Bounded, allocation-free edge-triggered event log owned by the session State.
// Logic appends one event when a transition happens; the application consumes the
// pending view in ascending sequence order. Delivery order is therefore the order
// in which transitions occurred during the fixed tick.
//
// Overflow: when the log is full the newest event is rejected and `overflowed`
// increments. Already-queued transitions are preserved, and the drop stays
// observable instead of silent. Capacity is a session constant; a later slice
// revisits explicit limits. `overflowed` is cumulative and survives clear_events.
EVENT_LIMIT :: 128
Event_Queue :: struct {
	events: [EVENT_LIMIT]c.Sim_Event,
	count: int,
	next_sequence: u64,
	overflowed: u64,
}

// Appends one event and reports whether it fit. building_id must borrow validated
// catalog/level storage that lives for the whole session.
push_event :: proc(queue: ^Event_Queue, kind: c.Sim_Event_Kind, building_id: string = "", subject_id: c.Subject_ID = 0) -> bool {
	if queue.count >= EVENT_LIMIT {
		queue.overflowed += 1
		return false
	}
	queue.next_sequence += 1
	queue.events[queue.count] = {sequence=queue.next_sequence, kind=kind, building_id=building_id, subject_id=subject_id}
	queue.count += 1
	return true
}

// Read-only pending events in delivery order. The slice borrows queue storage and
// is invalidated by the next push or clear.
pending_events :: proc(queue: ^Event_Queue) -> []c.Sim_Event {
	return queue.events[:queue.count]
}

// Removes every pending event. Cumulative overflow accounting is preserved.
clear_events :: proc(queue: ^Event_Queue) {
	queue.count = 0
}
