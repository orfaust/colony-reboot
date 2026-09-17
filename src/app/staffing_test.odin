package main

import "core:testing"
import "core:strings"
import "../config"
import "../logic"

// Task-4 integration: the shipped level and catalog materialize continuous slots
// headlessly, and the per-tick derivation keeps `Building_Snapshot.staffed` equal
// to authoritative coverage without touching the requested activity state.
@(test)
shipped_level_staffing_materializes_and_stays_consistent :: proc(t: ^testing.T) {
	data := load_reload_data(INITIAL_LEVEL_PATH)
	testing.expect(t,data != nil)
	if data == nil { return }
	defer destroy_reload_data(data)
	game, fleet := new_level_runtime(data)
	defer logic.destroy_transports(&fleet,context.allocator)
	expected := logic.continuous_slot_count(data.level.buildings,data.catalog.buildings)
	testing.expect(t,expected > 0)
	// Every shipped instance has a composed notice for each building-specific template
	// that names its localized type name plus its level instance ID.
	for building in data.level.buildings {
		definition, found := config.find_building(data.catalog,building.building_id)
		for key in BUILDING_NOTICE_KEYS {
			message, composed := data.building_notices.messages[{key,building.id}]
			testing.expectf(t,composed && message != "" && !strings.contains(message,"{name}") && !strings.contains(message,"{id}"),"%s notice for %s",key,building.id)
			if found {
				testing.expectf(t,strings.contains(message,data.text.entries[definition.name_key]),"%s notice names %s",key,building.id)
			}
			testing.expectf(t,strings.contains(message,building.id),"%s notice identifies %s",key,building.id)
		}
	}
	testing.expect(t,logic.staffing_slot_count(&game) == expected)
	// The shipped level assigns nobody, so every building with continuous slots is
	// unstaffed while its requested activity stays at the level's starting value.
	for building, i in data.level.buildings {
		testing.expect(t,logic.snapshot(&game,i).staffed == logic.building_staffed(&game,i))
		if logic.building_required_slots(&game,i) > 0 { testing.expect(t,!logic.building_staffed(&game,i)) }
		testing.expect(t,logic.snapshot(&game,i).active == logic.starts_active(building))
	}
	// The staffing gate is visible in the read-only view: the four started solar
	// panels have no continuous slots and keep producing 64 kW, while an active
	// building with uncovered continuous slots reports zero output.
	testing.expect(t,logic.balance(&game).produced_kw == 64)
	for building, i in data.level.buildings {
		view := logic.snapshot(&game,i)
		if view.active && logic.building_required_slots(&game,i) > 0 { testing.expect(t,view.power_output_kw == 0) }
	}
	// A fresh session publishes no staffing incident for covering that was never lost.
	testing.expect(t,len(logic.pending_events(&game.events)) == 0)
	for _ in 0..<120 {
		logic.step(&game)
		logic.step_subject_health(&fleet)
		logic.step_shifts(&game,&fleet)
		logic.step_transports(&fleet,&game,data.catalog.buildings)
		logic.commit_shift_handoffs(&game,&fleet)
		logic.derive_staffing(&game,&fleet)
		logic.schedule_staffing(&game,&fleet)
	}
	for building, i in data.level.buildings {
		testing.expect(t,logic.snapshot(&game,i).staffed == logic.building_staffed(&game,i))
		testing.expect(t,logic.snapshot(&game,i).active == logic.starts_active(building))
	}
	testing.expect(t,logic.balance(&game).produced_kw == 64)
	testing.expect(t,len(logic.pending_events(&game.events)) == 0)
	// Every slot-bearing building starts disabled and no resident is available yet, so
	// the scheduler leaves all materialized slots open without touching activity.
	for index in 0..<logic.staffing_slot_count(&game) {
		testing.expect(t,logic.staffing_slot_snapshot(&game,index).reserved == 0)
	}
}
