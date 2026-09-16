package logic

import "core:math"

// Requests are recorded on the same reconciliation used after successful toggles.
// Cooldown requests are reversible; reaching zero commits the remaining residents.
// No extra queue: per-building flags and per-person ownership are session-owned.
reconcile_evacuations :: proc(state: ^Transport_State, game: ^State) {
    for building, i in game.buildings {
        if state.last_active[i] && !game.active[i] && state.occupants[i] > 0 {
            state.evacuation_pending[i] = true
            for &subject in state.subjects {
                if subject.residence == building.id && (subject.activity == .Inside || subject.activity == .Moving || subject.activity == .Waiting) {
                    subject.evacuating = true
                }
            }
        }
        state.last_active[i] = game.active[i]
        if !state.evacuation_pending[i] { continue }
        if game.active[i] && !state.evacuation_started[i] {
            state.evacuation_pending[i] = false
            for &subject in state.subjects { if subject.residence == building.id { subject.evacuating = false } }
            continue
        }
        if !state.evacuation_started[i] && game.level[i] > 0 { continue }
        state.evacuation_started[i] = true
        remaining := false
        for &subject in state.subjects {
            if subject.residence != building.id || !subject.evacuating { continue }
            remaining = true
            if subject.evacuation_platform != "" { continue }
            // Stable walking anchor, not an exclusive ship reservation. A missing
            // active platform leaves the person safely at their current location.
            for platform, p in game.buildings {
                if platform.building_id != "landing_platform" || !game.active[p] { continue }
                subject.evacuation_platform = platform.id
                subject.destination = platform.id
                subject.target = platform.position
                subject.activity = .Waiting
                subject.wait_hours = 0
                for other in state.subjects {
                    if other.id == subject.id || !other.evacuating || other.evacuation_platform != platform.id || other.position != subject.position { continue }
                    if other.activity == .Waiting {
                        subject.wait_hours = max(subject.wait_hours,other.wait_hours+SUBJECT_LINE_SPACING/(SUBJECT_WALK_SPEED*f64(subject.speed)))
                    }
                }
                break
            }
        }
        if !remaining {
            state.evacuation_pending[i] = false
            state.evacuation_started[i] = false
        }
    }
}

// Includes both ordinary cargo return reservations and planned evacuation seats.
// Stock is never increased until an actual individual leaves a ship at station.
evacuation_station_room :: proc(state: ^Transport_State, subject_id: string) -> f32 {
    capacity: f64
    for entry in state.station.subjects { if entry.subject_id == subject_id { capacity = math.floor(f64(entry.capacity)); break } }
    found := false
    for stock in state.stock { if stock.subject_id == subject_id { capacity -= f64(stock.units); found = true; break } }
    if !found { return 0 }
    capacity -= station_reserved_subjects(state,subject_id)
    return f32(max(f64(0),capacity))
}

// Pickup dispatch follows building, station-ship and individual storage order.
// Requests have priority over new immigration, but never steal a ship/pad/subject
// already assigned. Full station capacity and mission-log limits leave demand pending.
dispatch_evacuations :: proc(state: ^Transport_State, game: ^State) {
    for building, i in game.buildings {
        if !state.evacuation_pending[i] || !state.evacuation_started[i] { continue }
        for &available in state.available {
            for ship in state.ships {
                if ship.id != available.ship_id || ship.type != "transport" || ship.max_speed <= 0 || ship.units_per_hour <= 0 { continue }
                for available.units > 0 && state.count < TRANSPORT_LIMIT {
                    first := -1
                    capacity: f32
                    for subject, index in state.subjects {
                        if !subject.evacuating || subject.evacuation_reserved || subject.residence != building.id || subject.evacuation_platform == "" { continue }
                        capacity = 0
                        for entry in ship.subjects { if entry.subject_id == subject.subject_id { capacity = entry.capacity; break } }
                        capacity = min(capacity,evacuation_station_room(state,subject.subject_id))
                        if capacity >= 1 { first = index; break }
                    }
                    if first < 0 { break }
                    person := state.subjects[first]
                    count := 0
                    for subject in state.subjects {
                        if subject.evacuating && !subject.evacuation_reserved && subject.residence == building.id && subject.subject_id == person.subject_id && subject.evacuation_platform == person.evacuation_platform { count += 1 }
                    }
                    units := min(count,int(min(f32(SUBJECT_LIMIT),capacity)))
                    manifest := make([]int,units,state.allocator)
                    n := 0
                    for &subject, index in state.subjects {
                        if !subject.evacuating || subject.evacuation_reserved || subject.residence != building.id || subject.subject_id != person.subject_id || subject.evacuation_platform != person.evacuation_platform { continue }
                        subject.evacuation_reserved = true
                        manifest[n] = index
                        n += 1
                        if n == units { break }
                    }
                    route := max(f64(0),f64(state.distance)-LANDING_RANGE_KM)
                    mission := Transport{evacuation=true,ship_id=ship.id,subject_id=person.subject_id,destination=building.id,
                        pickup_platform_id=person.evacuation_platform,manifest=manifest,units=f32(units),distance=f64(state.distance),
                        leg_distance=route,max_speed=f64(ship.max_speed),max_speed_hours=f64(ship.max_speed_hours),
                        handling_rate=f64(ship.units_per_hour),handling_hours=handling_duration(f32(units),f64(ship.units_per_hour)),
                        duration=travel_duration(route,f64(ship.max_speed),f64(ship.max_speed_hours))}
                    // Empty flight; no fictitious station loading or stock withdrawal.
                    set_transport_phase(&mission,.Outbound,mission.duration)
                    state.missions[state.count] = mission
                    state.count += 1
                    available.units -= 1
                }
            }
        }
    }
}

// Runs only while the mission exclusively owns its pad. Handling credit accrues
// only when the next manifest person has physically arrived, never while walking.
board_evacuating_subjects :: proc(state: ^Transport_State, game: ^State, mission: ^Transport, remaining: ^f64) -> bool {
    for mission.loaded < mission.units {
        subject := &state.subjects[mission.manifest[int(mission.loaded)]]
        if subject.activity != .Inside || subject.destination != mission.platform_id || subject.position != subject.target { return false }
        target_time := handling_duration(mission.loaded+1,mission.handling_rate)
        needed := max(f64(0),target_time-mission.phase_elapsed)
        used := min(remaining^,needed)
        mission.phase_elapsed += used
        remaining^ -= used
        if needed-used > 1e-10 { return false }
        mission.phase_elapsed = target_time
        for &building, i in game.buildings {
            if building.id != subject.residence { continue }
            assert(state.occupants[i] >= 1)
            state.occupants[i] -= 1
            building.residents_amount = state.occupants[i]
            break
        }
        subject.residence = ""
        subject.occupation = ""
        subject.activity = .Onboard
        mission.loaded += 1
    }
    return true
}
