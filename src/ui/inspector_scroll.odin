package ui

import c "../contracts"

// Measured wrapping precedes pagination, so long text is reachable at a fixed size.
inspector_visible_lines :: proc(state: ^Scene_State, input: c.Input, bounds: c.Rect, rows, hint: []c.Info_Row) -> []c.Info_Row {
    return info_visible_rows(&state.info_scroll, input, bounds, rows, hint)
}
