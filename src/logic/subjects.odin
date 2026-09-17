package logic

import c "../contracts"

// Subject types are borrowed immutable catalog storage, like building types.
Subject_Need :: struct {
    resource_id: string,
    amount_per_hour: f32, // Resource units consumed per hour.
    shortage_alert_time: f32, // Hours the subject can go without the resource before complaining; starving starts as soon as it is denied.
    shortage_max_time: f32, // Hours the subject can remain in shortage before it dies or shuts down.
    satisfied_health_gain_per_hour: f32, // Health gained per hour at full fulfillment; nonnegative.
    max_shortage_health_loss_per_hour: f32, // Health lost per hour at maximum shortage severity; nonnegative.
}
Subject_Role_Definition :: struct {
    role_id: Subject_Role,
    sprite: string `config:"optional"`, // Optional per-type role PNG override; borrowed catalog storage.
}
// Positive magnitudes in health per hour, except inactivity_max_time in hours.
// Logic decides whether each rate is a gain or loss and clamps health to [0,1].
Subject_Health_Rates :: struct {
    work_gain_per_hour: f32,
    rest_gain_per_hour: f32,
    extra_work_loss_per_hour: f32,
    max_inactivity_loss_per_hour: f32,
    inactivity_max_time: f32,
    station_recovery_per_hour: f32,
}
Subject_Type :: struct {
    id: string,
    name_key: string, // Localization key, not a display string.
    sprite: string `config:"optional"`, // Optional repository-relative PNG path; immutable catalog storage.
    width, height: f32, // Positive pixel dimensions at 100% zoom; presentation metadata.
    color: c.RGB, // Distinguishes the subject type.
    rest_time: f32, // Consecutive hours the subject must rest.
    work_time: f32, // Consecutive hours the subject can work.
    extra_work_time: f32, // Maximum hours the subject may keep a slot after work_time.
    min_work_health: f32, // Minimum health required to start or continue work, in (min_colony_health,1].
    min_colony_health: f32, // Threshold that requests medical evacuation, in [0,min_work_health).
    health_rates: Subject_Health_Rates, // Hourly health influences; nonnegative magnitudes.
    roles: []Subject_Role_Definition `config:"nullable"`, // Roles the subject type can take, without duplicates; JSON null (or []) means none.
    needs: []Subject_Need,
    produces: []Subject_Product, // Only resource_id and units_per_hour.
}
// A level subject's optional initial shift assignment. Runtime assignments are not
// pointers into configuration storage; this is validated startup metadata.
Initial_Assignment :: struct {
    building_id: string,
    role_id: Subject_Role,
}
// Gameplay roles are a shared contract. Configuration decodes them by their
// lowercase JSON names ("worker", "supervisor", "repairer"); the authoritative
// interpretation stays in logic. See src/contracts/subjects.odin.
Subject_Role :: c.Subject_Role
// Building references are instance IDs within the same level, not building type IDs.
Subject_Instance :: struct {
    id: string,
    subject_id: string,
    residence: string,
    health: f32, // Individual health in [0,1]; generated residents default to 1.
    initial_assignment: Initial_Assignment `config:"nullable"`, // JSON null: no initial shift. Replaces the former `occupation`.
    roles: []Subject_Role, // Jobs the subject can do: nonempty, without duplicates.
    speed: f32, // Positive speed multiplier; 1 is normal speed.
}

// Temporary migration bridge: the pre-shift runtime tracks one active occupation
// string. It borrows the initial assignment's building ID until the shift systems
// replace it. Empty means unassigned.
initial_occupation :: proc(instance: Subject_Instance) -> string {
    return instance.initial_assignment.building_id
}
