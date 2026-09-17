package logic

import "core:math"
import "core:testing"
import c "../contracts"

// Fixed-tick health and need regression tests. All fixtures are headless: no
// renderer, window or GPU resource is involved.

HUMAN_RATES :: Subject_Health_Rates {
	work_gain_per_hour = 0.002,
	rest_gain_per_hour = 0.01,
	extra_work_loss_per_hour = 0.025,
	max_inactivity_loss_per_hour = 0.012,
	inactivity_max_time = 72,
	station_recovery_per_hour = 0.04,
}
ROBOT_RATES :: Subject_Health_Rates {
	work_gain_per_hour = 0.0015,
	rest_gain_per_hour = 0.02,
	extra_work_loss_per_hour = 0.015,
	max_inactivity_loss_per_hour = 0.006,
	inactivity_max_time = 120,
	station_recovery_per_hour = 0.06,
}
// A need with no health influence: isolates activity/phase effects.
NEUTRAL_NEED :: Subject_Need{resource_id = "none", amount_per_hour = 1, shortage_alert_time = 0, shortage_max_time = 1}

Health_Fixture :: struct {
	needs: [c.NEED_SLOT_LIMIT]Subject_Need,
	roles: [1]Subject_Role_Definition,
	types: [1]Subject_Type,
	state: Transport_State,
}

// The needs slice must fit NEED_SLOT_LIMIT. The fixture owns the Transport_State;
// destroy_transports frees every runtime array exactly once.
health_fixture_init :: proc(r: ^Health_Fixture, rates: Subject_Health_Rates, needs: []Subject_Need) {
	assert(len(needs) <= c.NEED_SLOT_LIMIT)
	r.needs = {}
	for need, i in needs { r.needs[i] = need }
	r.roles = {{role_id = .worker}}
	r.types = {{id = "human", roles = r.roles[:], needs = r.needs[:len(needs)], health_rates = rates}}
	r.state = new_transports({}, {}, nil, nil, nil, context.allocator, nil, r.types[:])
}

health_fixture_destroy :: proc(r: ^Health_Fixture) {
	destroy_transports(&r.state,context.allocator)
}

health_fixture_subject :: proc(r: ^Health_Fixture, health: f32, phase: c.Work_Phase = .Idle, activity: Subject_Activity = .Inside, idle_hours: f64 = 0) -> ^Runtime_Subject {
	index := add_runtime_subject(&r.state,{subject_id="human", health=health, phase=phase, activity=activity, idle_hours=idle_hours})
	assert(index >= 0)
	return &r.state.subjects[index]
}

health_fixture_ticks :: proc(r: ^Health_Fixture, ticks: int) {
	for _ in 0..<ticks { step_subject_health(&r.state) }
}

@(test)
runtime_health_initialization_and_need_records :: proc(t: ^testing.T) {
	types := [?]Subject_Type{{id="human", needs=[]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=6, shortage_max_time=72, satisfied_health_gain_per_hour=0.001, max_shortage_health_loss_per_hour=0.025}}}}
	definitions := [?]Building_Type{{id="home", residents={type="human", capacity=5}}}
	initial := [?]Building_Instance{{id="H", building_id="home", health=1, residents_amount=f32(2)}}
	explicit := [?]Subject_Instance{{id="named", subject_id="human", residence="H", health=0.25}}
	stock := [?]Station_Subject_Stock{{subject_id="human", units=1}}
	instance := Station_Instance{subjects=stock[:]}
	state := new_transports({}, instance, nil, initial[:], explicit[:], context.allocator, definitions[:], types[:])
	defer destroy_transports(&state,context.allocator)

	named, generated, station := false, false, false
	for subject in state.subjects {
		if subject.source_id == "named" {
			named = true
			testing.expect(t,subject.health == 0.25 && subject.need_count == 1)
			testing.expect(t,subject.needs[0].resource_id == "water" && subject.needs[0].fulfillment == 1 && subject.needs[0].shortage_hours == 0)
			testing.expect(t,subject.phase == .Idle && subject.medical == .None)
		} else if subject.activity == .Inside {
			generated = true
			testing.expect(t,subject.health == 1 && subject.need_count == 1)
		} else if subject.activity == .Station {
			station = true
			testing.expect(t,subject.health == 1 && subject.need_count == 1)
		}
	}
	testing.expect(t,named && generated && station)
	// Explicit health is level session state, restored by a reset without touching config.
	reset_transports(&state,instance,initial[:],explicit[:])
	for subject in state.subjects { if subject.source_id == "named" { testing.expect(t,subject.health == 0.25) } }
}

