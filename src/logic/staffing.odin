package logic

import "core:mem"
import c "../contracts"

// Continuous staffing slots are materialized once per session from every building
// type's integer `subject_roles` entries. `on_demand` entries stay validated
// metadata until a future explicit request system exists and never create an
// automatic slot.
//
// Capacity and overflow behavior
// ------------------------------
// STAFFING_SLOT_LIMIT bounds the session slot table. Startup validation
// (config.decode_level) rejects a level whose continuous slots exceed the limit
// with an actionable diagnostic, so materialization never truncates and no slot is
// silently dropped. new_session asserts the bound because it is a caller
// invariant, not malformed external data.
STAFFING_SLOT_LIMIT :: 1024

// One subject's claim on one slot. `id == 0` means no claim; Subject_ID values
// start at 1. `index` caches the subject's position in Transport_State.subjects and
// is only trusted while that subject still carries the recorded stable ID, so a
// reused array slot invalidates the cache instead of aliasing another person.
Staffing_Claim :: struct {
	index: int,
	id: c.Subject_ID,
}

// One materialized continuous slot. building_index, role_id and slot_index are
// stable for the whole session; every reset rebuilds identical slots from the same
// level template and catalog.
Staffing_Slot :: struct {
	building_index: int, // Index into State.buildings; buildings never reorder in a session.
	role_id: Subject_Role,
	slot_index: int, // Stable index within the building's role entry.
	occupant: Staffing_Claim, // Physically arrived eligible subject covering the slot.
	reserved: Staffing_Claim, // Scheduled replacement that has not arrived yet.
}

// Session-owned staffing state. The slices are allocated once by new_session and
// freed by destroy; reset only clears values, so it allocates nothing. Slot claims
// are a derived cache: derive_staffing rebuilds them from the authoritative
// Runtime_Subject assignment/reservation values in deterministic subject order.
Staffing :: struct {
	slots: []Staffing_Slot, // One per continuous slot, in materialization order.
	first_slot: []int, // len(buildings)+1; building b owns slots[first_slot[b]..first_slot[b+1]].
	staffed: []bool, // Per building: every continuous slot is physically covered.
	covered: []int, // Per building: physically covered continuous slots.
	reserved: []int, // Per building: reserved continuous slots.
	// Edge-triggered operation tracking. `tracked` is false until the first
	// derivation after a reset, so a new session publishes no staffing event for
	// buildings that simply start unstaffed. `lost_pending` records a published
	// Staffing_Lost that has not been matched by a Staffing_Restored yet, so a
	// recovery notice only follows a real loss.
	tracked: bool,
	previous_active: []bool,
	previous_staffed: []bool,
	lost_pending: []bool,
}

// Number of continuous slots a level template materializes: building order, then
// catalog role-entry order, then ascending slot_index. Used by startup validation
// before a session exists; unknown definitions contribute nothing.
continuous_slot_count :: proc(initial: []Building_Instance, definitions: []Building_Type) -> int {
	total := 0
	for building in initial {
		for definition in definitions {
			if definition.id != building.building_id { continue }
			for entry in definition.subject_roles {
				if entry.staffing_mode == .continuous { total += max(0,entry.quantity) }
			}
			break
		}
	}
	return total
}

// Continuous slot quantity a type exposes for one role. Role entries are unique
// per type, so at most one entry matches.
continuous_role_quantity :: proc(definition: Building_Type, role_id: Subject_Role) -> int {
	for entry in definition.subject_roles {
		if entry.role_id == role_id && entry.staffing_mode == .continuous { return max(0,entry.quantity) }
	}
	return 0
}

