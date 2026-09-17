package logic

import "core:testing"
import c "../contracts"

// Headless task-7 lifecycle regressions: rest/work/overtime timers, the work trip,
// the atomic physical handoff and inactivity. Tests reuse the Schedule_Test fixture
// and helpers from scheduling_test.odin (same package) and run the full application
// tick order, so no renderer, window or random source is involved.

// Full application-order tick: health, lifecycle, movement, handoff, coverage,
// scheduling. Mirrors the frame loop in src/app/main.odin.
shift_test_tick :: proc(r: ^Schedule_Test, ticks: int = 1) {
	for _ in 0..<ticks {
		step(&r.game)
		step_subject_health(&r.fleet)
		step_shifts(&r.game,&r.fleet)
		step_transports(&r.fleet,&r.game,r.definitions[:])
		commit_shift_handoffs(&r.game,&r.fleet)
		derive_staffing(&r.game,&r.fleet)
		schedule_staffing(&r.game,&r.fleet)
	}
}

@(test)
rest_completion_starts_the_reserved_trip :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	resting := schedule_person(&r,"human",{-10,0},.Resting,1,11) // One hour of rest left.
	target := c.Shift_Assignment{building_id="W1",role_id=.worker,slot_index=0}
	testing.expect(t,reserve_staffing_slot(&r.game,&r.fleet,resting,target))
	step_shifts(&r.game,&r.fleet)
	testing.expect(t,r.fleet.subjects[resting].phase == .Resting,"the reservation coexists with rest")
	for _ in 0..<58 { step_shifts(&r.game,&r.fleet) }
	testing.expect(t,r.fleet.subjects[resting].phase == .Resting)
	step_shifts(&r.game,&r.fleet)
	subject := &r.fleet.subjects[resting]
	testing.expect(t,subject.rest_hours == 12)
	testing.expect(t,subject.phase == .Moving_To_Work && subject.activity == .Moving)
	testing.expect(t,subject.destination == "W1" && subject.target == r.initial[1].position)
	// Travel to work is health-neutral even though the need effects keep running.
	before := subject.health
	for _ in 0..<30 { step_subject_health(&r.fleet) }
	testing.expect(t,subject.health == before)
}

@(test)
on_time_handoff_never_leaves_an_uncovered_tick :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].work_hours = 11.9 // Six ticks of work_time left.
	relief := schedule_person(&r,"human",{10,0})
	relief_id := r.fleet.subjects[relief].id
	for tick in 0..<12 {
		shift_test_tick(&r)
		coverage := staffing_coverage(&r.game,1,.worker)
		testing.expectf(t,coverage.covered_slots == 1,"tick %d lost coverage",tick)
	}
	// The replacement took the slot and the incumbent started rest in place.
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == relief_id)
	testing.expect(t,r.fleet.subjects[relief].assignment != nil && r.fleet.subjects[relief].phase == .Working)
	testing.expect(t,r.fleet.subjects[relief].work_hours < 0.2,"the new shift starts at hour zero")
	testing.expect(t,r.fleet.subjects[incumbent].assignment == nil && r.fleet.subjects[incumbent].phase == .Resting)
	testing.expect(t,r.fleet.subjects[incumbent].work_hours == 0)
	testing.expect(t,r.fleet.subjects[incumbent].rest_hours < 0.2,"rest started at the handoff")
	testing.expect(t,r.fleet.subjects[incumbent].position == r.initial[1].position,"rest starts at the workplace")
	testing.expect(t,r.fleet.subjects[incumbent].idle_hours == 0)
	testing.expect(t,building_staffed(&r.game,1))
}

@(test)
late_replacement_enters_overtime_and_arrives :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].work_hours = 11 // One hour of work_time left.
	relief := schedule_person(&r,"human",{10,0},.Resting,1,9) // Arrival in three hours.
	// While the incumbent is on time, a candidate that cannot arrive in time is not
	// reserved and no overtime health loss starts.
	shift_test_tick(&r,30)
	testing.expect(t,r.fleet.subjects[relief].reservation == nil)
	testing.expect(t,r.fleet.subjects[incumbent].phase == .Working)
	testing.expect(t,r.fleet.subjects[incumbent].health == 1)
	// work_time expires: the incumbent enters extra_working and the earliest-arriving
	// replacement is requested immediately.
	shift_test_tick(&r,30)
	testing.expect(t,r.fleet.subjects[incumbent].phase == .Extra_Working)
	_, reserved := r.fleet.subjects[relief].reservation.?
	testing.expect(t,reserved)
	shift_test_tick(&r,100)
	testing.expect(t,r.fleet.subjects[incumbent].health < 1,"overtime loses health")
	testing.expect(t,r.fleet.subjects[relief].phase == .Resting)
	// The replacement finishes resting, travels to the building and takes the slot.
	shift_test_tick(&r,60)
	testing.expect(t,r.fleet.subjects[relief].assignment != nil && r.fleet.subjects[relief].phase == .Working)
	testing.expect(t,r.fleet.subjects[incumbent].assignment == nil && r.fleet.subjects[incumbent].phase == .Resting)
	testing.expect(t,building_staffed(&r.game,1))
}