@(test)
need_shortage_respects_tick_boundaries :: proc(t: ^testing.T) {
	// Alert 1 h, maximum 2 h: severity stays zero through the exact alert tick and
	// grows only once the clock passes it.
	needs := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=1, shortage_max_time=2, max_shortage_health_loss_per_hour=0.6}}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,needs[:])
	defer health_fixture_destroy(&r)
	subject := health_fixture_subject(&r,1)
	subject.needs[0].fulfillment = 0

	health_fixture_ticks(&r,59)
	testing.expect(t,subject.needs[0].shortage_severity == 0 && subject.health == 1)
	health_fixture_ticks(&r,1)
	testing.expect(t,abs(subject.needs[0].shortage_hours-1) < 1e-9)
	testing.expect(t,subject.needs[0].shortage_severity == 0 && subject.health == 1)
	health_fixture_ticks(&r,1)
	expected := f32(1.0/60)
	testing.expect(t,abs(subject.needs[0].shortage_severity-expected) < 1e-6, "severity ramps after the alert tick")
	testing.expect(t,subject.health < 1 && subject.health > 0.999)
	// Two half-tick reference steps accumulate to exactly one whole tick of shortage.
	half_a: Health_Fixture
	health_fixture_init(&half_a,HUMAN_RATES,needs[:])
	defer health_fixture_destroy(&half_a)
	a := health_fixture_subject(&half_a,1)
	a.needs[0].fulfillment = 0
	step_subject_health(&half_a.state,TICK_HOURS)
	step_subject_health(&half_a.state,TICK_HOURS)
	here: Health_Fixture
	health_fixture_init(&here,HUMAN_RATES,needs[:])
	defer health_fixture_destroy(&here)
	one := health_fixture_subject(&here,1)
	one.needs[0].fulfillment = 0
	step_subject_health(&here.state,2*TICK_HOURS)
	testing.expect(t,abs(a.health-one.health) < 1e-6 && abs(a.needs[0].shortage_hours-one.needs[0].shortage_hours) < 1e-9)
}

@(test)
partial_need_fulfillment_scales_gain_and_advances_clock :: proc(t: ^testing.T) {
	needs := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, satisfied_health_gain_per_hour=0.06}}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,needs[:])
	defer health_fixture_destroy(&r)
	subject := health_fixture_subject(&r,0)
	subject.needs[0].fulfillment = 0.5
	health_fixture_ticks(&r,60)
	testing.expect(t,abs(subject.health-0.03) < 1e-4, "half fulfillment applies half the gain")
	testing.expect(t,subject.needs[0].shortage_hours > 0.99, "any missing amount advances the clock")
	// Full fulfillment clears the clock and applies the whole gain.
	subject.needs[0].fulfillment = 1
	health_fixture_ticks(&r,60)
	testing.expect(t,abs(subject.health-0.09) < 1e-4)
	testing.expect(t,subject.needs[0].shortage_hours == 0 && subject.needs[0].shortage_severity == 0)
	// Out-of-range fulfillment clamps to a fraction and is normalized back.
	subject.needs[0].fulfillment = 2
	health_fixture_ticks(&r,60)
	testing.expect(t,abs(subject.health-0.15) < 1e-4)
	testing.expect(t,subject.needs[0].fulfillment == 1)
}

