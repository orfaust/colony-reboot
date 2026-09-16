package logic

import "core:math"
import "core:mem"

// Bounded session log, including finished missions. At the limit demand stays
// pending without consuming stock. Catalogs/IDs are borrowed; runtime arrays owned.
TRANSPORT_LIMIT :: 128
LANDING_HOURS :: f64(1) // Final approach/clearance: one simulated hour for the last <=1 km.
LANDING_RANGE_KM :: f64(1)
SUBJECT_WALK_SPEED :: f64(2) // World units per simulated hour; straight platform-to-home route.
SUBJECT_LINE_SPACING :: f64(0.25)
Transport_Phase :: enum {
    Loading, Outbound, Waiting_Landing, Landing, Unloading,
    Taking_Off, Braking, Returning, Return_Unloading, Completed, Cancelled,
}
Transport :: struct {
    ship_id, subject_id, destination, platform_id: string,
    evacuation: bool, // Empty outbound pickup; Unloading phase boards colony residents.
    pickup_platform_id: string, // Required pad for an evacuation manifest.
    holding_platform_id: string, // Visual anchor only, never a platform reservation.
    landing_ticket: u64, // FIFO entry order, independent of dispatch/mission order.
    manifest: []int, // Owned runtime slots; public APIs use stable subject IDs.
    units, loaded, returned, delivered, requested: f32, // Whole-person caches; the manifest owns individual membership.
    phase: Transport_Phase,
    phase_elapsed, phase_duration: f64,
    elapsed, duration, distance, max_speed, max_speed_hours, handling_hours, handling_rate: f64,
    speed, travelled, leg_distance: f64,
    brake_start, brake_speed, return_start, takeoff_start: f64,
    landing_progress: f64, // 0 at approach altitude, 1 on the platform.
    arrived: bool, // Colony service complete: delivery discharged, or evacuation boarded.
}
Transport_State :: struct {
    allocator: mem.Allocator,
    subjects: [dynamic]Runtime_Subject,
    next_subject_id: u64,
    building_types: []Building_Type,
    subject_types: []Subject_Type,
    subject_role_ids: [][]Subject_Role, // Owned projections; runtime subjects borrow these until destruction.
    station: Space_Station,
    distance: f32, // Copied from the level instance on reset.
    ships: []Ship,
    stock: []Station_Subject_Stock,
    stock_fraction: []f64, // Signed sub-subject accrual, never exposed as available stock.
    available: []Station_Ship,
    reserved: []f32,
    occupants: []f32,
    last_active, evacuation_pending, evacuation_started: []bool,
    missions: [TRANSPORT_LIMIT]Transport,
    count: int,
    next_landing_ticket: u64,
}
new_transports :: proc(station: Space_Station, instance: Station_Instance, ships: []Ship, buildings: []Building_Instance, subjects: []Subject_Instance, allocator: mem.Allocator, building_types: []Building_Type = nil, subject_types: []Subject_Type = nil) -> Transport_State {
    state := Transport_State{station=station, ships=ships,allocator=allocator,building_types=building_types,subject_types=subject_types,
        subjects=make([dynamic]Runtime_Subject,0,SUBJECT_LIMIT,allocator),
        stock=make([]Station_Subject_Stock,len(instance.subjects),allocator),
        stock_fraction=make([]f64,len(instance.subjects),allocator),
        available=make([]Station_Ship,len(station.ships),allocator),
        reserved=make([]f32,len(buildings),allocator), occupants=make([]f32,len(buildings),allocator),
        last_active=make([]bool,len(buildings),allocator), evacuation_pending=make([]bool,len(buildings),allocator),
        evacuation_started=make([]bool,len(buildings),allocator)}
    state.subject_role_ids = make([][]Subject_Role,len(subject_types),allocator)
    for definition, i in subject_types {
        state.subject_role_ids[i] = make([]Subject_Role,len(definition.roles),allocator)
        for role, j in definition.roles { state.subject_role_ids[i][j] = role.role_id }
    }
    reset_transports(&state,instance,buildings,subjects)
    return state
}
destroy_transports :: proc(state: ^Transport_State, allocator: mem.Allocator) {
    for mission in state.missions[:state.count] { delete(mission.manifest,allocator) }
    delete(state.subjects)
    for roles in state.subject_role_ids { delete(roles,allocator) }
    delete(state.subject_role_ids,allocator)
    delete(state.stock,allocator)
    delete(state.stock_fraction,allocator)
    delete(state.available,allocator)
    delete(state.reserved,allocator)
    delete(state.occupants,allocator)
    delete(state.last_active,allocator)
    delete(state.evacuation_pending,allocator)
    delete(state.evacuation_started,allocator)
    state^ = {}
}
reset_transports :: proc(state: ^Transport_State, instance: Station_Instance, buildings: []Building_Instance, subjects: []Subject_Instance) {
    assert(initial_subject_count(instance,buildings,subjects) <= SUBJECT_LIMIT) // External levels are validated by config.
    state.distance = instance.distance
    copy(state.stock,instance.subjects)
    for &fraction in state.stock_fraction { fraction = 0 }
    copy(state.available,state.station.ships)
    for mission in state.missions[:state.count] { delete(mission.manifest,state.allocator) }
    state.count = 0
    state.next_landing_ticket = 0
    state.missions = {}
    reset_runtime_subjects(state,buildings,subjects)
    for building, i in buildings {
        amount, _ := building.residents_amount.?
        explicit: f32
        for subject in subjects { if subject.residence == building.id { explicit += 1 } }
        state.occupants[i] = max(amount,explicit)
        state.reserved[i] = 0
        state.last_active[i] = starts_active(building)
        state.evacuation_pending[i] = false
        state.evacuation_started[i] = false
    }
}
// Symmetric accelerate/cruise/brake, including triangular short routes.
// Zero ramp hours explicitly means instantaneous speed changes; never divide by zero.
travel_duration :: proc(distance, max_speed, max_speed_hours: f64) -> f64 {
    if distance <= 0 || max_speed <= 0 { return 0 }
    if max_speed_hours <= 0 { return distance/max_speed }
    acceleration := max_speed/max_speed_hours
    ramp := min(max_speed_hours,math.sqrt(distance/acceleration))
    peak := acceleration*ramp
    return 2*ramp + max(f64(0),distance-peak*ramp)/peak
}
transport_position :: proc(mission: Transport) -> (distance, speed: f64) {
    if mission.elapsed >= mission.duration { return mission.leg_distance, 0 }
    t := max(f64(0),mission.elapsed)
    if mission.max_speed_hours <= 0 { return min(mission.leg_distance,mission.max_speed*t), mission.max_speed }
    acceleration := mission.max_speed/mission.max_speed_hours
    ramp := min(mission.max_speed_hours,math.sqrt(mission.leg_distance/acceleration))
    peak := acceleration*ramp
    if t < ramp { return 0.5*acceleration*t*t, acceleration*t }
    if t > mission.duration-ramp {
        remaining := mission.duration-t
        return mission.leg_distance-0.5*acceleration*remaining*remaining, acceleration*remaining
    }
    return 0.5*peak*ramp + peak*(t-ramp), peak
}
@(private)
set_transport_phase :: proc(mission: ^Transport, phase: Transport_Phase, duration: f64) {
    mission.phase = phase
    mission.phase_elapsed = 0
    mission.phase_duration = duration
}
@(private)
start_return :: proc(mission: ^Transport) {
    mission.return_start = mission.travelled
    mission.leg_distance = mission.travelled
    mission.duration = travel_duration(mission.leg_distance,mission.max_speed,mission.max_speed_hours)
    mission.elapsed = 0
    mission.speed = 0
    set_transport_phase(mission,.Returning,mission.duration)
}
@(private)
withdraw_transport :: proc(state: ^Transport_State, mission: ^Transport) {
    mission.requested = 0
    switch mission.phase {
    case .Loading:
        // Unboarded people never left the station. Release their reservation now.
        for index in mission.manifest {
            subject := &state.subjects[index]
            if subject.activity == .Reserved {
                subject.activity = .Station
                subject.residence = ""
                for &stock in state.stock { if stock.subject_id == subject.subject_id { stock.units += 1; break } }
            }
        }
        mission.units = mission.loaded
        set_transport_phase(mission,.Return_Unloading,handling_duration(mission.loaded,mission.handling_rate))
    case .Landing, .Unloading:
        mission.takeoff_start = mission.landing_progress
        set_transport_phase(mission,.Taking_Off,LANDING_HOURS*mission.takeoff_start)
    case .Outbound, .Waiting_Landing:
        if mission.speed > 0 && mission.max_speed_hours > 0 {
            mission.brake_start = mission.travelled
            mission.brake_speed = mission.speed
            set_transport_phase(mission,.Braking,mission.speed*mission.max_speed_hours/mission.max_speed)
        } else { start_return(mission) }
    case .Taking_Off, .Braking, .Returning, .Return_Unloading, .Completed, .Cancelled:
    }
}
// A mission has one requesting residence. Withdraw exactly its undelivered
// reservation, once. Delivered passengers enter the independent evacuation request.
// Reactivation never resurrects ordinary cargo already committed to return.
reconcile_transports :: proc(state: ^Transport_State, game: ^State) {
    reconcile_evacuations(state,game)
    for &mission in state.missions[:state.count] {
        if mission.evacuation || mission.requested <= 0 { continue }
        for building, i in game.buildings {
            if building.id != mission.destination { continue }
            if !game.active[i] {
                state.reserved[i] = max(f32(0),state.reserved[i]-mission.requested)
                withdraw_transport(state,&mission)
            }
            break
        }
    }
}
// Atomic reservation on request; boarding transfers one individual at a time. Loading holds the ship at the station
// for units / handling_rate hours. A manifest allocates only on dispatch; all
// per-subject stepping reuses session storage. No event queues.
dispatch_transports :: proc(state: ^Transport_State, game: ^State, definitions: []Building_Type) {
    reconcile_transports(state,game)
    dispatch_evacuations(state,game)
    for building, i in game.buildings {
        if !game.active[i] || state.evacuation_pending[i] { continue }
        for definition in definitions {
            if definition.id != building.building_id || definition.residents.type == "" { continue }
            free := f32(math.floor(f64(definition.residents.capacity-state.occupants[i]-state.reserved[i])))
            if free < 1 { continue }
            for &stock in state.stock {
                if stock.subject_id != definition.residents.type { continue }
                for &available in state.available {
                    for ship in state.ships {
                        if ship.id != available.ship_id || ship.type != "transport" || ship.max_speed <= 0 || ship.units_per_hour <= 0 { continue }
                        capacity: f32
                        for passenger in ship.subjects { if passenger.subject_id == stock.subject_id { capacity = passenger.capacity; break } }
                        for available.units > 0 && state.count < TRANSPORT_LIMIT {
                            units := f32(math.floor(f64(min(free,min(stock.units,capacity)))))
                            if units < 1 { break }
                            route := max(f64(0),f64(state.distance)-LANDING_RANGE_KM)
                            mission := Transport{ship_id=ship.id,subject_id=stock.subject_id,destination=building.id,
                                units=units,requested=units,distance=f64(state.distance),leg_distance=route,max_speed=f64(ship.max_speed),
                                max_speed_hours=f64(ship.max_speed_hours),handling_rate=f64(ship.units_per_hour),handling_hours=handling_duration(units,f64(ship.units_per_hour)),
                                duration=travel_duration(route,f64(ship.max_speed),f64(ship.max_speed_hours))}
                            manifest := make([]int,int(units),state.allocator)
                            manifest_count := 0
                            for &subject, index in state.subjects {
                                if subject.subject_id != stock.subject_id || subject.activity != .Station { continue }
                                subject.activity = .Reserved
                                subject.residence = building.id
                                manifest[manifest_count] = index
                                manifest_count += 1
                                if manifest_count == len(manifest) { break }
                            }
                            mission.manifest = manifest
                            mission.units = f32(manifest_count)
                            mission.requested = mission.units
                            units = mission.units
                            if units == 0 { delete(manifest,state.allocator); break }
                            assert(manifest_count == len(manifest)) // Available stock is a cache of Station instances.
                            mission.handling_hours = handling_duration(units,mission.handling_rate)
                            set_transport_phase(&mission,.Loading,mission.handling_hours)
                            state.missions[state.count] = mission
                            state.count += 1
                            available.units -= 1
                            stock.units -= units
                            state.reserved[i] += units
                            free -= units
                        }
                    }
                }
            }
        }
    }
}
// Active platforms are exclusive during descent, unloading and takeoff.
// If none is available, hold at <=1 km without unloading or discarding passengers.
@(private)
reserve_platform :: proc(state: ^Transport_State, game: ^State, required: string = "") -> string {
    for building, i in game.buildings {
        if required != "" && building.id != required { continue }
        if building.building_id != "landing_platform" || !game.active[i] { continue }
        busy := false
        for mission in state.missions[:state.count] {
            if mission.platform_id == building.id && (mission.phase == .Landing || mission.phase == .Unloading || mission.phase == .Taking_Off) { busy = true; break }
        }
        if !busy { return building.id }
    }
    return ""
}
@(private)
advance_transport_phase :: proc(mission: ^Transport, remaining: ^f64) -> bool {
    needed := max(f64(0),mission.phase_duration-mission.phase_elapsed)
    used := min(remaining^,needed)
    mission.phase_elapsed += used
    remaining^ -= used
    if needed-used <= 1e-10 {
        mission.phase_elapsed = mission.phase_duration
        return true
    }
    return false
}
@(private)
deliver_passengers :: proc(state: ^Transport_State, game: ^State, mission: ^Transport, total: f32) {
    additional := max(f32(0),total-mission.delivered)
    if additional == 0 { return }
    for i in int(mission.delivered)..<int(total) {
        disembark_subject(state,game,mission.manifest[i],mission)
    }
    for &building, i in game.buildings {
        if building.id != mission.destination { continue }
        state.reserved[i] = max(f32(0),state.reserved[i]-additional)
        state.occupants[i] += additional
        building.residents_amount = state.occupants[i]
        mission.delivered += additional
        mission.requested = max(f32(0),mission.requested-additional)
        break
    }
}
// Advance all phases using one shared fixed tick; unused time carries across phase
// boundaries. At most 16 transitions per mission/tick, including zero-duration phases.
// Request withdrawal precedes progress, so disabled housing cannot receive this tick.
step_transports :: proc(state: ^Transport_State, game: ^State, definitions: []Building_Type) {
    reconcile_transports(state,game)
    step_station_subjects(state)
    step_subjects(state)
    for &mission in state.missions[:state.count] {
        remaining := f64(1)/TICKS_PER_HOUR
        for _ in 0..<16 {
            if mission.phase == .Completed || mission.phase == .Cancelled { break }
            if mission.phase == .Waiting_Landing {
                if mission.landing_ticket == 0 {
                    state.next_landing_ticket += 1
                    mission.landing_ticket = state.next_landing_ticket
                }
                mission.holding_platform_id = ""
                for building, i in game.buildings {
                    if building.building_id != "landing_platform" { continue }
                    if mission.holding_platform_id == "" || game.active[i] { mission.holding_platform_id = building.id }
                    if game.active[i] { break }
                }
                if mission.evacuation { mission.holding_platform_id = mission.pickup_platform_id }
                first := true
                for other in state.missions[:state.count] {
                    if other.phase == .Waiting_Landing && other.landing_ticket != 0 && other.landing_ticket < mission.landing_ticket && reserve_platform(state,game,other.pickup_platform_id) != "" { first = false; break }
                }
                if !first { break }
                platform := reserve_platform(state,game,mission.pickup_platform_id)
                if platform == "" { break }
                mission.platform_id = platform
                set_transport_phase(&mission,.Landing,LANDING_HOURS)
            }
            if mission.evacuation && mission.phase == .Unloading {
                if !board_evacuating_subjects(state,game,&mission,&remaining) { break }
                mission.arrived = true // Pickup complete; station handling still remains.
                mission.takeoff_start = 1
                set_transport_phase(&mission,.Taking_Off,LANDING_HOURS)
                continue
            }
            complete := advance_transport_phase(&mission,&remaining)
            switch mission.phase {
            case .Loading:
                loaded := complete ? mission.units : min(mission.units,f32(math.floor(mission.phase_elapsed*mission.handling_rate+1e-10)))
                for i in int(mission.loaded)..<int(loaded) { state.subjects[mission.manifest[i]].activity = .Onboard }
                mission.loaded = loaded
                if complete { set_transport_phase(&mission,.Outbound,mission.duration) }
            case .Outbound:
                mission.elapsed = mission.phase_elapsed
                mission.travelled, mission.speed = transport_position(mission)
                if complete { set_transport_phase(&mission,.Waiting_Landing,0) }
            case .Landing:
                mission.landing_progress = mission.phase_elapsed/LANDING_HOURS
                approach := max(f64(0),mission.distance-LANDING_RANGE_KM)
                mission.travelled = approach+(mission.distance-approach)*mission.landing_progress
                if complete {
                    set_transport_phase(&mission,.Unloading,mission.handling_hours)
                }
            case .Unloading:
                total := complete ? mission.loaded : min(mission.loaded,f32(math.floor(mission.phase_elapsed*mission.handling_rate+1e-10)))
                deliver_passengers(state,game,&mission,total)
                if complete {
                    deliver_passengers(state,game,&mission,mission.units)
                    mission.arrived = true
                    mission.takeoff_start = 1
                    set_transport_phase(&mission,.Taking_Off,LANDING_HOURS)
                }
            case .Taking_Off:
                fraction := mission.phase_duration <= 0 ? f64(1) : mission.phase_elapsed/mission.phase_duration
                mission.landing_progress = mission.takeoff_start*(1-fraction)
                approach := max(f64(0),mission.distance-LANDING_RANGE_KM)
                mission.travelled = approach+(mission.distance-approach)*mission.landing_progress
                if complete { start_return(&mission) }
            case .Braking:
                acceleration := mission.max_speed/mission.max_speed_hours
                t := mission.phase_elapsed
                mission.travelled = min(mission.distance,mission.brake_start+mission.brake_speed*t-0.5*acceleration*t*t)
                mission.speed = max(f64(0),mission.brake_speed-acceleration*t)
                if complete { start_return(&mission) }
            case .Returning:
                mission.elapsed = mission.phase_elapsed
                position, speed := transport_position(mission)
                mission.travelled = max(f64(0),mission.return_start-position)
                mission.speed = speed
                if complete { set_transport_phase(&mission,.Return_Unloading,handling_duration(mission.loaded-mission.delivered,mission.handling_rate)) }
            case .Return_Unloading:
                total := complete ? mission.loaded-mission.delivered : min(mission.loaded-mission.delivered,f32(math.floor(mission.phase_elapsed*mission.handling_rate+1e-10)))
                for i in int(mission.delivered+mission.returned)..<int(mission.delivered+total) {
                    subject := &state.subjects[mission.manifest[i]]
                    assert(subject.activity == .Onboard)
                    subject.activity = .Station
                    subject.residence = ""
                    if mission.evacuation {
                        subject.evacuating = false
                        subject.evacuation_reserved = false
                        subject.evacuation_platform = ""
                        subject.destination = ""
                        subject.position = {}
                        subject.target = {}
                        subject.wait_hours = 0
                    }
                    for &stock in state.stock { if stock.subject_id == subject.subject_id { stock.units += 1; break } }
                }
                mission.returned = total
                if complete {
                    for &available in state.available { if available.ship_id == mission.ship_id { available.units += 1; break } }
                    set_transport_phase(&mission,mission.arrived ? .Completed : .Cancelled,0)
                }
            case .Waiting_Landing, .Completed, .Cancelled:
            }
            if !complete { break }
        }
    }
    dispatch_transports(state,game,definitions)
}
// Independent mission value; strings borrow startup storage.
transport_snapshot :: proc(state: ^Transport_State, index: int) -> Transport {
    assert(index >= 0 && index < state.count)
    return state.missions[index]
}
// Remaining time in the current procedure/leg. Waiting for a pad has no finite ETA.
transport_eta :: proc(mission: Transport) -> f64 {
    if mission.evacuation && !mission.arrived { return -1 } // Individual arrival times may block pickup.
    left := max(f64(0),mission.phase_duration-mission.phase_elapsed)
    switch mission.phase {
    case .Loading: return left+mission.duration+LANDING_HOURS+mission.handling_hours
    case .Outbound: return left+LANDING_HOURS+mission.handling_hours
    case .Landing: return left+mission.handling_hours
    case .Returning: return left+handling_duration(transport_cargo(mission),mission.handling_rate)
    case .Taking_Off:
        return left+travel_duration(max(f64(0),mission.distance-LANDING_RANGE_KM),mission.max_speed,mission.max_speed_hours)+handling_duration(transport_cargo(mission),mission.handling_rate)
    case .Braking:
        end := mission.brake_start+mission.brake_speed*mission.phase_duration/2
        return left+travel_duration(end,mission.max_speed,mission.max_speed_hours)+handling_duration(transport_cargo(mission),mission.handling_rate)
    case .Waiting_Landing: return -1
    case .Unloading, .Return_Unloading: return left
    case .Completed, .Cancelled: return 0
    }
    return 0
}
