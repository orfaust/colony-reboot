package logic

import "core:math"
import c "../contracts"

// Shift scheduler: the per-tick step that reserves unassigned individuals for
// materialized continuous staffing slots. Reservation is exclusive and value-based
// (see staffing.odin); this step only chooses candidates and never moves anyone.
// Task 7 owns movement, physical handoff and the work/rest/overtime timers.
//
// Candidate ordering is deterministic and uses only authoritative state:
//   1. compatible role and health eligibility (filters);
//   2. forecast arrival ascending (remaining required rest plus travel time);
//   3. longest availability descending (the type's nominal work_time: the longer
//      shift wins a tie, which matters with mixed subject types);
//   4. straight-line distance ascending;
//   5. stable Subject_ID ascending.
//
// Reservation timing
// ------------------
// An uncovered slot is filled immediately with the best candidate: coverage is
// needed now, and the candidate rests normally before task 7 moves it to work. For
// a slot whose incumbent is still `Working`, the scheduler is deliberately
// just-in-time: it reserves a replacement only when the candidate's forecast
// arrival is within one fixed tick of the incumbent's remaining work_time. While
// both the candidate rests and the incumbent works, that difference stays constant,
// so the request lands in the final part of the candidate's rest and travel starts
// as soon as rest completes, reaching the building by shift end. A candidate that
// cannot make it is not reserved early; once the incumbent enters `Extra_Working`
// the earliest-arriving eligible candidate is requested regardless of lateness.
//
// Work bounds and limits
// ----------------------
// A pass examines at most SCHEDULER_SLOT_BUDGET materialized slots and performs at
// most SCHEDULER_EVALUATION_LIMIT subject evaluations. When a bound cuts the pass
// short, the remaining slots are left exactly as they are and retried next pass; the
// slot cursor and the subject-scan cursor rotate so no slot or subject is
// permanently ignored. `Scheduler.deferred` counts cumulative deferred slot
// examinations for diagnostics. Deferral never drops a subject and never changes a
// reservation; when there is no eligible candidate the slot simply stays open.
SCHEDULER_SLOT_BUDGET :: 128
SCHEDULER_EVALUATION_LIMIT :: 65536
// Reserve a replacement when its forecast arrival is within one fixed tick of the
// incumbent's remaining work time (just-in-time handoff).
SCHEDULER_ARRIVAL_WINDOW :: f64(TICK_HOURS)

// Session-owned scheduler bookkeeping. Reset clears it; no allocation, no random
// source and no per-tick state outside this struct.
Scheduler :: struct {
	cursor: int, // Next materialized slot index to examine; rotates across passes.
	subject_cursor: int, // First subject of a bounded scan; rotates when a pass is cut short.
	deferred: u64, // Cumulative slot examinations skipped because a bound cut the pass.
}

// One candidate ranking value. `arrival` is in simulated hours from now, `distance`
// in world units, `availability` the type's nominal work_time in hours.
@(private)
Schedule_Candidate :: struct {
	index: int,
	id: c.Subject_ID,
	arrival: f64,
	availability: f32,
	distance: f64,
}

// Straight-line distance (world units) and travel hours from the subject's current
// position to a building, using the same speed model as step_subjects. Shared by the
// scheduler forecast and the movement/handoff step so both agree on arrival time.
subject_travel :: proc(subject: ^Runtime_Subject, building: Building_Instance) -> (distance, hours: f64) {
	dx := f64(subject.position.x)-f64(building.position.x)
	dy := f64(subject.position.y)-f64(building.position.y)
	distance = math.sqrt(dx*dx+dy*dy)
	speed := f64(subject.speed)
	if speed <= 0 { speed = 1 }
	return distance,distance/(SUBJECT_WALK_SPEED*speed)
}

subject_travel_hours :: proc(subject: ^Runtime_Subject, building: Building_Instance) -> f64 {
	_, hours := subject_travel(subject,building)
	return hours
}

// Evaluates one individual as a candidate for one slot. Claims, station/onboard
// people, the unhealthy, medical/evacuation cases and unsupported roles are filtered
// out here and re-checked by reserve_staffing_slot.
@(private)
schedule_candidate :: proc(fleet: ^Transport_State, index: int, role_id: Subject_Role, building: Building_Instance) -> (Schedule_Candidate, bool) {
	subject := &fleet.subjects[index]
	if subject.activity == .Removed || subject.assignment != nil || subject.reservation != nil { return {},false }
	if !staffing_subject_in_colony(subject) { return {},false }
	definition, found := find_subject_type(fleet,subject.subject_id)
	if !found { return {},false }
	if !staffing_subject_eligible(subject,definition,role_id) { return {},false }
	remaining_rest: f64
	if subject.phase == .Resting { remaining_rest = max(f64(0),f64(definition.rest_time)-subject.rest_hours) }
	distance, travel := subject_travel(subject,building)
	return {index=index,id=subject.id,arrival=remaining_rest+travel,availability=definition.work_time,distance=distance},true
}

