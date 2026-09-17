package contracts

// Shared subject-health contracts for the logic, application and UI layers.
//
// Ownership and lifetime
// ----------------------
// Every value here is plain data (IDs, numbers, fixed arrays, Maybe values).
// Strings borrow validated configuration/level storage owned by the application
// arena; they stay valid while that storage lives and must never be freed or
// mutated by a consumer. Snapshots are copies of authoritative state: mutating a
// returned value never changes the simulation.
//
// No config slice and no mutable logic pointer ever crosses this boundary.

// Subject roles are a shared, untranslated vocabulary across configuration,
// simulation and UI. JSON uses the lowercase names: "worker", "supervisor",
// "repairer". Logic owns the authoritative interpretation of a role.
Subject_Role :: enum {
	worker,
	supervisor,
	repairer,
}

// Individual health is a normalized value in [0,1]. Logic clamps every update; a
// consumer must never treat it as a percentage or write it back into the session.
Health :: f32

// Per-tick work/rest phase. Physical presence, shift reservation and medical state
// are separate fields and are never folded into this enum.
//   Idle           rest complete and unassigned: quadratic inactivity loss applies.
//   Resting        required rest: the positive rest rate applies.
//   Reserved       assigned to a future shift with rest already complete: neutral.
//   Moving_To_Work travelling to the assigned building: neutral.
//   Working        covering a staffing slot: the positive work rate applies.
//   Extra_Working  overtime past work_time: the negative overtime rate applies.
Work_Phase :: enum {
	Idle,
	Resting,
	Reserved,
	Moving_To_Work,
	Working,
	Extra_Working,
}

// One individual staffing slot. building_id is a level building-instance ID,
// role_id a supported role and slot_index the stable index within that building's
// role entry. Strings borrow validated level storage. Runtime assignments are
// values, never pointers into configuration or another module's mutable storage.
Shift_Assignment :: struct {
	building_id: string,
	role_id: Subject_Role,
	slot_index: int,
}

// Medical lifecycle, orthogonal to work phase and physical activity. A dead
// subject is removed from the session rather than represented by a status value.
Medical_Status :: enum {
	None,
	Pending_Evacuation,
	Evacuating,
	Hospitalized,
	Returning,
}

// One per-need runtime record copied into the read-only subject view.
// resource_id borrows the subject catalog. fulfillment is the applied gain
// fraction in [0,1]; shortage_hours is the need's independent shortage clock;
// shortage_severity and health_effect_per_hour are the cached quadratic severity
// and the signed hourly contribution for presentation.
Need_Snapshot :: struct {
	resource_id: string,
	fulfillment: f32,
	shortage_hours: f64,
	shortage_severity: f32,
	health_effect_per_hour: f32,
}

// Maximum needs supported per subject type, validated at startup. A fixed array
// keeps per-subject need state allocation-free.
NEED_SLOT_LIMIT :: 8

// Read-only individual view produced by logic. All fields are values; strings
// borrow catalog/level storage and the value must not be retained past that
// storage. assignment is unset until the shift model materializes slots.
Subject_Snapshot :: struct {
	id: Subject_ID,
	subject_id: string, // Subject type ID from subjects.json.
	residence: string, // Building instance ID; empty at the station or onboard.
	health: Health,
	work_phase: Work_Phase,
	medical: Medical_Status,
	assignment: Maybe(Shift_Assignment),
	position: Vector2,
	work_hours: f64,
	rest_hours: f64,
	idle_hours: f64,
	needs: [NEED_SLOT_LIMIT]Need_Snapshot,
	need_count: int,
}

// Staffing coverage for one building role entry. required_slots counts the
// continuous slots the entry asks for, covered_slots the slots a physically
// present eligible subject currently occupies, and reserved_slots the slots a
// scheduled replacement has claimed but not yet reached. Counts are nonnegative
// and never expose slot storage.
Staffing_Coverage :: struct {
	role_id: Subject_Role,
	required_slots: int,
	covered_slots: int,
	reserved_slots: int,
}

// Read-only view of one materialized continuous staffing slot. building_id borrows
// validated level storage. occupant and reserved are stable subject IDs, zero when
// the slot is physically uncovered or unreserved; the two claims are independent.
// slot_index is the stable index within the building's role entry and prevents two
// subjects from covering or reserving the same slot.
Staffing_Slot_Snapshot :: struct {
	building_id: string,
	role_id: Subject_Role,
	slot_index: int,
	occupant: Subject_ID,
	reserved: Subject_ID,
}

// Edge-triggered simulation events. A transition is queued exactly once when it
// happens, never once per tick. Payloads carry stable IDs only; building_id
// borrows validated level storage. sequence is monotonic within a session and
// defines the delivery order observed by consumers.
//
// Power_Shed is emitted once per building stopped by automatic load shedding, in
// shed order. All Power_Shed events of one fixed tick belong to the same grouped
// notice, so a consumer must collect them instead of composing one notice each.
Sim_Event_Kind :: enum {
	Staffing_Lost, // An enabled building lost continuous coverage.
	Staffing_Restored, // Continuous coverage returned to the building.
	Production_Blocked, // An operational building skipped its hour for a missing input.
	Production_Resumed, // A previously blocked building ran its hourly recipe again.
	Power_Shed, // Load shedding force-stopped an active consumer; grouped per tick.
	Medical_Evacuation, // A subject crossed min_colony_health.
	Medical_Return, // A recovered patient returned to the colony.
	Subject_Died, // A subject reached zero health and was removed.
}

Sim_Event :: struct {
	sequence: u64, // Monotonic within a session; defines delivery order.
	kind: Sim_Event_Kind,
	building_id: string, // Building events; empty for subject-only events.
	subject_id: Subject_ID, // Subject events; zero for building-only events.
}