@(private)
materialize_staffing :: proc(staffing: ^Staffing, initial: []Building_Instance, definitions: []Building_Type, allocator: mem.Allocator) {
	count := continuous_slot_count(initial,definitions)
	staffing.slots = make([]Staffing_Slot,count,allocator)
	staffing.first_slot = make([]int,len(initial)+1,allocator)
	staffing.staffed = make([]bool,len(initial),allocator)
	staffing.covered = make([]int,len(initial),allocator)
	staffing.reserved = make([]int,len(initial),allocator)
	staffing.previous_active = make([]bool,len(initial),allocator)
	staffing.previous_staffed = make([]bool,len(initial),allocator)
	staffing.lost_pending = make([]bool,len(initial),allocator)
	next := 0
	for building, i in initial {
		staffing.first_slot[i] = next
		for definition in definitions {
			if definition.id != building.building_id { continue }
			for entry in definition.subject_roles {
				if entry.staffing_mode != .continuous { continue }
				for slot_index in 0..<max(0,entry.quantity) {
					staffing.slots[next] = {building_index=i,role_id=entry.role_id,slot_index=slot_index}
					next += 1
				}
			}
			break
		}
	}
	staffing.first_slot[len(initial)] = next
	// A building with no continuous slots is vacuously staffed; derive_staffing
	// updates every flag once subjects exist.
	for i in 0..<len(initial) { staffing.staffed[i] = staffing.first_slot[i] == staffing.first_slot[i+1] }
}

@(private)
destroy_staffing :: proc(staffing: ^Staffing, allocator: mem.Allocator) {
	delete(staffing.slots,allocator)
	delete(staffing.first_slot,allocator)
	delete(staffing.staffed,allocator)
	delete(staffing.covered,allocator)
	delete(staffing.reserved,allocator)
	delete(staffing.previous_active,allocator)
	delete(staffing.previous_staffed,allocator)
	delete(staffing.lost_pending,allocator)
	staffing^ = {}
}

// Drops every derived claim without touching the materialized slot table. Called
// by reset before the subjects are rebuilt, so a stale occupant can never survive
// into a new session. Transition tracking restarts, so the next derivation
// baselines instead of publishing events for the fresh session.
@(private)
clear_staffing_claims :: proc(staffing: ^Staffing) {
	for &slot in staffing.slots { slot.occupant = {}; slot.reserved = {} }
	for i in 0..<len(staffing.staffed) {
		staffing.covered[i] = 0
		staffing.reserved[i] = 0
		staffing.staffed[i] = staffing.first_slot[i] == staffing.first_slot[i+1]
		staffing.previous_active[i] = false
		staffing.previous_staffed[i] = false
		staffing.lost_pending[i] = false
	}
	staffing.tracked = false
}

// Continuous slots one building instance requires. Zero for unknown indices.
building_required_slots :: proc(state: ^State, building_index: int) -> int {
	if building_index < 0 || building_index+1 >= len(state.staffing.first_slot) { return 0 }
	return state.staffing.first_slot[building_index+1]-state.staffing.first_slot[building_index]
}

// True when every continuous slot of the building is physically covered. A
// building with no continuous slots is vacuously staffed. This is independent of
// the player-requested `active` state and never changes it.
building_staffed :: proc(state: ^State, building_index: int) -> bool {
	if building_index < 0 || building_index >= len(state.staffing.staffed) { return false }
	return state.staffing.staffed[building_index]
}

// True when the staffing gate suppresses this building's electrical output: the
// building is enabled but its continuous slots are not fully covered. Consumption is
// never gated this way, and a disabled (cooling) building is unaffected, so warmup,
// cooldown and the player's requested activity keep their existing meaning.
building_output_gated :: proc(state: ^State, building_index: int) -> bool {
	if building_index < 0 || building_index >= len(state.active) { return false }
	return state.active[building_index] && !building_staffed(state,building_index)
}

// Read-only materialized slot count. Slots are never added or removed during a
// session; only reset/reload rebuilds them from the level template.
staffing_slot_count :: proc(state: ^State) -> int {
	return len(state.staffing.slots)
}

// Read-only slot view. building_id borrows level storage; occupant/reserved are
// stable subject IDs (zero when unclaimed). Mutating the result changes nothing.
staffing_slot_snapshot :: proc(state: ^State, index: int) -> c.Staffing_Slot_Snapshot {
	assert(index >= 0 && index < len(state.staffing.slots))
	slot := state.staffing.slots[index]
	return {
		building_id = state.buildings[slot.building_index].id,
		role_id = slot.role_id,
		slot_index = slot.slot_index,
		occupant = slot.occupant.id,
		reserved = slot.reserved.id,
	}
}