// Strict ordering over the deterministic candidate keys, smallest first.
@(private)
schedule_candidate_better :: proc(candidate, best: Schedule_Candidate) -> bool {
	if candidate.arrival != best.arrival { return candidate.arrival < best.arrival }
	if candidate.availability != best.availability { return candidate.availability > best.availability }
	if candidate.distance != best.distance { return candidate.distance < best.distance }
	return candidate.id < best.id
}

// Examines one materialized slot and reserves the best candidate when the timing
// rules allow it. `stop` reports that an evaluation bound cut the pass short.
@(private)
schedule_slot :: proc(state: ^State, fleet: ^Transport_State, table: int, evaluations: ^int, evaluation_limit: int, scanned: ^int, stop: ^bool) {
	slot := &state.staffing.slots[table]
	if !state.active[slot.building_index] { return }
	if slot.reserved.id != 0 { return }
	building := state.buildings[slot.building_index]
	just_in_time := false
	deadline: f64
	if slot.occupant.id != 0 {
		if slot.occupant.index < 0 || slot.occupant.index >= len(fleet.subjects) { return }
		incumbent := &fleet.subjects[slot.occupant.index]
		if incumbent.id != slot.occupant.id { return }
		definition, found := find_subject_type(fleet,incumbent.subject_id)
		if !found { return }
		switch incumbent.phase {
		case .Working:
			deadline = max(f64(0),f64(definition.work_time)-incumbent.work_hours)
			// A zero deadline behaves like overtime even before the phase transition:
			// request the earliest-arriving candidate instead of waiting.
			just_in_time = deadline > 0
		case .Extra_Working:
			// The deadline has passed; request coverage as soon as possible.
		case .Idle, .Resting, .Reserved, .Moving_To_Work:
			return
		}
	}
	subject_count := len(fleet.subjects)
	if subject_count == 0 { return }
	best: Schedule_Candidate
	has_best := false
	offset := 0
	for offset < subject_count {
		if evaluations^ >= evaluation_limit { stop^ = true; break }
		index := (state.scheduler.subject_cursor+offset)%subject_count
		evaluations^ += 1
		scanned^ += 1
		offset += 1
		candidate, ok := schedule_candidate(fleet,index,slot.role_id,building)
		if !ok { continue }
		if just_in_time && abs(deadline-candidate.arrival) > SCHEDULER_ARRIVAL_WINDOW+1e-9 { continue }
		if !has_best || schedule_candidate_better(candidate,best) { best = candidate; has_best = true }
	}
	if has_best {
		reserve_staffing_slot(state,fleet,best.index,{building_id=building.id,role_id=slot.role_id,slot_index=slot.slot_index})
	}
}

// Runs the scheduler once. Call after derive_staffing in the same fixed tick, so
// invalid or stale reservations have already been cancelled and are replaced
// immediately; `slot_budget`/`evaluation_limit` default to the documented bounds and
// are parameters only so tests can exercise deferral deterministically.
schedule_staffing :: proc(state: ^State, fleet: ^Transport_State, slot_budget: int = SCHEDULER_SLOT_BUDGET, evaluation_limit: int = SCHEDULER_EVALUATION_LIMIT) {
	slot_count := len(state.staffing.slots)
	if slot_count == 0 { return }
	budget := clamp(slot_budget,0,slot_count)
	if budget == 0 {
		state.scheduler.deferred += u64(slot_count)
		return
	}
	evaluations := 0
	scanned := 0
	examined := 0
	stop := false
	for examined < budget && !stop {
		table := (state.scheduler.cursor+examined)%slot_count
		schedule_slot(state,fleet,table,&evaluations,evaluation_limit,&scanned,&stop)
		examined += 1
	}
	state.scheduler.cursor = (state.scheduler.cursor+examined)%slot_count
	subject_count := len(fleet.subjects)
	if subject_count > 0 { state.scheduler.subject_cursor = (state.scheduler.subject_cursor+scanned)%subject_count }
	state.scheduler.deferred += u64(slot_count-examined)
}
