package gameplay_smoke

// Headless task-13 gameplay smoke. Builds a deterministic multi-day colony from the
// shipped tuning values, steps it through the application's fixed-tick order, prints
// the observed balance outcomes and fails (non-zero exit) if an integration
// invariant is not demonstrated. No window or GPU is opened.
//
//   odin run tools/gameplay_smoke -out:build/gameplay-smoke.exe

import app "../../src/app"
import "core:fmt"
import "core:os"

main :: proc() {
	report, ok := app.run_gameplay_smoke()
	fmt.printf("Gameplay smoke: %d simulated hours (%d fixed ticks)\n",report.hours,report.ticks)
	fmt.printf("  population        : %d -> %d (deaths %d, conserved %v)\n",report.population_start,report.population_end,report.deaths,report.population_conserved)
	fmt.printf("  shift handoffs    : %d, overtime entries %d\n",report.shift_handoffs,report.overtime_entries)
	fmt.printf("  staffing events   : lost %d, restored %d\n",report.staffing_lost,report.staffing_restored)
	fmt.printf("  generator unstaffed: %.1f h, power-gated ticks %d, min available %.2f kW, sheds %d\n",report.generator_unstaffed_hours,report.power_gated_ticks,report.min_available_kw,report.power_shed)
	fmt.printf("  simultaneous shortage ticks: %d, health %.3f -> min %.3f\n",report.simultaneous_shortage_ticks,report.shortage_health_start,report.shortage_health_min)
	fmt.printf("  medical          : evacuations %d, returns %d, hospitalized %v, returned home %v\n",report.medical_evacuations,report.medical_returns,report.patient_hospitalized,report.patient_returned_home)
	fmt.printf("  death while waiting: %v, medical landing priority %v\n",report.death_while_waiting,report.priority_medical_landed_first)
	if !ok {
		fmt.eprintln("Gameplay smoke FAILED one or more integration invariants.")
		os.exit(1)
	}
	fmt.println("Gameplay smoke passed all documented integration invariants.")
}