// Coverage of one building role entry: required continuous slots, physically
// covered slots and reserved-but-not-arrived slots. Deterministic and bounded by
// the building's slot count.
staffing_coverage :: proc(state: ^State, building_index: int, role_id: Subject_Role) -> c.Staffing_Coverage {
	result := c.Staffing_Coverage{role_id=role_id}
	if building_index < 0 || building_index+1 >= len(state.staffing.first_slot) { return result }
	for i in state.staffing.first_slot[building_index]..<state.staffing.first_slot[building_index+1] {
		slot := state.staffing.slots[i]
		if slot.role_id != role_id { continue }
		result.required_slots += 1
		if slot.occupant.id != 0 { result.covered_slots += 1 }
		if slot.reserved.id != 0 { result.reserved_slots += 1 }
	}
	return result
}

// Resolves a shift assignment value to its materialized slot. Fails for unknown
// buildings, roles without a continuous slot and out-of-range slot indices, so a
// stale value can never be mistaken for another slot.
staffing_slot_lookup :: proc(state: ^State, assignment: c.Shift_Assignment) -> (int, bool) {
	if len(state.staffing.slots) == 0 { return 0,false }
	for building, i in state.buildings {
		if building.id != assignment.building_id { continue }
		for slot_index in state.staffing.first_slot[i]..<state.staffing.first_slot[i+1] {
			slot := state.staffing.slots[slot_index]
			if slot.role_id == assignment.role_id && slot.slot_index == assignment.slot_index { return slot_index,true }
		}
		return 0,false
	}
	return 0,false
}

// A candidate must be a live, healthy, non-medical, non-evacuating subject that
// supports the role. Health is compared against the type's min_work_health.
@(private)
staffing_subject_eligible :: proc(subject: ^Runtime_Subject, definition: Subject_Type, role_id: Subject_Role) -> bool {
	if subject.activity == .Removed || subject.evacuating || subject.medical != .None { return false }
	if subject.health < definition.min_work_health { return false }
	for role in subject.roles { if role == role_id { return true } }
	return false
}

// Physically in the colony: station stock and inbound/boarding people are never
// candidates before landing-platform discharge. `.Waiting` and `.Moving` are the
// colony-side landing walk; `.Reserved` is station boarding.
@(private)
staffing_subject_in_colony :: proc(subject: ^Runtime_Subject) -> bool {
	switch subject.activity {
	case .Inside, .Moving, .Waiting:
		return true
	case .Station, .Reserved, .Onboard, .Removed:
		return false
	}
	return false
}

// Physically arrived at the building: the subject is inside and its stable walking
// destination is that building. Movement itself stays in the transport step.
@(private)
staffing_subject_arrived :: proc(subject: ^Runtime_Subject, building_id: string) -> bool {
	return subject.activity == .Inside && subject.destination == building_id
}

// Clears a physical assignment. A working subject starts required rest where it
// stands and the inactivity clock restarts with the new rest cycle; other phases
// keep their current lifecycle state. `occupation` is the temporary inspector bridge
// derived from the assignment and is cleared with it.
@(private)
release_subject_assignment :: proc(subject: ^Runtime_Subject) {
	subject.assignment = nil
	subject.occupation = ""
	if subject.phase == .Working || subject.phase == .Extra_Working {
		subject.phase = .Resting
		subject.work_hours = 0
		subject.rest_hours = 0
		subject.idle_hours = 0
	}
}

// Clears a reservation. A rest-complete reserved subject becomes unassigned and
// inactive immediately; a subject still resting continues resting.
@(private)
release_subject_reservation :: proc(subject: ^Runtime_Subject) {
	subject.reservation = nil
	if subject.phase == .Reserved || subject.phase == .Moving_To_Work { subject.phase = .Idle }
}