@(test)
no_replacement_leaves_at_overtime_expiry_and_rests :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].work_hours = 15.9 // Six ticks before extra_work_time expires.
	shift_test_tick(&r,5)
	testing.expect(t,r.fleet.subjects[incumbent].phase == .Extra_Working)
	testing.expect(t,r.fleet.subjects[incumbent].assignment != nil)
	shift_test_tick(&r,1)
	subject := &r.fleet.subjects[incumbent]
	testing.expect(t,subject.assignment == nil && subject.phase == .Resting,"leaving at extra_work_time expiry")
	testing.expect(t,subject.work_hours == 0 && subject.rest_hours == 0 && subject.idle_hours == 0)
	testing.expect(t,subject.position == r.initial[1].position,"rests where it is")
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == 0)
	testing.expect(t,!building_staffed(&r.game,1))
}

@(test)
incapacity_during_overtime_releases_immediately :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].phase = .Extra_Working
	r.fleet.subjects[incumbent].work_hours = 13
	shift_test_tick(&r,1)
	testing.expect(t,building_staffed(&r.game,1))
	r.fleet.subjects[incumbent].health = 0.2 // Below min_work_health.
	shift_test_tick(&r,1)
	subject := &r.fleet.subjects[incumbent]
	testing.expect(t,subject.assignment == nil && subject.phase == .Resting)
	testing.expect(t,subject.work_hours == 0 && subject.rest_hours == 0 && subject.idle_hours == 0)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == 0)
	testing.expect(t,!building_staffed(&r.game,1))
	// The same immediate release applies to a medical transition, before task 8 adds
	// evacuation movement.
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].health = 1
	shift_test_tick(&r,1)
	testing.expect(t,building_staffed(&r.game,1))
	r.fleet.subjects[incumbent].medical = .Pending_Evacuation
	shift_test_tick(&r,1)
	testing.expect(t,r.fleet.subjects[incumbent].assignment == nil && r.fleet.subjects[incumbent].phase == .Resting)
	testing.expect(t,staffing_slot_snapshot(&r.game,0).occupant == 0)
}

@(test)
replacement_still_in_transit_keeps_the_incumbent_in_overtime :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	incumbent := schedule_person(&r,"human",{10,0})
	schedule_claim(&r,incumbent,"W1",.worker)
	r.fleet.subjects[incumbent].work_hours = 11 // One hour left.
	// Rest finishes in one hour and the building is one travel hour away.
	relief := schedule_person(&r,"human",{8,0},.Resting,1,11)
	shift_test_tick(&r,90)
	testing.expect(t,r.fleet.subjects[incumbent].phase == .Extra_Working)
	testing.expect(t,r.fleet.subjects[relief].phase == .Moving_To_Work)
	testing.expect(t,r.fleet.subjects[incumbent].assignment != nil,"the incumbent keeps the slot while the relief travels")
	testing.expect(t,r.fleet.subjects[incumbent].health < 1)
	testing.expect(t,staffing_coverage(&r.game,1,.worker).covered_slots == 1)
	shift_test_tick(&r,40)
	testing.expect(t,r.fleet.subjects[relief].assignment != nil && r.fleet.subjects[relief].phase == .Working)
	testing.expect(t,r.fleet.subjects[incumbent].assignment == nil && r.fleet.subjects[incumbent].phase == .Resting)
}

