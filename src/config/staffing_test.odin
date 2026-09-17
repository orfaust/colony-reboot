package config

import "core:mem"
import "core:strings"
import "core:testing"
import "../logic"

// Task-4 startup validation: a level can never materialize more continuous slots
// than the runtime table holds, and no two initial assignments may share one slot.
// Both failures are reported before a session exists, so nothing is truncated and
// no subject is silently dropped at runtime.

@(test)
level_staffing_slot_capacity_is_enforced :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena,alignment=64)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)
	texts := test_texts(allocator)
	resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
	catalog, _ := decode_catalog(transmute([]byte)building_fixture,resources,texts,allocator)
	catalog.subjects, _ = decode_subjects(transmute([]byte)subject_fixture,resources,texts,allocator)
	// The level fixture assigns the supervisor role, which the minimal subject fixture omits.
	catalog.subjects[0].roles = []logic.Subject_Role_Definition{{role_id=.worker},{role_id=.supervisor},{role_id=.repairer}}
	stations := [?]logic.Space_Station{{id="test_station"}}
	catalog.space_stations = stations[:]
	level, error := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
	testing.expect(t,error == "",error)
	// test_producer exposes one supervisor and two continuous worker slots; the
	// on-demand repairer entry materializes nothing.
	testing.expect(t,logic.continuous_slot_count(level.buildings,catalog.buildings) == 3)
	testing.expect(t,logic.continuous_role_quantity(catalog.buildings[1],.repairer) == 0)
	testing.expect(t,logic.continuous_role_quantity(catalog.buildings[1],.worker) == 2)
	// One entry raised beyond the runtime table is rejected with an actionable path.
	catalog.buildings[1].subject_roles[1].quantity = logic.STAFFING_SLOT_LIMIT+1
	_, over := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
	testing.expect(t,strings.contains(over,"continuous staffing slots"),over)
	testing.expect(t,strings.contains(over,"runtime limit"),over)
	catalog.buildings[1].subject_roles[1].quantity = 2
	_, restored := decode_level(transmute([]byte)subject_level_fixture,catalog,allocator)
	testing.expect(t,restored == "",restored)
}

@(test)
initial_assignment_cannot_share_one_continuous_slot :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena,alignment=64)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)
	texts := test_texts(allocator)
	resources, _ := decode_resources(transmute([]byte)resource_fixture,texts,allocator)
	catalog, _ := decode_catalog(transmute([]byte)building_fixture,resources,texts,allocator)
	catalog.subjects, _ = decode_subjects(transmute([]byte)subject_fixture,resources,texts,allocator)
	// The level fixture assigns the supervisor role, which the minimal subject fixture omits.
	catalog.subjects[0].roles = []logic.Subject_Role_Definition{{role_id=.worker},{role_id=.supervisor},{role_id=.repairer}}
	stations := [?]logic.Space_Station{{id="test_station"}}
	catalog.space_stations = stations[:]
	// H2 becomes a second worker: exactly the two continuous worker slots are filled.
	two, _ := strings.replace_all(subject_level_fixture,`"initial_assignment":null,"roles":["repairer"]`,`"initial_assignment":{"building_id":"WP1","role_id":"worker"},"roles":["worker"]`,allocator)
	_, ok := decode_level(transmute([]byte)two,catalog,allocator)
	testing.expect(t,ok == "",ok)
	// A third initial assignment cannot share a materialized slot.
	three, _ := strings.replace_all(two,`"speed":0.75}`,`"speed":0.75},{"id":"H3","subject_id":"human","residence":"WP1","health":1,"initial_assignment":{"building_id":"WP1","role_id":"worker"},"roles":["worker"],"speed":1}`,allocator)
	_, over := decode_level(transmute([]byte)three,catalog,allocator)
	testing.expect(t,strings.contains(over,"subjects[2].initial_assignment"),over)
	testing.expect(t,strings.contains(over,"already assigned"),over)
	// The same level decodes once the entry exposes a third continuous slot.
	catalog.buildings[1].subject_roles[1].quantity = 3
	_, room := decode_level(transmute([]byte)three,catalog,allocator)
	testing.expect(t,room == "",room)
}
