package logic

import c "../contracts"

// Subject types are borrowed immutable catalog storage, like building types.
Subject_Need :: struct {
    resource_id: string,
    amount_per_hour: f32, // Resource units consumed per hour.
    shortage_alert_time: f32, // Hours the subject can go without the resource before complaining; starving starts as soon as it is denied.
    shortage_max_time: f32, // Hours the subject can remain in shortage before it dies or shuts down.
}
Subject_Role_Definition :: struct {
    role_id: Subject_Role,
    sprite: string `config:"optional"`, // Optional per-type role PNG override; borrowed catalog storage.
}
Subject_Type :: struct {
    id: string,
    name_key: string, // Localization key, not a display string.
    sprite: string `config:"optional"`, // Optional repository-relative PNG path; immutable catalog storage.
    width, height: f32, // Positive world-unit dimensions; presentation metadata.
    color: c.RGB, // Distinguishes the subject type.
    rest_time: f32, // Consecutive hours the subject must rest.
    work_time: f32, // Consecutive hours the subject can work.
    roles: []Subject_Role_Definition `config:"nullable"`, // Roles the subject type can take, without duplicates; JSON null (or []) means none.
    needs: []Subject_Need,
    produces: []Subject_Product, // Only resource_id and units_per_hour.
}
// JSON uses the lowercase names: "worker", "supervisor", "repairer".
Subject_Role :: enum {
    worker,
    supervisor,
    repairer,
}
// Building references are instance IDs within the same level, not building type IDs.
Subject_Instance :: struct {
    id: string,
    subject_id: string,
    residence: string,
    occupation: string `config:"nullable"`, // JSON null decodes as "": not working anywhere.
    roles: []Subject_Role, // Jobs the subject can do: nonempty, without duplicates.
    speed: f32, // Positive speed multiplier; 1 is normal speed.
}
