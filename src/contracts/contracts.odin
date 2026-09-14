package contracts

Vector2 :: struct { x, y: f32 }
RGB :: struct { r, g, b: u8 }
// Stable catalog ID, independent of localized display names.
Building_Type_ID :: distinct string
CONTROL_UNIT_ID :: Building_Type_ID("control_unit")
// Snapshots are independent values; IDs are stable, never storage pointers.
Building_Snapshot :: struct {
    id: string,
    building_id: Building_Type_ID,
    position: Vector2,
    health: f32,
    repairing: bool,
    active: bool,
    power_output_kw, power_need_kw: f64,
}
Power_Balance :: struct {
    produced_kw, consumed_kw: f64,
    available_kw: f64,
}
Toggle_Building :: struct { id: string }
Toggle_Result :: enum { None, Applied, Control_Unit_Locked, Insufficient_Power, Generator_Required, Unknown_Building }
Building_Target :: struct { id: string, bounds: Rect }
NOTICE_VISIBLE_ROWS :: 4
Notice_Line :: struct { bounds: Rect, text: string }
// Value snapshot in chronological order; strings borrow startup localization.
Notice_View :: struct {
    bounds: Rect,
    lines: [NOTICE_VISIBLE_ROWS]Notice_Line,
    count: int,
}
Rect :: struct { x, y, width, height: f32 }
Action :: enum { None, Play, Load, Settings, Exit }
Input :: struct {
    width, height: f32,
    mouse_x, mouse_y: f32,
    mouse_moved, click, up, down, activate, focused, back: bool,
}
Button :: struct {
    bounds: Rect,
    label: string,
    selected: bool,
}
Menu_View :: struct {
    title: string,
    title_bounds: Rect,
    title_font_size: i32,
    buttons: [4]Button,
    font_size: i32,
    status: string,
}
