package logic

import "core:math"

// Fixed-tick subject health and need accounting. Every authoritative health and
// shortage change happens here; the per-need `fulfillment` input is produced by
// `step_need_fulfillment` (fulfillment.odin) at whole simulated hours. No procedure
// allocates and none retains catalog storage past the call; per-need state lives in
// fixed arrays on each runtime subject.

// Hourly activity contribution for one subject, excluding needs. Only a subject
// physically inside a building is affected by work/rest/idle activity. Physical
// transport (.Station, station-side .Reserved for boarding, .Onboard, .Waiting,
// .Moving) is activity-neutral. Reservation waiting after completed rest and
// travel to work are neutral through their Work_Phase. Inactivity applies only to
// an unassigned subject whose required rest is complete (phase .Idle).
@(private)
subject_activity_effect :: proc(subject: ^Runtime_Subject, definition: Subject_Type) -> f32 {
	rates := definition.health_rates
	// Automatic station recovery for an identified hospitalized patient. It consumes
	// no colony or station resources and applies wherever the patient physically is
	// at the station, independent of the work/rest activity model.
	if subject.medical == .Hospitalized { return rates.station_recovery_per_hour }
	if subject.activity != .Inside { return 0 }
	switch subject.phase {
	case .Idle:
		return -inactivity_loss_per_hour(rates,subject.idle_hours)
	case .Resting:
		return rates.rest_gain_per_hour
	case .Working:
		return rates.work_gain_per_hour
	case .Extra_Working:
		return -rates.extra_work_loss_per_hour
	case .Reserved, .Moving_To_Work:
		return 0
	}
	return 0
}

// Quadratic inactivity ramp:
//   severity = clamp(idle_hours / inactivity_max_time, 0, 1)
//   loss_per_hour = max_inactivity_loss_per_hour * severity^2
// A configured maximum of zero disables the ramp instead of dividing by zero.
@(private)
inactivity_loss_per_hour :: proc(rates: Subject_Health_Rates, idle_hours: f64) -> f32 {
	if rates.inactivity_max_time <= 0 || idle_hours <= 0 { return 0 }
	severity := clamp(f32(idle_hours/f64(rates.inactivity_max_time)),0,1)
	return rates.max_inactivity_loss_per_hour*severity*severity
}

// Quadratic shortage severity. Before the alert time shortage has no negative
// effect. At or beyond the maximum time severity saturates at one. When the alert
// and maximum times are equal, severity becomes one immediately at that time.
@(private)
shortage_severity :: proc(hours, alert_time, max_time: f32) -> f32 {
	if hours < alert_time { return 0 }
	if max_time <= alert_time { return 1 }
	return clamp((hours-alert_time)/(max_time-alert_time),0,1)
}

// Advances one fixed tick of need shortage and health for every live subject.
// Safe to call headlessly: subject types were validated at startup. elapsed_hours
// must be finite and positive; NaN, infinity, zero and negative values change
// nothing, and a very large value only saturates health at 0 or 1.
step_subject_health :: proc(state: ^Transport_State, elapsed_hours: f64 = TICK_HOURS) {
	if math.is_nan(elapsed_hours) || math.is_inf(elapsed_hours) || elapsed_hours <= 0 { return }
	for &subject in state.subjects {
		if subject.activity == .Removed { continue }
		definition, found := find_subject_type(state,subject.subject_id)
		if !found { continue }
		apply_subject_health_tick(&subject,definition,elapsed_hours)
	}
}

// One authoritative health tick: advance every need clock, sum the signed hourly
// influences (activity plus one effect per need), then clamp health into [0,1].
// Full fulfillment clears that need's shortage clock; any missing amount advances
// it. Partial fulfillment still scales the positive gain by its fraction.
@(private)
apply_subject_health_tick :: proc(subject: ^Runtime_Subject, definition: Subject_Type, elapsed_hours: f64) {
	hourly := f64(subject_activity_effect(subject,definition))
	count := min(subject.need_count,len(definition.needs))
	for i in 0..<count {
		need := &subject.needs[i]
		configured := definition.needs[i]
		// Fulfillment is a fraction; out-of-range input is clamped so a malformed
		// supply step can never double a gain or negate a shortage.
		fraction := clamp(need.fulfillment,0,1)
		need.fulfillment = fraction
		if fraction >= 1 {
			need.shortage_hours = 0
		} else {
			need.shortage_hours += elapsed_hours
		}
		severity := shortage_severity(f32(need.shortage_hours),configured.shortage_alert_time,configured.shortage_max_time)
		gain := f64(configured.satisfied_health_gain_per_hour)*f64(fraction)
		loss := f64(configured.max_shortage_health_loss_per_hour)*f64(severity)*f64(severity)
		need.shortage_severity = severity
		need.health_effect_per_hour = f32(gain-loss)
		hourly += gain-loss
	}
	subject.health = clamp(f32(f64(subject.health)+hourly*elapsed_hours),0,1)
}