@(test)
rest_completion_without_reservation_begins_inactivity :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r,true)
	defer schedule_test_destroy(&r)
	// No slot can take the subject, so the rest completes into inactivity.
	testing.expect(t,toggle(&r.game,{id="W1"}) == .Applied)
	subject_index := schedule_person(&r,"human",{10,0},.Resting,1,11.5) // Half an hour left.
	shift_test_tick(&r,30)
	subject := &r.fleet.subjects[subject_index]
	testing.expect(t,subject.phase == .Idle)
	testing.expect(t,subject.idle_hours < 1e-9,"inactivity starts from zero after rest")
	shift_test_tick(&r,60)
	testing.expect(t,abs(subject.idle_hours-1) < 0.03)
	shift_test_tick(&r,3600)
	testing.expect(t,subject.health < 1,"prolonged inactivity loses health")
}

@(test)
a_subject_can_take_a_different_role_after_resting :: proc(t: ^testing.T) {
	r: Schedule_Test
	schedule_test_init(&r)
	defer schedule_test_destroy(&r)
	subject_index := schedule_person(&r,"human",{-10,0})
	schedule_claim(&r,subject_index,"K1",.worker)
	r.fleet.subjects[subject_index].work_hours = 15.9 // Near extra_work_time expiry.
	shift_test_tick(&r,10)
	subject := &r.fleet.subjects[subject_index]
	testing.expect(t,subject.assignment == nil && subject.phase == .Resting)
	// The old worker slot is gone and the worker building is disabled; only the
	// office supervisor slot remains open.
	testing.expect(t,toggle(&r.game,{id="K1"}) == .Applied)
	testing.expect(t,toggle(&r.game,{id="W1"}) == .Applied)
	shift_test_tick(&r,1)
	reserved, has_reservation := subject.reservation.?
	testing.expect(t,has_reservation && reserved.role_id == .supervisor && reserved.building_id == "O1")
	testing.expect(t,subject.phase == .Resting)
	// Rest completes, the subject travels to the office and commits the new role.
	shift_test_tick(&r,1300)
	assigned, has_assignment := subject.assignment.?
	testing.expect(t,has_assignment && assigned.role_id == .supervisor && assigned.building_id == "O1")
	testing.expect(t,subject.phase == .Working)
	testing.expect(t,staffing_slot_snapshot(&r.game,2).occupant == subject.id)
	testing.expect(t,staffing_slot_snapshot(&r.game,1).occupant == 0)
	testing.expect(t,building_staffed(&r.game,3))
	testing.expect(t,!building_staffed(&r.game,2))
}

@(test)
lifecycle_follows_tick_counts_not_frame_pacing :: proc(t: ^testing.T) {
	// Two identical fixtures: one frame of one second and four frames of 0.25 s
	// produce the same fixed tick count, so the lifecycle is identical afterwards.
	a: Schedule_Test
	schedule_test_init(&a,true)
	defer schedule_test_destroy(&a)
	b: Schedule_Test
	schedule_test_init(&b,true)
	defer schedule_test_destroy(&b)
	for r in ([?]^Schedule_Test{&a,&b}) {
		worker := schedule_person(r,"human",{10,0})
		schedule_claim(r,worker,"W1",.worker)
		r.fleet.subjects[worker].work_hours = 11
		schedule_person(r,"human",{10,0},.Resting,1,10)
		schedule_person(r,"human",{10,0})
	}
	// 4x speed for one 0.25 s frame and four 0.25 s frames at 1x simulate the same
	// number of fixed ticks, so pacing and speed scaling cannot change the outcome.
	testing.expect(t,change_speed(&a.game.clock,.Faster) && change_speed(&a.game.clock,.Faster))
	ticks_a := advance_clock(&a.game.clock,0.25)
	ticks_b := 0
	for _ in 0..<4 { ticks_b += advance_clock(&b.game.clock,0.25) }
	testing.expect(t,ticks_a == 60 && ticks_b == 60)
	for _ in 0..<ticks_a { shift_test_tick(&a) }
	for _ in 0..<ticks_b { shift_test_tick(&b) }
	for index in 0..<len(a.fleet.subjects) {
		left, right := &a.fleet.subjects[index], &b.fleet.subjects[index]
		testing.expect(t,left.phase == right.phase)
		testing.expect(t,left.work_hours == right.work_hours && left.rest_hours == right.rest_hours)
		testing.expect(t,left.idle_hours == right.idle_hours && left.position == right.position)
		testing.expect(t,left.assignment == right.assignment && left.reservation == right.reservation)
	}
	// A paused frame advances no tick and therefore changes nothing.
	ticks_paused := advance_clock(&a.game.clock,0)
	testing.expect(t,ticks_paused == 0)
	testing.expect(t,a.fleet.subjects[0].work_hours == b.fleet.subjects[0].work_hours)
}
