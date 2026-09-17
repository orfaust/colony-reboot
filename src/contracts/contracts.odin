package contracts

// Subject IDs are stable within a session; never array addresses.
Subject_ID :: distinct u64
Move_Subject :: struct { id: Subject_ID, destination: string }
Move_Subject_Result :: enum { Applied, Unknown_Subject, Unknown_Destination, Unavailable }
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
    active: bool, // Requested activity; gameplay eligibility changes immediately.
    staffed: bool, // Every continuous staffing slot is physically covered; independent of `active`.
    energized: bool, // Full demand persists until inactive AND level zero; not visual brightness.
    level: f64, // Startup progress in [0,1]: warmup raises it, cooldown lowers it.
    power_output_kw, power_need_kw: f64,
}
// One building instance's runtime stock record. `resource_id` borrows validated
// catalog/level storage, so it stays valid for the whole session. `logic.stock_snapshot`
// returns a borrowed slice of these records: unlike the copied building/subject
// snapshots, it points at authoritative storage and is invalidated by the next
// mutation (simulation step, reset or destroy). Consumers must not retain it.
Stock_Snapshot :: struct {
    resource_id: string,
    amount: f64, // Current units, clamped to [0, capacity] by the owning logic step.
    capacity: f64, // Resolved maximum units for this resource on this building type.
}
// Live evaluation of one building's hourly recipe. None means the recipe would run
// at the next whole simulated hour; every other value is the reason it would be
// skipped. The order is the presentation precedence: a missing input outranks a
// full output store, and inactivity outranks both.
Production_Block :: enum {
    None,
    Inactive,
    Warming_Up,
    Unstaffed,
    Missing_Input,
    Output_Full,
}
// Resolved hourly flow of one building resource at the current catalog values:
// amount_per_hour directly, amount_per_unit scaled by the first produces entry
// (the reference product). Per-resident rates are not resolved yet. resource_id
// borrows validated catalog storage and stays valid for the whole session.
Production_Rate :: struct {
    resource_id: string,
    consumed_per_hour: f64,
    produced_per_hour: f64,
}
Power_Balance :: struct {
    produced_kw, consumed_kw: f64,
    available_kw: f64,
}
Toggle_Building :: struct { id: string }
// Generator_Required rejects any active type with positive configured power output,
// regardless of current ramped output or network demand. Control Units have their own lock.
Toggle_Result :: enum { None, Applied, Control_Unit_Locked, Insufficient_Health, Insufficient_Power, Generator_Required, Unknown_Building, Always_On_Locked }
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
// Steps through the logic's ordered simulation speed levels.
Speed_Change :: enum { Faster, Slower }
Clock_Snapshot :: struct {
    elapsed_hours: i64, // Whole simulated hours since the session started.
    speed: i64, // Simulated hours per real second.
}
// Shared screen-space text metrics keep measurement, pagination and drawing aligned.
INFO_FONT_SIZE :: f32(24)
INFO_ROW_HEIGHT :: f32(26)
INFO_PADDING :: f32(8)
// Wrapped rows borrow frame text; source index preserves title color across wrapping.
Info_Row :: struct { text: string, title: bool }
// Clock text borrows frame-temporary storage and is consumed synchronously.
Hud_View :: struct {
    bounds: Rect,
    clock: string,
    // Wrapped station rows borrow frame storage; rendering consumes them synchronously.
    station_bounds: Rect,
    station_rows: []Info_Row,
    // Inspector text borrows frame storage and is consumed synchronously.
    info_bounds: Rect,
    info_rows: []Info_Row,
    info_title_color: RGB, // Element color, supplied by the application adapter.
    transport_bounds: Rect,
    transports: []Transport_Card, // Frame-owned presentation, consumed synchronously.
    // Overview toggles and the optional modal grid they open.
    toggles: [2]Modal_Toggle,
    modal: Modal_View,
}
// Minimum screen-space card height; wrapped rows determine the actual height.
TRANSPORT_CARD_HEIGHT :: f32(176)
Transport_Card :: struct {
    bounds: Rect,
    ship_color, subject_color: RGB,
    passengers: int, // Renderer clips icons to the card; text retains the full count.
    subject_sprite: string, // Borrowed preloaded subject/role sprite path; empty preserves subject color.
    lines: []string, // Semantic lines supplied by the application.
    rows: []Info_Row, // Renderer-measured wrapping, consumed by UI layout and drawing.
    approve_id: u64, // Pending ordinary request awaiting approval; 0 when none.
    approve_bounds: Rect, // UI-filled rocket button hit area, empty when not actionable.
}
// Stable ordinary-mission identity; never a storage index into logic state.
Approve_Transport :: struct { id: u64 }

// Bottom-right overview toggles open a modal grid of every element of one kind.
Modal_Kind :: enum { None, Buildings, Subjects }
Modal_Toggle :: struct {
    bounds: Rect,
    label: string, // Localized, supplied by the application.
    active: bool,
}
Modal_Row :: struct {
    cells: []string, // Frame-owned text, one entry per column.
    swatch: RGB, // Configured element color shown as a small square.
    has_swatch: bool, // False when the element has no configured color to show.
}
// The application owns the full grid; UI paginates and render only draws rows.
Modal_View :: struct {
    kind: Modal_Kind,
    bounds: Rect,
    title: string,
    columns: []string,
    rows: []Modal_Row, // Visible page only, already clipped by UI pagination.
    hint: string,
}
Action :: enum { None, Play, Load, Settings, Exit, Resume }
Input :: struct {
    width, height: f32,
    mouse_x, mouse_y: f32,
    zoom: f32, // Signed zoom steps this frame; positive zooms in.
    pan_x, pan_y: f32, // Cursor movement while a pan binding is held, in screen units.
    mouse_moved, click, up, down, activate, focused, back: bool,
    reload_requested: bool, // Development-only consumed Ctrl+R edge; never a gameplay binding.
    right_pressed, right_released: bool,
    speed_up, slow_down: bool,
    toggle_buildings, toggle_subjects: bool, // Overview panel toggles; resolved bindings.
}
// Input names per action, as written in key_bindings.json (profile-relative). Names are
// engine-neutral text here; the renderer resolves them to platform codes.
Key_Bindings :: struct {
    version: int,
    menu_up, menu_down, activate, back, select, zoom_in, zoom_out, pan: []string,
    speed_up, slow_down: []string,
    overview_buildings, overview_subjects: []string,
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
    buttons: [5]Button,
    button_count: int, // Visible entries; Resume Game is hidden until a session is paused.
    font_size: i32,
    status: string,
}
