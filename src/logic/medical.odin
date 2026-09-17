package logic

import c "../contracts"

// Request and patient capacity. Requests and patients are not separate tables: each
// is per-subject state on Runtime_Subject, so the hard bound is the individual array
// itself. A live subject has at most one medical request and one patient state, so
// these aliases make the overflow contract explicit without adding storage.
MEDICAL_REQUEST_LIMIT :: SUBJECT_LIMIT
PATIENT_LIMIT :: SUBJECT_LIMIT

// Medical evacuation and death (roadmap task 8).
//
// An individual whose health reaches its type's `min_colony_health` requests
// medical evacuation exactly once. The request is per-subject authoritative state
// (`Runtime_Subject.medical`): at most one per live subject and therefore bounded by
// SUBJECT_LIMIT. There is no separate request table, so a request can never overflow
// and no person is silently dropped. On creation the subject immediately releases its
// staffing slot and reservation, becomes ineligible for scheduling
// (`staffing_subject_eligible` rejects any non-`.None` medical state) and walks to
// the first active landing platform using the existing individual movement rules.
// Health keeps evolving while the request is pending; needs keep applying and are
// not paused by the evacuation.
//
// At health zero, anywhere in the lifecycle and independent of the medical state,
// the subject is permanently removed. Removal releases staffing claims, detaches the
// person from transport manifests and residence/station population counters without
// duplicating anyone, and emits exactly one Subject_Died event. A removed person can
// never recover or be discharged.
//
// Ownership, mutability and lifetime
// ----------------------------------
// All state belongs to the session (`State.events` and `Transport_State`). The
// subject records, manifests and population counters are mutated in place; strings
// borrow validated level/catalog storage for the whole session. Every procedure is
// headless and the steady state allocates nothing. Removing one passenger rebuilds
// that mission's manifest (a rare event, not a per-tick path); the replaced
// allocation is freed immediately, and `delete` then always sees the true
// allocation length.
//
// Delivery order and limits
// -------------------------
// `step_medical` runs once per fixed tick, immediately after `step_subject_health`
// and before the shift/movement steps, so death removal (fixed-tick step 4) is
// delivered before medical requests (step 5) of the same tick and both follow
// ascending runtime subject order. Events use the shared bounded Event_Queue
// (EVENT_LIMIT events, newest rejected on overflow, `overflowed` observable).

// Runs the medical phase of the fixed tick. See the file header for ordering.
step_medical :: proc(state: ^State, fleet: ^Transport_State) {
	remove_dead_subjects(state, fleet)
	request_medical_evacuations(state, fleet)
	request_medical_returns(state, fleet)
}

// A physically colony-side subject: only these can be ordered to a landing platform.
// Station stock and passengers still boarding or in flight are not redirected; they
// request evacuation once they are discharged into the colony.
@(private)
medical_subject_in_colony :: proc(subject: ^Runtime_Subject) -> bool {
	switch subject.activity {
	case .Inside, .Moving, .Waiting:
		return true
	case .Station, .Reserved, .Onboard, .Removed:
		return false
	}
	return false
}

// True when the subject's recorded platform still exists, is a landing platform and
// is active. A missing or disabled platform makes the walk order stale and the
// request retries against a currently active platform.
@(private)
active_medical_platform :: proc(state: ^State, subject: ^Runtime_Subject) -> bool {
	return landing_platform_active(state,subject.evacuation_platform)
}

// Orders one patient to the first active landing platform in building order, using
// the same movement fields and single-file spacing as residence evacuation. With no
// active platform the subject stays safely where it is and the request retries next
// tick; the stable `evacuation_platform` anchor is only overwritten by a call that
// actually finds a platform.
@(private)
send_to_platform :: proc(state: ^State, fleet: ^Transport_State, subject: ^Runtime_Subject) {
	for building, i in state.buildings {
		if building.building_id != "landing_platform" || !state.active[i] { continue }
		subject.evacuation_platform = building.id
		subject.destination = building.id
		subject.target = building.position
		subject.activity = .Waiting
		subject.wait_hours = 0
		for &other in fleet.subjects {
			if other.id == subject.id || other.medical == .None { continue }
			if other.evacuation_platform != building.id { continue }
			if other.position != subject.position { continue }
			if other.activity == .Waiting {
				subject.wait_hours = max(subject.wait_hours,other.wait_hours+SUBJECT_LINE_SPACING/(SUBJECT_WALK_SPEED*f64(subject.speed)))
			}
		}
		return
	}
}