@(test)
simultaneous_need_effects_are_additive :: proc(t: ^testing.T) {
	combined := [?]Subject_Need{
		{resource_id="water", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, max_shortage_health_loss_per_hour=0.3},
		{resource_id="meals", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, max_shortage_health_loss_per_hour=0.6},
	}
	single_a := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, max_shortage_health_loss_per_hour=0.3}}
	single_b := [?]Subject_Need{{resource_id="meals", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, max_shortage_health_loss_per_hour=0.6}}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,combined[:])
	defer health_fixture_destroy(&r)
	both := health_fixture_subject(&r,1)
	for &need in both.needs { need.fulfillment = 0 }
	health_fixture_ticks(&r,60)

	ra: Health_Fixture
	health_fixture_init(&ra,HUMAN_RATES,single_a[:])
	defer health_fixture_destroy(&ra)
	a := health_fixture_subject(&ra,1)
	a.needs[0].fulfillment = 0
	health_fixture_ticks(&ra,60)

	rb: Health_Fixture
	health_fixture_init(&rb,HUMAN_RATES,single_b[:])
	defer health_fixture_destroy(&rb)
	b := health_fixture_subject(&rb,1)
	b.needs[0].fulfillment = 0
	health_fixture_ticks(&rb,60)

	drop_both := 1-both.health
	drop_sum := (1-a.health)+(1-b.health)
	testing.expect(t,abs(drop_both-drop_sum) < 1e-5, "need effects from different resources add")
	testing.expect(t,both.health > 0.6 && both.health < 0.75)
}

@(test)
shortage_alert_equal_to_max_saturates_immediately :: proc(t: ^testing.T) {
	needs := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=1, shortage_max_time=1, max_shortage_health_loss_per_hour=60}}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,needs[:])
	defer health_fixture_destroy(&r)
	subject := health_fixture_subject(&r,1)
	subject.needs[0].fulfillment = 0
	health_fixture_ticks(&r,59)
	testing.expect(t,subject.health == 1 && subject.needs[0].shortage_severity == 0)
	health_fixture_ticks(&r,1)
	testing.expect(t,subject.needs[0].shortage_severity == 1)
	testing.expect(t,subject.health == 0, "maximum severity applies from the alert tick")
}

@(test)
very_large_and_invalid_elapsed_values :: proc(t: ^testing.T) {
	loss := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, max_shortage_health_loss_per_hour=1}}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,loss[:])
	defer health_fixture_destroy(&r)
	subject := health_fixture_subject(&r,0.5)
	subject.needs[0].fulfillment = 0
	step_subject_health(&r.state,1e9)
	testing.expect(t,subject.health == 0 && subject.needs[0].shortage_severity == 1)

	gain := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, satisfied_health_gain_per_hour=1}}
	rg: Health_Fixture
	health_fixture_init(&rg,HUMAN_RATES,gain[:])
	defer health_fixture_destroy(&rg)
	recovering := health_fixture_subject(&rg,0.5)
	step_subject_health(&rg.state,1e9)
	testing.expect(t,recovering.health == 1)

	// NaN, infinity, zero and negative elapsed values change nothing.
	before := recovering.health
	step_subject_health(&rg.state,math.nan_f64())
	step_subject_health(&rg.state,math.inf_f64(1))
	step_subject_health(&rg.state,0)
	step_subject_health(&rg.state,-1)
	testing.expect(t,recovering.health == before)
}

@(test)
health_saturates_at_zero_and_one :: proc(t: ^testing.T) {
	neutral := [?]Subject_Need{NEUTRAL_NEED}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,neutral[:])
	defer health_fixture_destroy(&r)
	full := health_fixture_subject(&r,1,.Resting)
	empty := health_fixture_subject(&r,0,.Extra_Working)
	health_fixture_ticks(&r,120)
	testing.expect(t,full.health == 1)
	testing.expect(t,empty.health == 0)
	// Positive activity still contributes near full health; only clamping limits it.
	near := health_fixture_subject(&r,0.9999,.Resting)
	health_fixture_ticks(&r,1)
	testing.expect(t,near.health == 1)
}

