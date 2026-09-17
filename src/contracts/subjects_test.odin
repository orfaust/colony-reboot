package contracts

import "core:testing"

// Contract-level value semantics: snapshots and events are plain data that copies
// independent of one another, so a consumer can never mutate authoritative state.
@(test)
snapshot_and_event_values_are_independent_copies :: proc(t: ^testing.T) {
	original := Subject_Snapshot{id=Subject_ID(7), subject_id="human", residence="HR1", health=0.5, work_phase=.Resting, need_count=1}
	original.needs[0] = {resource_id="water", fulfillment=1}
	assignment := Shift_Assignment{building_id="GH1", role_id=.worker, slot_index=2}
	original.assignment = assignment

	copied := original
	copied.health = 0
	copied.subject_id = "robot"
	copied.work_phase = .Idle
	copied.need_count = 0
	copied.needs[0].fulfillment = 0
	copied.assignment = nil
	testing.expect(t,original.health == 0.5 && original.subject_id == "human")
	testing.expect(t,original.work_phase == .Resting && original.need_count == 1)
	testing.expect(t,original.needs[0].fulfillment == 1)
	stored, ok := original.assignment.?
	testing.expect(t,ok && stored == assignment)

	event := Sim_Event{sequence=1, kind=.Subject_Died, subject_id=Subject_ID(42)}
	copied_event := event
	copied_event.kind = .Staffing_Lost
	copied_event.subject_id = 0
	testing.expect(t,event.kind == .Subject_Died && event.subject_id == 42)
}
