package main

import "core:testing"
import "../logic"

// Integration check for the data-foundation slice: the shipped level and catalog
// drive runtime health, need records and the fixed-tick health step without a
// window. Rendering is never initialized here.
@(test)
shipped_subject_health_integrates_with_transport :: proc(t: ^testing.T) {
	data := load_reload_data(INITIAL_LEVEL_PATH)
	testing.expect(t,data != nil)
	if data == nil { return }
	defer destroy_reload_data(data)
	game, fleet := new_level_runtime(data)
	defer logic.destroy_transports(&fleet,context.allocator)

	// Every individual is initialized from its type: full health and one need record
	// per configured need.
	for subject in fleet.subjects {
		testing.expect(t,subject.health == 1)
		for definition in data.catalog.subjects {
			if definition.id == subject.subject_id { testing.expect(t,subject.need_count == len(definition.needs)) }
		}
	}
	first := fleet.subjects[0].id
	for _ in 0..<121 {
		logic.step(&game)
		logic.step_subject_health(&fleet)
		logic.step_shifts(&game,&fleet)
		logic.step_transports(&fleet,&game,data.catalog.buildings)
		logic.commit_shift_handoffs(&game,&fleet)
		logic.derive_staffing(&game,&fleet)
		logic.schedule_staffing(&game,&fleet)
	}
	// Health stays clamped and stable IDs survive the simulated ticks.
	found := false
	for subject in fleet.subjects {
		testing.expect(t,subject.health >= 0 && subject.health <= 1)
		if subject.id == first { found = true }
	}
	testing.expect(t,found)
}