// Creates the single medical request for a subject that crossed the threshold:
// detaches it from ordinary residence evacuation, releases its work, records the
// pending status and emits exactly one evacuation event. Idempotent per subject
// because callers only enter for `medical == .None`.
@(private)
begin_medical_evacuation :: proc(state: ^State, fleet: ^Transport_State, subject: ^Runtime_Subject, index: int) {
	// A residence-evacuation seat would otherwise keep the person owned by the
	// ordinary transport; the emergency medical path takes over exclusively.
	if subject.evacuating || subject.evacuation_reserved {
		if subject.evacuation_reserved { detach_manifest_person(state, fleet, index) }
		subject.evacuating = false
		subject.evacuation_reserved = false
		subject.evacuation_platform = ""
	}
	release_subject_assignment(subject)
	release_subject_reservation(subject)
	subject.medical_home = subject.residence
	subject.medical = .Pending_Evacuation
	send_to_platform(state, fleet, subject)
	push_event(&state.events,.Medical_Evacuation,subject_id=subject.id)
}

// Creates requests for every live colony subject that reached `min_colony_health`,
// at most once each, and retries the platform walk of pending patients whose platform
// is unavailable. Deterministic: runtime subject order.
@(private)
request_medical_evacuations :: proc(state: ^State, fleet: ^Transport_State) {
	for &subject, index in fleet.subjects {
		if subject.activity == .Removed { continue }
		if subject.medical != .None {
			// A patient already holding an emergency seat is re-targeted only by
			// reconcile_medical_missions, which also moves the committed mission; this
			// keeps a ship already landing from being separated from its manifest.
			if subject.medical == .Pending_Evacuation &&
			   !subject.medical_reserved &&
			   medical_subject_in_colony(&subject) &&
			   !active_medical_platform(state,&subject) {
				send_to_platform(state,fleet,&subject)
			}
			continue
		}
		if !medical_subject_in_colony(&subject) { continue }
		definition, found := find_subject_type(fleet,subject.subject_id)
		if !found { continue }
		if subject.health > definition.min_colony_health { continue }
		begin_medical_evacuation(state,fleet,&subject,index)
	}
}

// Requests the return of every recovered hospital patient. A patient becomes
// available for a return only after reaching `min_work_health`; the return leg itself
// is batched by dispatch_medical_returns, which also sets `medical_reserved`. This
// never touches station stock and is idempotent because `.Hospitalized` is left
// behind on the first request.
@(private)
request_medical_returns :: proc(state: ^State, fleet: ^Transport_State) {
	for &subject in fleet.subjects {
		if subject.activity == .Removed { continue }
		if subject.medical != .Hospitalized { continue }
		definition, found := find_subject_type(fleet,subject.subject_id)
		if !found { continue }
		if subject.health < definition.min_work_health { continue }
		subject.medical = .Returning
	}
}

// Permanently removes every live subject at zero health. One death event per person,
// in ascending runtime subject order.
@(private)
remove_dead_subjects :: proc(state: ^State, fleet: ^Transport_State) {
	for &subject, index in fleet.subjects {
		if subject.activity == .Removed || subject.health > 0 { continue }
		id := subject.id
		reconcile_death(state,fleet,index)
		push_event(&state.events,.Subject_Died,subject_id=id)
	}
}

