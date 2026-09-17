package main

import "core:testing"

// Task-13 integration smoke, enforced by the test suite. The report is produced by
// `run_gameplay_smoke` in gameplay_smoke.odin and exercised in full by
// `tools/gameplay_smoke`. Every phenomenon named by roadmap task 13 must be observed
// in this one deterministic multi-day run.
@(test)
gameplay_multi_day_integration_smoke :: proc(t: ^testing.T) {
	report, ok := run_gameplay_smoke()
	testing.expectf(t,ok,"gameplay smoke invariants failed: %v",report)
	testing.expect(t,report.population_conserved,"population must be conserved")
	testing.expect(t,report.shift_handoffs >= 1,"at least one physical shift handoff")
	testing.expect(t,report.overtime_entries >= 1,"at least one overtime entry")
	testing.expect(t,report.staffing_lost >= 1 && report.staffing_restored >= 1,"staffing loss and restoration")
	testing.expect(t,report.power_gated_ticks > 0 && report.generator_unstaffed_hours > 0,"enabled generator must stop producing while unstaffed")
	testing.expect(t,report.simultaneous_shortage_ticks > 0,"two simultaneous need shortages")
	testing.expect(t,report.shortage_health_min < report.shortage_health_start,"simultaneous shortages must cost health")
	testing.expect(t,report.medical_evacuations >= 1,"medical evacuation requested")
	testing.expect(t,report.patient_hospitalized && report.patient_returned_home,"station recovery and return home")
	testing.expect(t,report.medical_returns >= 1,"medical return event")
	testing.expect(t,report.death_while_waiting && report.deaths >= 1,"death while waiting for evacuation")
	testing.expect(t,report.priority_medical_landed_first,"medical mission lands before an earlier ordinary waiter")
}
