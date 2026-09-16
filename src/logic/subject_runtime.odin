package logic

import "core:math"
import c "../contracts"

SUBJECT_LIMIT :: 16384
Subject_Activity :: enum { Station, Reserved, Onboard, Waiting, Moving, Inside, Removed }
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
}
@(private)
add_runtime_subject :: proc(state: ^Transport_State, subject: Runtime_Subject) -> int {
    value := subject
    value.id = c.Subject_ID(state.next_subject_id)
    state.next_subject_id += 1
    if value.speed <= 0 { value.speed = 1 }
    if len(value.roles) == 0 {
        for definition, i in state.subject_types { if definition.id == value.subject_id { value.roles = state.subject_role_ids[i]; break } }
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
    for subject in initial {
        value := Runtime_Subject{source_id=subject.id,subject_id=subject.subject_id,residence=subject.residence,
            occupation=subject.occupation,roles=subject.roles,speed=subject.speed,activity=.Inside,destination=subject.residence}
        for building in buildings { if building.id == subject.residence { value.position = building.position; value.target = building.position; break } }
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
                    position=building.position,target=building.position,activity=.Inside})
            }
        }
    }
    for stock in state.stock {
        for _ in 0..<int(stock.units) { add_runtime_subject(state,{subject_id=stock.subject_id,activity=.Station}) }
    }
}
// Independent value snapshot; borrowed roles must not be mutated by callers.
subject_snapshot :: proc(state: ^Transport_State, id: c.Subject_ID) -> (Runtime_Subject, bool) {
    for subject in state.subjects { if subject.id == id && subject.activity != .Removed { return subject,true } }
    return {}, false
}
// A semantic colony command changes only this subject. Transport-owned subjects
// cannot be redirected before discharge. Straight movement has no obstacle solver yet.
move_subject :: proc(state: ^Transport_State, game: ^State, command: c.Move_Subject) -> c.Move_Subject_Result {
    for &subject in state.subjects {
        if subject.id != command.id || subject.activity == .Removed { continue }
        if subject.evacuating || (subject.activity != .Inside && subject.activity != .Moving && subject.activity != .Waiting) { return .Unavailable }
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
