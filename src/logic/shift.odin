package logic

// Shift lifecycle: rest, work and overtime timers, the work trip, and the physical
// handoff. The scheduler (task 6) chooses and reserves; this step advances the
// authoritative lifecycle and commits arrivals.
//
// Fixed-tick order in the application:
//   health -> step_shifts -> transport movement -> commit_shift_handoffs ->
//   derive_staffing -> schedule_staffing
// Timers and phase transitions therefore run before movement, and the handoff runs
// after movement but before coverage is derived, so consecutive shifts never show an
// uncovered tick.
//
// Reservation, physical presence and work phase stay orthogonal: a reserved subject
// may still be resting or already travelling, a travelling subject does not cover a
// physical slot yet, and only an arrived, eligible, assigned subject covers a slot.
// Movement itself is owned by step_subjects; the lifecycle only sets the work target.

// Fixed-tick timer tolerance: floating-point accumulation over many ticks must not
// delay a threshold by a tick.
@(private)
SHIFT_TIME_EPSILON :: f64(1e-9)

// Advances rest, work and overtime timers by one fixed tick and performs the
// non-movement phase transitions:
//   Resting        accrues rest; on completion it travels to the reserved building or
//                  becomes Idle, where inactivity starts immediately.
//   Reserved       rest already complete: starts the work trip immediately.
//   Idle           accrues inactivity time.
//   Working        accrues work; at work_time it enters Extra_Working.
//   Extra_Working  accrues overtime; at work_time + extra_work_time it leaves the
//                  slot even without a replacement and rests where it is.
// Moving_To_Work subjects are advanced by step_transports; arrivals are committed by
// commit_shift_handoffs. Health, medical and evacuation ineligibility is released by
// derive_staffing in the same tick.
step_shifts :: proc(state: ^State, fleet: ^Transport_State) {
	for &subject in fleet.subjects {
		if subject.activity == .Removed { continue }
		definition, found := find_subject_type(fleet,subject.subject_id)
		if !found { continue }
		switch subject.phase {
		case .Resting:
			subject.rest_hours += TICK_HOURS
			if subject.rest_hours >= f64(definition.rest_time)-SHIFT_TIME_EPSILON {
				subject.rest_hours = f64(definition.rest_time)
				if subject.reservation != nil {
					start_work_travel(state,&subject)
				} else {
					subject.phase = .Idle
					subject.idle_hours = 0
				}
			}
		case .Idle:
			subject.idle_hours += TICK_HOURS
		case .Reserved:
			if subject.reservation != nil {
				start_work_travel(state,&subject)
			} else {
				subject.phase = .Idle
			}
		case .Moving_To_Work:
			// Movement and arrival are handled after this step.
		case .Working:
			subject.work_hours += TICK_HOURS
			if subject.work_hours >= f64(definition.work_time)-SHIFT_TIME_EPSILON { subject.phase = .Extra_Working }
		case .Extra_Working:
			subject.work_hours += TICK_HOURS
			if subject.work_hours >= f64(definition.work_time)+f64(definition.extra_work_time)-SHIFT_TIME_EPSILON {
				release_subject_assignment(&subject)
			}
		}
	}
}

// Starts the trip to the reserved building: the subject walks there with the normal
// movement step and is committed by commit_shift_handoffs on arrival. Reservation
// waiting after rest and travel to work are health-neutral (see the health step).
@(private)
start_work_travel :: proc(state: ^State, subject: ^Runtime_Subject) {
	reservation, has_reservation := subject.reservation.?
	if !has_reservation {
		subject.phase = .Idle
		return
	}
	for building in state.buildings {
		if building.id != reservation.building_id { continue }
		subject.phase = .Moving_To_Work
		subject.destination = building.id
		subject.target = building.position
		subject.activity = .Moving
		subject.wait_hours = 0
		return
	}
	// A reservation for a building outside the session is stale; derive_staffing
	// cancels it and the subject stays unassigned.
	subject.phase = .Idle
}

// Commits the physical handoff for every reserved subject that has arrived at its
// reserved building. The incumbent is released and the replacement takes the slot in
// the same step, before the next derive_staffing, so coverage never observes an
// uncovered tick. A released incumbent starts required rest where it stands. An
// absent replacement simply leaves the slot open for the scheduler.
commit_shift_handoffs :: proc(state: ^State, fleet: ^Transport_State) {
	for &subject, index in fleet.subjects {
		reservation, has_reservation := subject.reservation.?
		if !has_reservation || subject.phase != .Moving_To_Work { continue }
		// Physically arrived: step_subjects parks an arrived walker `.Inside` at the
		// destination.
		if subject.activity != .Inside || subject.destination != reservation.building_id { continue }
		definition, found := find_subject_type(fleet,subject.subject_id)
		if !found { continue }
		if !staffing_subject_eligible(&subject,definition,reservation.role_id) { continue }
		table, ok := staffing_slot_lookup(state,reservation)
		if !ok { continue }
		slot := &state.staffing.slots[table]
		if !state.active[slot.building_index] { continue }
		if slot.reserved.id != 0 && slot.reserved.id != subject.id { continue }
		// Atomic handoff: the incumbent leaves before the replacement is recorded, and
		// both happen in this step.
		if slot.occupant.id != 0 && slot.occupant.id != subject.id {
			if slot.occupant.index >= 0 && slot.occupant.index < len(fleet.subjects) {
				incumbent := &fleet.subjects[slot.occupant.index]
				if incumbent.id == slot.occupant.id { release_subject_assignment(incumbent) }
			}
		}
		release_subject_assignment(&subject)
		release_subject_reservation(&subject)
		subject.assignment = reservation
		subject.occupation = reservation.building_id
		subject.phase = .Working
		subject.work_hours = 0
		subject.idle_hours = 0
		slot.occupant = {index,subject.id}
		slot.reserved = {}
	}
}