@(test)
activity_neutrality_keeps_need_effects_active :: proc(t: ^testing.T) {
	needs := [?]Subject_Need{{resource_id="water", amount_per_hour=0.1, shortage_alert_time=0, shortage_max_time=1, max_shortage_health_loss_per_hour=0.6}}
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,needs[:])
	defer health_fixture_destroy(&r)
	// Reserved and moving-to-work phases are activity-neutral, but need loss still applies.
	reserved := health_fixture_subject(&r,1,.Reserved)
	moving := health_fixture_subject(&r,1,.Moving_To_Work)
	// Transport activity is neutral even if the work phase says otherwise.
	onboard := health_fixture_subject(&r,1,.Working,.Onboard)
	for subject in ([?]^Runtime_Subject{reserved,moving,onboard}) { subject.needs[0].fulfillment = 0 }
	health_fixture_ticks(&r,60)
	// Severity ramps quadratically over the hour: the discrete total loss is
	// 0.6 * sum((n/60)^2) / 60 = 0.20503, independent of the neutral phase or
	// transport activity.
	expected := f32(0.79497)
	for subject in ([?]^Runtime_Subject{reserved,moving,onboard}) {
		testing.expectf(t,abs(subject.health-expected) < 1e-4, "need loss continues while transport/activity is neutral: got %v want %v", subject.health, expected)
	}
	// Fully satisfied needs leave reserved and moving subjects at full health.
	satisfied := health_fixture_subject(&r,1,.Reserved)
	health_fixture_ticks(&r,60)
	testing.expect(t,satisfied.health == 1)
}

@(test)
configured_human_and_robot_default_rates :: proc(t: ^testing.T) {
	neutral := [?]Subject_Need{NEUTRAL_NEED}
	// Human: +0.002/h working, +0.01/h resting, -0.025/h overtime, -0.012/h at
	// full inactivity, over a 72 h ramp.
	r: Health_Fixture
	health_fixture_init(&r,HUMAN_RATES,neutral[:])
	defer health_fixture_destroy(&r)
	working := health_fixture_subject(&r,0.5,.Working)
	resting := health_fixture_subject(&r,0.5,.Resting)
	overtime := health_fixture_subject(&r,0.5,.Extra_Working)
	idle := health_fixture_subject(&r,0.5,.Idle,.Inside,72)
	health_fixture_ticks(&r,60)
	testing.expect(t,abs(working.health-0.502) < 1e-4)
	testing.expect(t,abs(resting.health-0.51) < 1e-4)
	testing.expect(t,abs(overtime.health-0.475) < 1e-4)
	testing.expect(t,abs(idle.health-0.488) < 1e-4)

	// Robot: +0.0015/h working, +0.02/h resting, -0.015/h overtime, -0.006/h at
	// full inactivity, over a 120 h ramp.
	rb: Health_Fixture
	health_fixture_init(&rb,ROBOT_RATES,neutral[:])
	defer health_fixture_destroy(&rb)
	robot_working := health_fixture_subject(&rb,0.5,.Working)
	robot_resting := health_fixture_subject(&rb,0.5,.Resting)
	robot_overtime := health_fixture_subject(&rb,0.5,.Extra_Working)
	robot_idle := health_fixture_subject(&rb,0.5,.Idle,.Inside,120)
	health_fixture_ticks(&rb,60)
	testing.expect(t,abs(robot_working.health-0.5015) < 1e-4)
	testing.expect(t,abs(robot_resting.health-0.52) < 1e-4)
	testing.expect(t,abs(robot_overtime.health-0.485) < 1e-4)
	testing.expect(t,abs(robot_idle.health-0.494) < 1e-4)

	// Halfway through the inactivity ramp the quadratic loss is a quarter of the max.
	ramp: Health_Fixture
	health_fixture_init(&ramp,HUMAN_RATES,neutral[:])
	defer health_fixture_destroy(&ramp)
	half_idle := health_fixture_subject(&ramp,0.5,.Idle,.Inside,36)
	health_fixture_ticks(&ramp,60)
	testing.expect(t,abs(half_idle.health-0.497) < 1e-4)
}

@(test)
zero_inactivity_ramp_disables_loss :: proc(t: ^testing.T) {
	rates := HUMAN_RATES
	rates.inactivity_max_time = 0
	neutral := [?]Subject_Need{NEUTRAL_NEED}
	r: Health_Fixture
	health_fixture_init(&r,rates,neutral[:])
	defer health_fixture_destroy(&r)
	subject := health_fixture_subject(&r,0.5,.Idle,.Inside,72)
	health_fixture_ticks(&r,60)
	testing.expect(t,subject.health == 0.5)
}
