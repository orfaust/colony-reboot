package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"
import "../logic"
import "../config"
import c "../contracts"

// Task-12 reload state regressions. The previous session is driven into a rich live
// state (active shift, changed health and needs, pending patient, evacuation queue,
// in-flight mission, queued events) so a failed reload proves the whole session
// survives untouched and a successful one proves it is rebuilt from the level.

// Activates the first continuously staffed building and gives it one physically
// working individual, materializing a covered staffing slot in the running session.
// Returns the building index, or -1 when the level materializes no continuous slot.
reload_state_activate_shift :: proc(game: ^logic.State, fleet: ^logic.Transport_State, data: ^Reload_Data) -> int {
	for instance, i in game.buildings {
		if logic.building_required_slots(game,i) == 0 { continue }
		game.active[i] = true
		game.level[i] = 1
		role := logic.Subject_Role.worker
		for definition in data.catalog.buildings {
			if definition.id != instance.building_id { continue }
			for entry in definition.subject_roles {
				if entry.staffing_mode == .continuous && entry.quantity > 0 { role = entry.role_id; break }
			}
			break
		}
		for subject_type, si in data.catalog.subjects {
			if subject_type.id != "human" { continue }
			person := logic.Runtime_Subject{id=1,subject_id=subject_type.id,residence=instance.id,destination=instance.id,
				position=instance.position,target=instance.position,activity=.Inside,phase=.Working,
				roles=fleet.subject_role_ids[si],health=0.55,work_hours=3,
				assignment=c.Shift_Assignment{building_id=instance.id,role_id=role,slot_index=0}}
			count := min(len(subject_type.needs),c.NEED_SLOT_LIMIT)
			person.need_count = count
			for need, n in subject_type.needs[:count] { person.needs[n] = {resource_id=need.resource_id,fulfillment=0.6,shortage_hours=2} }
			append(&fleet.subjects,person)
			break
		}
		logic.derive_staffing(game,fleet)
		return i
	}
	return -1
}

// Turns a freshly built session into the rich live state shared by both reload
// tests. Returns the activated building index, or -1 when none was available.
reload_state_seed_live :: proc(game: ^logic.State, fleet: ^logic.Transport_State, data: ^Reload_Data, t: ^testing.T) -> int {
	shift_building := reload_state_activate_shift(game,fleet,data)
	testing.expect(t,shift_building >= 0)
	append(&fleet.subjects,logic.Runtime_Subject{id=2,subject_id="human",activity=.Inside,health=0.08,medical=.Pending_Evacuation})
	fleet.evacuation_pending[0] = true
	fleet.evacuation_started[0] = true
	fleet.next_landing_ticket = 9
	fleet.count = 1
	fleet.missions[0] = {phase=.Outbound,ship_id="shuttle",subject_id="human",distance=100,travelled=10,duration=5,phase_duration=5,phase_elapsed=1}
	testing.expect(t,logic.push_event(&game.events,.Staffing_Lost,building_id=game.buildings[0].id))
	return shift_building
}

