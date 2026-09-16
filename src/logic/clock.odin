package logic

import "core:math"
import c "../contracts"

// At 1x one simulated hour passes per real second.
HOURS_PER_SECOND :: f64(1)
// Fixed simulation step: one simulated minute, independent of the frame rate.
TICKS_PER_HOUR :: 60
// Ordered speed levels in simulated hours per real second; index 0 is the default.
SPEEDS :: [?]i64{1, 2, 4, 8, 16, 32}
// Real time beyond this per advance (window drag, debugger, stall) is dropped
// rather than caught up, bounding one advance to MAX_FRAME_SECONDS*60*32 = 480 ticks.
MAX_FRAME_SECONDS :: f64(0.25)

// Value type owned by the session; the zero value is a fresh clock at 1x.
Clock :: struct {
    ticks: i64,
    pending_ticks: f64, // Fractional progress toward the next tick, in [0,1).
    speed_index: int,
}

// Returns the number of fixed steps to simulate this frame. Negative, NaN, and
// zero intervals advance nothing. Game rules must step per tick, never per frame.
advance_clock :: proc(clock: ^Clock, elapsed_seconds: f64) -> int {
    if math.is_nan(elapsed_seconds) || elapsed_seconds <= 0 { return 0 }
    speeds := SPEEDS
    seconds := min(elapsed_seconds, MAX_FRAME_SECONDS)
    clock.pending_ticks += seconds * HOURS_PER_SECOND * TICKS_PER_HOUR * f64(speeds[clock.speed_index])
    steps := math.floor(clock.pending_ticks)
    clock.pending_ticks -= steps
    clock.ticks += i64(steps)
    return int(steps)
}

// Saturates at the slowest and fastest levels. Pending progress is kept, so a
// change applies from the next advance without skipping or repeating ticks.
change_speed :: proc(clock: ^Clock, change: c.Speed_Change) -> bool {
    next := clock.speed_index + (change == .Faster ? 1 : -1)
    if next < 0 || next >= len(SPEEDS) { return false }
    clock.speed_index = next
    return true
}

clock_snapshot :: proc(clock: Clock) -> c.Clock_Snapshot {
    speeds := SPEEDS
    return {elapsed_hours = clock.ticks / TICKS_PER_HOUR, speed = speeds[clock.speed_index]}
}