// Rebuilds the derived slot claims and per-building coverage from the
// authoritative subject assignment/reservation values. Deterministic and
// allocation-free.
//
// A claim survives only when it names a materialized continuous slot, the building
// is enabled, the subject is a live, healthy, non-medical, non-evacuating colony
// resident supporting the role, and (for an occupant) the subject has physically
// arrived and is in a work phase. Invalid claims are released; no subject is ever
// removed or silently dropped. Two subjects can never claim one slot: occupancy and
// reservation are independent, so a scheduled replacement may hold the reservation
// of a slot an incumbent still covers, but two subjects can never both cover or both
// reserve it. Conflicts are resolved in favour of the lower stable Subject_ID,
// independent of array order. Call once per fixed tick after movement and after any
// reset or command.
derive_staffing :: proc(state: ^State, fleet: ^Transport_State) {
	for &slot in state.staffing.slots { slot.occupant = {}; slot.reserved = {} }
	for i in 0..<len(state.staffing.staffed) { state.staffing.covered[i] = 0; state.staffing.reserved[i] = 0 }
	for &subject, index in fleet.subjects {
		if subject.activity == .Removed {
			release_subject_assignment(&subject)
			release_subject_reservation(&subject)
			continue
		}
		definition, found := find_subject_type(fleet,subject.subject_id)
		if !found {
			release_subject_assignment(&subject)
			release_subject_reservation(&subject)
			continue
		}
		// A physical assignment wins over a reservation: one subject is never both
		// covering a slot and scheduled elsewhere.
		if assignment, has_assignment := subject.assignment.?; has_assignment {
			claimed := false
			if table, ok := staffing_slot_lookup(state,assignment); ok {
				slot := &state.staffing.slots[table]
				if state.active[slot.building_index] &&
				   staffing_subject_eligible(&subject,definition,slot.role_id) &&
				   staffing_subject_arrived(&subject,assignment.building_id) &&
				   (subject.phase == .Working || subject.phase == .Extra_Working) {
					switch {
					case slot.occupant.id == 0:
						slot.occupant = {index,subject.id}
						claimed = true
					case subject.id < slot.occupant.id:
						// Stable-ID priority: the lower ID keeps the slot even when it
						// appears later in the array (for example after a removed slot
						// was reused by a newer subject).
						previous := &fleet.subjects[slot.occupant.index]
						if previous.id == slot.occupant.id { release_subject_assignment(previous) }
						slot.occupant = {index,subject.id}
						claimed = true
					}
				}
			}
			if !claimed { release_subject_assignment(&subject) }
		}
		if reservation, has_reservation := subject.reservation.?; has_reservation {
			claimed := false
			if subject.assignment == nil && staffing_subject_in_colony(&subject) &&
			   staffing_subject_eligible(&subject,definition,reservation.role_id) {
				if table, ok := staffing_slot_lookup(state,reservation); ok {
					slot := &state.staffing.slots[table]
					// A reservation is independent of the occupant: the scheduler may
					// pre-claim the slot an incumbent still covers for the coming handoff.
					if state.active[slot.building_index] {
						switch {
						case slot.reserved.id == 0:
							slot.reserved = {index,subject.id}
							claimed = true
						case subject.id < slot.reserved.id:
							previous := &fleet.subjects[slot.reserved.index]
							if previous.id == slot.reserved.id { release_subject_reservation(previous) }
							slot.reserved = {index,subject.id}
							claimed = true
						}
					}
				}
			}
			if !claimed {
				release_subject_reservation(&subject)
			} else if subject.phase == .Idle {
				// Reservation waiting after completed rest is health-neutral.
				subject.phase = .Reserved
			}
		}
	}
	for slot in state.staffing.slots {
		if slot.occupant.id != 0 { state.staffing.covered[slot.building_index] += 1 }
		if slot.reserved.id != 0 { state.staffing.reserved[slot.building_index] += 1 }
	}
	for i in 0..<len(state.staffing.staffed) {
		state.staffing.staffed[i] = state.staffing.covered[i] == building_required_slots(state,i)
	}
	publish_staffing_transitions(state)
}