@(test)
reload_failure_preserves_active_shifts_health_patients_and_queues :: proc(t: ^testing.T) {
	old := load_reload_data(INITIAL_LEVEL_PATH)
	testing.expect(t,old != nil)
	if old == nil { return }
	defer destroy_reload_data(old)
	game, fleet := new_level_runtime(old)
	defer logic.destroy_transports(&fleet,context.allocator)
	shift_building := reload_state_seed_live(&game,&fleet,old,t)
	if shift_building < 0 { return }

	before_slots := logic.staffing_slot_count(&game)
	before_covered := logic.staffing_coverage(&game,shift_building,.worker).covered_slots
	before_events := len(logic.pending_events(&game.events))
	before_health := fleet.subjects[0].health
	before_need := fleet.subjects[0].needs[0]
	before_assignment := fleet.subjects[0].assignment
	before_medical := fleet.subjects[1].medical
	before_ticket := fleet.next_landing_ticket
	before_mission := fleet.missions[0].phase
	before_pending := fleet.evacuation_pending[0]
	// Runtime stock lives in the session, so it must survive a rejected reload too.
	// The snapshot is borrowed, so keep an independent copy to compare after reloads.
	stock_building := -1
	for i in 0..<len(game.buildings) {
		if len(logic.stock_snapshot(&game,i)) > 0 { stock_building = i; break }
	}
	testing.expect(t,stock_building >= 0)
	before_stock: []c.Stock_Snapshot
	if stock_building >= 0 {
		source := logic.stock_snapshot(&game,stock_building)
		before_stock = make([]c.Stock_Snapshot,len(source),context.allocator)
		copy(before_stock,source)
	}
	defer delete(before_stock,context.allocator)

	// A sprite-staging failure must leave the previous session completely untouched.
	testing.expect(t,prepare_reload(INITIAL_LEVEL_PATH,reload_test_sprites_fail) == nil)
	// A bad reference (unknown station) must do the same.
	path := "build/reload-state-invalid-test.json"
	testing.expect(t,!os.exists(path))
	if !os.exists(path) {
		defer os.remove(path)
		bad := `{"version":1,"level":0,"space_station":{"station_id":"missing-station","distance":0,"resources":[],"subjects":[]},"buildings":[],"subjects":[]}`
		testing.expect(t,os.write_entire_file(path,transmute([]byte)bad))
		testing.expect(t,prepare_reload(path,reload_test_sprites_ok) == nil)
	}

	testing.expect(t,logic.staffing_slot_count(&game) == before_slots)
	testing.expect(t,logic.staffing_coverage(&game,shift_building,.worker).covered_slots == before_covered)
	testing.expect(t,len(logic.pending_events(&game.events)) == before_events)
	testing.expect(t,fleet.subjects[0].health == before_health && fleet.subjects[0].needs[0] == before_need)
	testing.expect(t,fleet.subjects[0].assignment == before_assignment)
	testing.expect(t,fleet.subjects[0].reservation == nil)
	testing.expect(t,fleet.subjects[1].medical == before_medical)
	testing.expect(t,fleet.next_landing_ticket == before_ticket)
	testing.expect(t,fleet.missions[0].phase == before_mission)
	testing.expect(t,fleet.evacuation_pending[0] == before_pending)
	stock := logic.stock_snapshot(&game,stock_building)
	testing.expect(t,len(stock) == len(before_stock))
	for entry, i in stock { testing.expect(t,entry == before_stock[i]) }
}