// Reconciles one death against every state that can own a person: staffing,
// transport manifests, residence occupancy and station stock. Exactly one of those
// owns the subject at a time, so population is reduced by one with no duplication.
@(private)
reconcile_death :: proc(state: ^State, fleet: ^Transport_State, index: int) {
	subject := &fleet.subjects[index]
	release_subject_assignment(subject)
	release_subject_reservation(subject)
	// Any mission that owns a seat, boarded or only reserved, must drop the person
	// before the physical owner is reconciled. detach_manifest_person is a no-op when
	// no manifest references the individual.
	if subject.activity == .Reserved || subject.activity == .Onboard || subject.medical_reserved || subject.evacuation_reserved {
		detach_manifest_person(state,fleet,index)
	}
	switch subject.activity {
	case .Reserved, .Onboard:
		// Manifest ownership already reconciled above.
	case .Inside, .Moving, .Waiting:
		// Colony resident: residence occupancy counts the individual.
		release_residence_population(state,fleet,subject)
	case .Station:
		// Identified station patients, hospitalized or waiting to return, are not
		// anonymous stock units.
		if subject.medical == .None { release_station_population(fleet,subject) }
	case .Removed:
	}
	subject.evacuating = false
	subject.evacuation_reserved = false
	subject.evacuation_platform = ""
	subject.medical = .None
	subject.medical_home = ""
	subject.residence = ""
	subject.destination = ""
	subject.occupation = ""
	subject.position = {}
	subject.target = {}
	subject.wait_hours = 0
	subject.activity = .Removed
}

// Removes one individual from the manifest that owns it and corrects the mission
// counters. A new manifest allocation replaces the old one (freed immediately) so
// `delete` always sees the true allocation length; deaths are rare and this is not a
// per-tick path. An ordinary mission also drops the destination reservation of the
// undelivered passenger; already delivered passengers are never touched.
@(private)
detach_manifest_person :: proc(state: ^State, fleet: ^Transport_State, index: int) {
	for &mission in fleet.missions[:fleet.count] {
		position := -1
		for i in 0..<len(mission.manifest) {
			if mission.manifest[i] == index { position = i; break }
		}
		if position < 0 { continue }
		if len(mission.manifest) > 1 {
			replacement := make([]int,len(mission.manifest)-1,fleet.allocator)
			copy(replacement,mission.manifest[:position])
			copy(replacement[position:],mission.manifest[position+1:])
			delete(mission.manifest,fleet.allocator)
			mission.manifest = replacement
		} else {
			delete(mission.manifest,fleet.allocator)
			mission.manifest = nil
		}
		mission.units = max(f32(0),mission.units-1)
		if position < int(mission.loaded) { mission.loaded = max(f32(0),mission.loaded-1) }
		if !mission.evacuation && !mission.medical && f32(position) >= mission.delivered && mission.requested > 0 {
			mission.requested = max(f32(0),mission.requested-1)
			release_building_reservation(state,fleet,mission.destination,1)
		}
		return
	}
}

// Drops one reserved unit from a colony building; unknown IDs change nothing.
@(private)
release_building_reservation :: proc(state: ^State, fleet: ^Transport_State, building_id: string, amount: f32) {
	if amount <= 0 { return }
	for building, i in state.buildings {
		if building.id != building_id { continue }
		fleet.reserved[i] = max(f32(0),fleet.reserved[i]-amount)
		return
	}
}

// Removes one colony resident from its residence occupancy. The residents_amount
// cache mirrors the authoritative occupant count.
@(private)
release_residence_population :: proc(state: ^State, fleet: ^Transport_State, subject: ^Runtime_Subject) {
	for &building, i in state.buildings {
		if building.id != subject.residence { continue }
		if fleet.occupants[i] >= 1 {
			fleet.occupants[i] -= 1
			building.residents_amount = fleet.occupants[i]
		}
		return
	}
}

// Removes one station-stock unit of the subject's type.
@(private)
release_station_population :: proc(fleet: ^Transport_State, subject: ^Runtime_Subject) {
	for &stock in fleet.stock {
		if stock.subject_id != subject.subject_id { continue }
		if stock.units >= 1 { stock.units -= 1 }
		return
	}
}