// Edge-triggered coverage transitions for enabled buildings. Disabling or enabling
// a building is a player command, not a staffing incident, so events require the
// building to stay enabled across the derivation. The first derivation after a
// reset baselines without events, and a Staffing_Restored is only published after a
// Staffing_Lost that has not yet been matched. Events are appended in building
// order; queue capacity and overflow follow Event_Queue.
@(private)
publish_staffing_transitions :: proc(state: ^State) {
	for i in 0..<len(state.staffing.staffed) {
		if state.staffing.tracked && state.staffing.previous_active[i] && state.active[i] {
			if state.staffing.previous_staffed[i] && !state.staffing.staffed[i] {
				push_event(&state.events,.Staffing_Lost,state.buildings[i].id)
				state.staffing.lost_pending[i] = true
			} else if !state.staffing.previous_staffed[i] && state.staffing.staffed[i] && state.staffing.lost_pending[i] {
				push_event(&state.events,.Staffing_Restored,state.buildings[i].id)
				state.staffing.lost_pending[i] = false
			}
		}
		state.staffing.previous_active[i] = state.active[i]
		state.staffing.previous_staffed[i] = state.staffing.staffed[i]
	}
	state.staffing.tracked = true
}

// Clears both claims of one subject and rebuilds the derived cache. Other
// subjects keep their claims. Unknown indices change nothing.
release_subject_staffing :: proc(state: ^State, fleet: ^Transport_State, subject_index: int) {
	if subject_index < 0 || subject_index >= len(fleet.subjects) { return }
	subject := &fleet.subjects[subject_index]
	release_subject_assignment(subject)
	release_subject_reservation(subject)
	derive_staffing(state,fleet)
}

// Records an exclusive reservation for a future shift without moving the subject.
// Fails without mutation when the subject is deleted, at the station or onboard, in
// a medical/evacuation state, unhealthy, lacking the role, already assigned or
// reserved, or when the target slot is missing, disabled or already reserved. The
// occupant may still be covering the slot: the reservation is the scheduled
// replacement, and the physical handoff later releases the incumbent. The scheduler
// owns rest forecasting and travel; this records the claim and switches a
// rest-complete idle subject to the health-neutral reserved phase.
reserve_staffing_slot :: proc(state: ^State, fleet: ^Transport_State, subject_index: int, target: c.Shift_Assignment) -> bool {
	if subject_index < 0 || subject_index >= len(fleet.subjects) { return false }
	subject := &fleet.subjects[subject_index]
	if existing, has_reservation := subject.reservation.?; has_reservation {
		return existing == target
	}
	if subject.assignment != nil { return false }
	definition, found := find_subject_type(fleet,subject.subject_id)
	if !found { return false }
	if !staffing_subject_in_colony(subject) { return false }
	if !staffing_subject_eligible(subject,definition,target.role_id) { return false }
	table, ok := staffing_slot_lookup(state,target)
	if !ok { return false }
	slot := &state.staffing.slots[table]
	if !state.active[slot.building_index] || slot.reserved.id != 0 { return false }
	subject.reservation = target
	if subject.phase == .Idle { subject.phase = .Reserved }
	slot.reserved = {subject_index,subject.id}
	return true
}

// Records a physical assignment: the subject must already be inside and arrived at
// the target building, eligible and healthy. Any previous claim is released, the
// subject starts work at hour zero, and the derived cache is rebuilt. Fails without
// mutation for a missing/disabled/occupied slot or an ineligible or absent
// subject. The physical handoff that swaps an incumbent for a replacement is
// composed from this call and release_subject_staffing.
assign_staffing_slot :: proc(state: ^State, fleet: ^Transport_State, subject_index: int, target: c.Shift_Assignment) -> bool {
	if subject_index < 0 || subject_index >= len(fleet.subjects) { return false }
	subject := &fleet.subjects[subject_index]
	if subject.activity == .Removed { return false }
	definition, found := find_subject_type(fleet,subject.subject_id)
	if !found { return false }
	table, ok := staffing_slot_lookup(state,target)
	if !ok { return false }
	slot := &state.staffing.slots[table]
	if !state.active[slot.building_index] { return false }
	if slot.occupant.id != 0 && slot.occupant.id != subject.id { return false }
	if !staffing_subject_eligible(subject,definition,target.role_id) { return false }
	if !staffing_subject_arrived(subject,target.building_id) { return false }
	release_subject_assignment(subject)
	release_subject_reservation(subject)
	subject.assignment = target
	subject.occupation = target.building_id
	subject.phase = .Working
	subject.work_hours = 0
	derive_staffing(state,fleet)
	return true
}