@(test)
reload_success_rebuilds_health_rates_slots_reservations_patients_and_queues :: proc(t: ^testing.T) {
	old := load_reload_data(INITIAL_LEVEL_PATH)
	testing.expect(t,old != nil)
	if old == nil { return }
	defer destroy_reload_data(old)
	game, fleet := new_level_runtime(old)
	defer logic.destroy_transports(&fleet,context.allocator)
	if reload_state_seed_live(&game,&fleet,old,t) < 0 { return }

	// A changed but valid level: the new session must rebuild every derived array.
	path := "build/reload-state-valid-test.json"
	testing.expect(t,!os.exists(path))
	if os.exists(path) { return }
	defer os.remove(path)
	source, read_ok := os.read_entire_file(INITIAL_LEVEL_PATH)
	testing.expect(t,read_ok)
	if !read_ok { return }
	defer delete(source)
	quoted_id := fmt.aprintf("\"%s\"",old.level.buildings[1].id)
	defer delete(quoted_id)
	changed, _ := strings.replace_all(string(source),quoted_id,`"reload-state-building"`,context.allocator)
	defer delete(changed)
	testing.expect(t,os.write_entire_file(path,transmute([]byte)changed))

	next := prepare_reload(path,reload_test_sprites_ok)
	testing.expect(t,next != nil)
	if next == nil { return }
	defer destroy_reload_data(next)
	fresh, fresh_fleet := new_level_runtime(next)
	defer logic.destroy_transports(&fresh_fleet,context.allocator)

	// Slots are materialized from the new level and the level change is visible.
	testing.expect(t,logic.staffing_slot_count(&fresh) == logic.continuous_slot_count(next.level.buildings,next.catalog.buildings))
	testing.expect(t,next.level.buildings[1].id == "reload-state-building" && old.level.buildings[1].id != "reload-state-building")
	// Clock, missions, queues and the event log restart cleanly.
	testing.expect(t,fresh.clock == {})
	testing.expect(t,fresh_fleet.count == 0 && fresh_fleet.next_landing_ticket == 0)
	for value in fresh_fleet.evacuation_pending { testing.expect(t,!value) }
	for value in fresh_fleet.evacuation_started { testing.expect(t,!value) }
	testing.expect(t,len(logic.pending_events(&fresh.events)) == 0)
	for index in 0..<logic.staffing_slot_count(&fresh) {
		slot := logic.staffing_slot_snapshot(&fresh,index)
		testing.expect(t,slot.occupant == 0 && slot.reserved == 0)
	}
	// Every individual comes from the level: health 1, needs rebuilt and fully
	// satisfied, no carried-over assignment, reservation or medical state.
	testing.expect(t,len(fresh_fleet.subjects) > 0)
	// Runtime stock is rebuilt from the new level: one entry per required resource,
	// capacities from the definition and amounts from the level template.
	for instance, i in fresh.buildings {
		stock := logic.stock_snapshot(&fresh,i)
		definition, found := config.find_building(next.catalog,instance.building_id)
		testing.expect(t,found)
		testing.expect(t,len(stock) == len(instance.stored))
		for entry in stock {
			capacity, stocked := logic.stock_capacity(definition,entry.resource_id)
			testing.expect(t,stocked && entry.capacity == f64(capacity))
			found_amount := false
			for stored in instance.stored {
				if stored.resource_id == entry.resource_id {
					testing.expect(t,entry.amount == f64(stored.amount))
					found_amount = true
					break
				}
			}
			testing.expect(t,found_amount)
		}
	}
	for subject in fresh_fleet.subjects {
		testing.expect(t,subject.health == 1)
		testing.expect(t,subject.assignment == nil && subject.reservation == nil)
		testing.expect(t,subject.medical == .None && !subject.medical_reserved)
		testing.expect(t,!subject.evacuating && !subject.evacuation_reserved)
		for definition in next.catalog.subjects {
			if definition.id != subject.subject_id { continue }
			testing.expect(t,subject.need_count == len(definition.needs))
		}
		for i in 0..<subject.need_count { testing.expect(t,subject.needs[i].fulfillment == 1 && subject.needs[i].shortage_hours == 0) }
	}
}

// Every reload candidate owns a separate arena; success and failure must both release
// it, leaving no long-lived allocation behind.
@(test)
reload_candidate_allocations_are_released_on_success_and_failure :: proc(t: ^testing.T) {
	backing := context.allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track,backing)
	track.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)
	defer context.allocator = backing

	testing.expect(t,prepare_reload(INITIAL_LEVEL_PATH,reload_test_sprites_fail) == nil)
	next := prepare_reload(INITIAL_LEVEL_PATH,reload_test_sprites_ok)
	testing.expect(t,next != nil)
	if next != nil {
		// Building the runtime allocates the flat stock table from the candidate arena:
		// destroying the candidate must release it together with the rest of the session.
		fresh, fresh_fleet := new_level_runtime(next)
		logic.destroy_transports(&fresh_fleet,context.allocator)
		destroy_reload_data(next)
	}

	leaks := 0
	for _, entry in track.allocation_map {
		_ = entry
		leaks += 1
	}
	testing.expectf(t,leaks == 0,"%d reload candidate allocation(s) survived",leaks)
	testing.expect(t,len(track.bad_free_array) == 0)
}
