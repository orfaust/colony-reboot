package main

import "core:testing"
import "../logic"

// Regression for the pause contract: while the menu is shown (in_game == false)
// no fixed simulation tick may run, and the paused interval must not be caught up
// when the player resumes.
@(test)
menu_pauses_session_time :: proc(t: ^testing.T) {
    clock := logic.Clock{}
    // Any amount of frame time while paused produces no ticks and no pending progress.
    testing.expect(t, session_ticks(false,&clock,1.0/60.0) == 0 && clock.ticks == 0 && clock.pending_ticks == 0)
    testing.expect(t, session_ticks(false,&clock,3600) == 0 && clock.ticks == 0 && clock.pending_ticks == 0)
    // Resuming advances only the new frame, never the paused backlog. Frame time is
    // clamped to MAX_FRAME_SECONDS, so one second advances 0.25s * 60 = 15 ticks.
    testing.expect(t, session_ticks(true,&clock,1.0) == 15 && clock.ticks == 15)
    testing.expect(t, session_ticks(false,&clock,100) == 0 && clock.ticks == 15)
    testing.expect(t, session_ticks(true,&clock,0.5) == 15 && clock.ticks == 30)
    // A sub-tick remainder is preserved across a pause, exactly as speed changes do.
    clock = {}
    testing.expect(t, session_ticks(true,&clock,1.0/240.0) == 0 && clock.ticks == 0)
    before := clock.pending_ticks
    testing.expect(t, abs(before-0.25) < 1e-9)
    testing.expect(t, session_ticks(false,&clock,10) == 0 && clock.pending_ticks == before)
    testing.expect(t, session_ticks(true,&clock,0.5) == 15 && clock.ticks == 15)
    testing.expect(t, abs(clock.pending_ticks-before) < 1e-9)
}
