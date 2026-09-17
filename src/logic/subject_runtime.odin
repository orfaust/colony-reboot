package logic

import "core:math"
import c "../contracts"

SUBJECT_LIMIT :: 16384
Subject_Activity :: enum { Station, Reserved, Onboard, Waiting, Moving, Inside, Removed }
// Per-need authoritative state: exactly one record per configured need of the
// subject's type. resource_id borrows the subject catalog. fulfillment is the
// fraction of the satisfied gain applied by the health step; it starts at 1
// (fully satisfied) and is driven hourly by `step_need_fulfillment` from the stock
// of the building the subject is physically inside.
// shortage_hours is that need's independent clock. The cached severity and effect
// are presentation values recomputed by the health step. Fixed storage keeps the
// per-subject state allocation-free.
Need_State :: struct {
    resource_id: string,
    fulfillment: f32,
    shortage_hours: f64,
    shortage_severity: f32,
    health_effect_per_hour: f32,
}
// Authoritative individual state. Strings borrow catalogs; roles borrow level data or transport-owned projections. Runtime
// IDs are unique for the session, including after a removed slot is reused.
Runtime_Subject :: struct {
    id: c.Subject_ID,
    source_id, subject_id, residence, occupation, destination: string,
    roles: []Subject_Role,
    activity: Subject_Activity,
    position, target: c.Vector2,
    speed: f32,
    wait_hours: f64,
    evacuating, evacuation_reserved: bool, // Colony evacuation owns movement until station discharge.
    evacuation_platform: string, // Stable destination once the walk starts; borrowed ID.
    medical_reserved: bool, // An emergency mission holds a seat; no second batch may claim it.
    medical_home: string, // Original colony residence; a returning patient goes home. Borrowed level ID.
    // Orthogonal authoritative state. health is clamped to [0,1] by the health
    // step; the timers are advanced by the shift lifecycle; assignment,
    // reservation and medical state are populated by the staffing/medical tasks.
    health: f32,
    phase: c.Work_Phase,
    work_hours, rest_hours, idle_hours: f64,
    assignment: Maybe(c.Shift_Assignment),
    reservation: Maybe(c.Shift_Assignment),
    medical: c.Medical_Status,
    needs: [c.NEED_SLOT_LIMIT]Need_State,
    need_count: int,
}
// Resolves a subject type by its stable catalog ID. The returned copy borrows
// catalog slices and is only valid while the catalog lives (the whole session).
@(private)
find_subject_type :: proc(state: ^Transport_State, id: string) -> (Subject_Type, bool) {
    for definition in state.subject_types { if definition.id == id { return definition, true } }
    return {}, false
}

// Materializes the fixed per-need runtime records of one subject from its type.
// The subject catalog is validated to fit NEED_SLOT_LIMIT at startup.
@(private)
initialize_needs :: proc(subject: ^Runtime_Subject, definition: Subject_Type) {
    count := min(len(definition.needs),c.NEED_SLOT_LIMIT)
    subject.need_count = count
    for i in 0..<count {
        need := definition.needs[i]
        subject.needs[i] = {resource_id=need.resource_id,fulfillment=1}
    }
}

@(private)
add_runtime_subject :: proc(state: ^Transport_State, subject: Runtime_Subject) -> int {
    value := subject
    value.id = c.Subject_ID(state.next_subject_id)
    state.next_subject_id += 1
    if value.speed <= 0 { value.speed = 1 }
    for definition, i in state.subject_types {
        if definition.id != value.subject_id { continue }
        if len(value.roles) == 0 { value.roles = state.subject_role_ids[i] }
        initialize_needs(&value,definition)
        break
    }
    for &existing, i in state.subjects {
        if existing.activity == .Removed { existing = value; return i }
    }
    if len(state.subjects) >= SUBJECT_LIMIT { return -1 }
    append(&state.subjects,value)
    return len(state.subjects)-1
}
initial_subject_count :: proc(instance: Station_Instance, buildings: []Building_Instance, initial: []Subject_Instance) -> f64 {
    count := f64(len(initial))
    for stock in instance.subjects { count += f64(stock.units) }
    for building in buildings {
        amount, _ := building.residents_amount.?
        explicit: f64
        for subject in initial { if subject.residence == building.id { explicit += 1 } }
        count += max(f64(0),f64(amount)-explicit)
    }
    return count
}

@(private)
reset_runtime_subjects :: proc(state: ^Transport_State, buildings: []Building_Instance, initial: []Subject_Instance) {
    clear(&state.subjects)
    state.next_subject_id = 1
    for subject, i in initial {
        value := Runtime_Subject{source_id=subject.id,subject_id=subject.subject_id,residence=subject.residence,
            occupation=initial_occupation(subject),roles=subject.roles,speed=subject.speed,health=subject.health,activity=.Inside,destination=subject.residence}
        for building in buildings { if building.id == subject.residence { value.position = building.position; value.target = building.position; break } }
        // A level initial assignment starts on shift at the assigned building. Startup
        // validation guaranteed the assignment references a continuous slot; slot
        // indices fill in level-subject order because the level format has no explicit
        // slot index. derive_staffing still validates the claim and releases it when an
        // eligibility rule (health, disablement, role) is not met.
        if subject.initial_assignment.building_id != "" {
            taken := 0
            for previous in initial[:i] {
                if previous.initial_assignment.building_id == subject.initial_assignment.building_id &&
                   previous.initial_assignment.role_id == subject.initial_assignment.role_id { taken += 1 }
            }
            value.assignment = c.Shift_Assignment{building_id=subject.initial_assignment.building_id,
                role_id=subject.initial_assignment.role_id,slot_index=taken}
            value.phase = .Working
            for building in buildings {
                if building.id == subject.initial_assignment.building_id {
                    value.position = building.position
                    value.target = building.position
                    value.destination = building.id
                    break
                }
            }
        }
        add_runtime_subject(state,value)
    }
    for building in buildings {
        amount, _ := building.residents_amount.?
        explicit := 0
        for subject in initial { if subject.residence == building.id { explicit += 1 } }
        for definition in state.building_types {
            if definition.id != building.building_id || definition.residents.type == "" { continue }
            for _ in explicit..<int(amount) {
                add_runtime_subject(state,{subject_id=definition.residents.type,residence=building.id,destination=building.id,
                    position=building.position,target=building.position,health=1,activity=.Inside})
            }
        }
    }
    for stock in state.stock {
        for _ in 0..<int(stock.units) { add_runtime_subject(state,{subject_id=stock.subject_id,health=1,activity=.Station}) }
    }
}
// Independent value snapshot; borrowed roles must not be mutated by callers.
subject_snapshot :: proc(state: ^Transport_State, id: c.Subject_ID) -> (Runtime_Subject, bool) {
    for subject in state.subjects { if subject.id == id && subject.activity != .Removed { return subject,true } }
    return {}, false
}

// Read-only contract view of one live subject. The result is a copy: mutating it
// never changes authoritative state, and its strings borrow catalog/level storage.
// Medical and assignment fields stay at their zero value until the staffing and
// medical tasks populate them.
subject_view_of :: proc(subject: ^Runtime_Subject) -> c.Subject_Snapshot {
    view := c.Subject_Snapshot{id=subject.id,subject_id=subject.subject_id,residence=subject.residence,
        health=subject.health,work_phase=subject.phase,medical=subject.medical,assignment=subject.assignment,
        position=subject.position,work_hours=subject.work_hours,rest_hours=subject.rest_hours,
        idle_hours=subject.idle_hours,need_count=subject.need_count}
    for i in 0..<subject.need_count {
        need := subject.needs[i]
        view.needs[i] = {resource_id=need.resource_id,fulfillment=need.fulfillment,
            shortage_hours=need.shortage_hours,shortage_severity=need.shortage_severity,
            health_effect_per_hour=need.health_effect_per_hour}
    }
    return view
}

// Read-only contract view by stable ID; the string fields borrow catalog storage.
subject_view :: proc(state: ^Transport_State, id: c.Subject_ID) -> (c.Subject_Snapshot, bool) {
    for &subject in state.subjects {
        if subject.id == id && subject.activity != .Removed { return subject_view_of(&subject),true }
    }
    return {}, false
}
// A semantic colony command changes only this subject. Transport-owned subjects
// cannot be redirected before discharge. Straight movement has no obstacle solver yet.
move_subject :: proc(state: ^Transport_State, game: ^State, command: c.Move_Subject) -> c.Move_Subject_Result {
    for &subject in state.subjects {
        if subject.id != command.id || subject.activity == .Removed { continue }
        // A person in medical evacuation or hospitalization is owned by the medical
        // path and cannot be redirected before discharge.
        if subject.evacuating || subject.medical != .None || (subject.activity != .Inside && subject.activity != .Moving && subject.activity != .Waiting) { return .Unavailable }
        for building in game.buildings {
            if building.id != command.destination { continue }
            subject.destination = building.id
            subject.target = building.position
            subject.activity = .Moving
            subject.wait_hours = 0
            return .Applied
        }
        return .Unknown_Destination
    }
    return .Unknown_Subject
}
@(private)
step_subjects :: proc(state: ^Transport_State) {
    for &subject in state.subjects {
        if subject.activity != .Waiting && subject.activity != .Moving { continue }
        remaining := f64(1)/TICKS_PER_HOUR
        if subject.activity == .Waiting {
            used := min(remaining,subject.wait_hours)
            subject.wait_hours -= used
            remaining -= used
            if subject.wait_hours > 1e-10 { continue }
            subject.activity = .Moving
        }
        dx := f64(subject.target.x)-f64(subject.position.x)
        dy := f64(subject.target.y)-f64(subject.position.y)
        distance := math.sqrt(dx*dx+dy*dy)
        travel := SUBJECT_WALK_SPEED*f64(subject.speed)*remaining
        if distance <= travel+1e-8 {
            subject.position = subject.target
            subject.activity = .Inside
        } else {
            subject.position.x += f32(dx*travel/distance)
            subject.position.y += f32(dy*travel/distance)
        }
    }
}
// Queue discharged people on the same route behind the preceding person. Identity
// survives boarding, cancellation, station return and later reassignment.
@(private)
disembark_subject :: proc(state: ^Transport_State, game: ^State, index: int, mission: ^Transport) {
    subject := &state.subjects[index]
    subject.residence = mission.destination
    subject.destination = mission.destination
    for building in game.buildings {
        if building.id == mission.platform_id { subject.position = building.position }
        if building.id == mission.destination { subject.target = building.position }
    }
    subject.activity = .Waiting
    subject.wait_hours = 0
    for other, i in state.subjects {
        if i == index || other.destination != subject.destination { continue }
        if other.activity == .Waiting && other.position == subject.position {
            subject.wait_hours = max(subject.wait_hours,other.wait_hours+SUBJECT_LINE_SPACING/(SUBJECT_WALK_SPEED*f64(subject.speed)))
        } else if other.activity == .Moving {
            dx := f64(other.position.x)-f64(subject.position.x)
            dy := f64(other.position.y)-f64(subject.position.y)
            separation := math.sqrt(dx*dx+dy*dy)
            subject.wait_hours = max(subject.wait_hours,(SUBJECT_LINE_SPACING-separation)/(SUBJECT_WALK_SPEED*f64(subject.speed)))
        }
    }
}
