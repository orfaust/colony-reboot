// Validation rules for the asset files, derived from the strict Odin loaders
// (src/config, src/localization) and the current JSON layout. Paths are relative to
// the selected configuration version directory (assets/config/<version>/):
//   buildings.json         — array of building types, identified by `id`
//   resources.json         — array of resources, identified by `id`
//   levels/*.json          — instances referencing a building type through `building_id`
//   localization/en.json   — every player-facing UI text
// Keep these rules in sync when the Odin structures change.
import { isPlainObject } from './object.js';
import { storedIssues } from './stored.js';
import { KEY_DEFAULTS, INPUT_NAMES, normalizeInput } from './station.js';

export const BUILDINGS_PATH = 'buildings.json';
export const RESOURCES_PATH = 'resources.json';
export const SUBJECTS_PATH = 'subjects.json';
export const SUBJECT_ROLES_PATH = 'subject_roles.json';
export const SHIPS_PATH = 'ships.json';
export const STATIONS_PATH = 'space_stations.json';
export const KEY_BINDINGS_PATH = 'key_bindings.json';
export const TEXTS_PATH = 'localization/en.json';
export const CONTROL_UNIT_ID = 'control_unit'; // contracts.CONTROL_UNIT_ID

const u8 = { type: 'u8' };
const int = { type: 'int' };
const f32 = { type: 'f32' };
const str = { type: 'string' };
export const assetPathSchema = { ...str, format: 'asset-path', optional: true };
const bool = { type: 'bool' };
// `oneOf` lists field names of which exactly one must be present (Odin `config:"one_of"` tag).
const obj = (fields, oneOf = []) => ({ type: 'object', fields, oneOf });
const arr = (item) => ({ type: 'array', item });
const nullable = (schema) => ({ ...schema, nullable: true }); // Odin `config:"nullable"` tag
const enumOf = (values) => ({ type: 'enum', values });
// logic.valid_ship_type: ordinary dispatch uses transport; medical missions use emergency.
export const SHIP_TYPES = ['transport', 'emergency'];

export const keyBindingsSchema = obj(Object.fromEntries(Object.keys(KEY_DEFAULTS).map((key) => [key, key === 'version' ? int : arr(str)])));
export const colorSchema = obj({ r: u8, g: u8, b: u8 });
export const shipSchema = obj({ id: str, code: str, sprite: assetPathSchema, width: f32, height: f32, color: colorSchema, name_key: str, type: enumOf(SHIP_TYPES), max_speed: f32, max_speed_hours: f32, units_per_hour: f32, subjects: arr(obj({ subject_id: str, capacity: f32 })) });
export const stationSchema = obj({
  id: str,
  code: str,
  name_key: str,
  resources: arr(obj({ resource_id: str, capacity: f32 })),
  subjects: arr(obj({ subject_id: str, capacity: f32 })),
  ships: arr(obj({ ship_id: str, units: int })),
});

export const NEED_AMOUNT_FIELDS = ['amount_per_unit', 'amount_per_hour'];
// Matches logic.NEED_SLOT_LIMIT: runtime need state uses fixed per-subject arrays.
export const SUBJECT_NEED_LIMIT = 8;
export const needSchema = obj(
  { resource_id: str, amount_per_unit: f32, amount_per_hour: f32, capacity: f32 },
  NEED_AMOUNT_FIELDS,
);
// Building types only declare storage capacity; the units held belong to level instances (`stored`).
// A building product has one rate: units_per_hour. Per-capita consumption lives only in subject needs.
export const PRODUCT_RATE_FIELDS = ['units_per_hour'];
export const buildingProductSchema = obj({ resource_id: str, units_per_hour: f32, capacity: f32 }, PRODUCT_RATE_FIELDS);
// Subjects hold no stock: their products have no capacity or stored amount.
export const subjectProductSchema = obj({ resource_id: str, units_per_hour: f32 });
// A resource a building type can hold beyond its needs and products.
export const storageSchema = obj({ resource_id: str, capacity: f32 });
export const SUBJECT_ROLES = ['worker', 'supervisor', 'repairer']; // logic.Subject_Role
// logic.Staffing_Mode: continuous keeps every slot covered; on_demand waits for a request.
export const STAFFING_MODES = ['continuous', 'on_demand'];
export const buildingRoleSchema = obj({ role_id: enumOf(SUBJECT_ROLES), quantity: int, staffing_mode: enumOf(STAFFING_MODES) });
export const buildingTypeSchema = obj({
  id: str,
  sprite: assetPathSchema,
  name_key: str,
  description_key: str,
  code: str,
  width: f32,
  height: f32,
  color: colorSchema,
  power_need_kw: f32,
  power_output_kw: f32,
  always_on: bool, // must never be switched off (metadata for now)
  warmup_time: f32,
  cooldown_time: f32,
  min_operative_health: f32,
  materials_amount: f32,
  subject_roles: arr(buildingRoleSchema),
  residents: nullable(obj({ type: str, capacity: f32 })), // null: hosts no subjects; type is a subjects.json id
  needs: arr(needSchema),
  produces: arr(buildingProductSchema),
  storage: arr(storageSchema), // level instances keep a stored entry for these resources too
});
export const resourceSchema = obj({
  id: str,
  name_key: str,
  description_key: str,
  unit_type_key: str,
  color: colorSchema,
});
export const buildingInstanceSchema = obj({
  id: str,
  building_id: str,
  position: obj({ x: f32, y: f32 }),
  health: f32,
  repairing: bool,
  enable_at_start: bool,
  residents_amount: nullable(f32), // a number only when the building type has residents, null otherwise
  stored: arr(obj({ resource_id: str, amount: f32 })), // one entry per resource the building type produces
});
export const roleSchema = obj({ id: str, name_key: str });
export const subjectRoleSchema = obj({ role_id: enumOf(SUBJECT_ROLES), sprite: { ...str, optional: true } });
export const subjectNeedSchema = obj({
  resource_id: str,
  amount_per_hour: f32,
  shortage_alert_time: f32,
  shortage_max_time: f32,
  satisfied_health_gain_per_hour: f32,
  max_shortage_health_loss_per_hour: f32,
});
export const healthRatesSchema = obj({
  work_gain_per_hour: f32,
  rest_gain_per_hour: f32,
  extra_work_loss_per_hour: f32,
  max_inactivity_loss_per_hour: f32,
  inactivity_max_time: f32,
  station_recovery_per_hour: f32,
});
export const subjectTypeSchema = obj({
  id: str,
  width: f32,
  height: f32,
  sprite: assetPathSchema,
  name_key: str,
  color: colorSchema,
  rest_time: f32,
  work_time: f32,
  extra_work_time: f32,
  min_work_health: f32,
  min_colony_health: f32,
  health_rates: healthRatesSchema,
  roles: nullable(arr(subjectRoleSchema)), // roles the type can take, without duplicates; null (or []) means none
  // shortage_alert_time: hours without the resource before complaining (starving starts as soon as it is denied);
  // shortage_max_time: hours in shortage before dying or shutting down
  needs: arr(subjectNeedSchema),
  produces: arr(subjectProductSchema),
});
// initial_assignment replaces the former occupation: a building instance id plus a role, or null.
export const initialAssignmentSchema = obj({ building_id: str, role_id: enumOf(SUBJECT_ROLES) });
export const subjectInstanceSchema = obj({
  id: str,
  subject_id: str,
  residence: str,
  health: f32, // individual health in [0,1]; generated residents default to 1
  initial_assignment: nullable(initialAssignmentSchema),
  roles: arr(enumOf(SUBJECT_ROLES)), // nonempty, without duplicates
  speed: f32,
});
export const stationInstanceSchema = obj({
  station_id: str,
  distance: f32,
  resources: arr(obj({ resource_id: str, units: f32, units_per_hour: f32 })),
  subjects: arr(obj({ subject_id: str, units: f32, units_per_hour: f32 })),
});
export const levelSchema = obj({ version: int, level: int, buildings: arr(buildingInstanceSchema), subjects: arr(subjectInstanceSchema), space_station: stationInstanceSchema });

// Named fields of localization.Text; the game refuses to start without them.
export const POWER_FORMAT_KEYS = ['power_output_format', 'power_need_format', 'power_available_format'];
export const EXTRA_FORMAT_TOKENS = {
  notice_staffing_lost: ['{name}', '{id}'],
  notice_staffing_restored: ['{name}', '{id}'],
  notice_production_blocked: ['{name}', '{id}'],
  notice_production_resumed: ['{name}', '{id}'],
  notice_power_shed: ['{buildings}'],
  notice_insufficient_power: ['{name}', '{id}'],
  notice_insufficient_health: ['{name}', '{id}'],
  notice_always_on_locked: ['{name}', '{id}'],
  notice_generator_required: ['{name}', '{id}'],
  transport_cargo_format: ['{units}', '{name}', '{destination}'],
  transport_trip_format: ['{remaining}'],
  transport_speed_format: ['{speed}', '{max_speed}'],
  transport_eta_format: ['{status}', '{hours}'],
  transport_hours_format: ['{value}'],
  station_stock_format: ['{name}', '{units}', '{capacity}', '{rate}'],
  station_ship_format: ['{name}', '{units}'],
  building_info_health: ['{value}'],
  building_info_power_output: ['{value}'],
  building_info_power_need: ['{value}'],
  building_info_level: ['{value}'],
  building_info_residents: ['{name}', '{amount}', '{capacity}'],
  building_info_workers: ['{covered}', '{required}'],
  building_info_supervisors: ['{covered}', '{required}'],
  building_info_repairers: ['{covered}', '{required}'],
  building_info_coverage_reserved: ['{role}', '{reserved}'],
  building_info_coverage_ondemand: ['{role}', '{quantity}'],
  building_info_uncovered: ['{count}'],
  subject_info_identity: ['{name}', '{id}'],
  subject_info_health: ['{value}'],
  subject_info_phase: ['{value}'],
  subject_info_role: ['{value}'],
  subject_info_assignment: ['{value}'],
  subject_info_slot: ['{building}', '{slot}'],
  subject_info_timers: ['{work}', '{max_work}', '{rest}', '{max_rest}', '{idle}'],
  subject_info_medical: ['{value}'],
  subject_info_need_ok: ['{name}', '{value}'],
  subject_info_need_short: ['{name}', '{value}', '{hours}'],
  building_info_stock: ['{name}', '{amount}', '{capacity}', '{unit}'],
  building_info_stock_flow: ['{name}', '{consumed}', '{produced}', '{unit}'],
  building_info_production: ['{value}'],
  building_info_rate_hour: ['{value}', '{unit}'],
  building_info_rate_product: ['{value}', '{unit}'],
};
export const REQUIRED_TEXT_KEYS = [
  'transport_travelling', 'transport_arrived',
  'transport_loading', 'transport_waiting_landing', 'transport_landing', 'transport_unloading',
  'transport_taking_off', 'transport_braking', 'transport_returning', 'transport_return_unloading',
  'transport_cancelled', 'transport_eta_unknown', 'transport_awaiting_approval',
  'station_resources', 'station_subjects', 'station_ships', 'station_empty',
  'building_info_active', 'building_info_inactive', 'building_info_close',
  'building_info_subjects', 'building_info_no_residents', 'building_info_needs',
  'building_info_products', 'building_info_empty', 'building_info_stock_header', 'building_info_scroll', 'info_scroll_hint', 'building_info_no_staff',
  'modal_buildings_toggle', 'modal_subjects_toggle', 'modal_buildings_title', 'modal_subjects_title',
  'modal_scroll_hint', 'modal_none',
  'grid_building_code', 'grid_building_name', 'grid_building_state', 'grid_building_health',
  'grid_building_activity', 'grid_building_power_out', 'grid_building_power_need',
  'grid_building_residents', 'grid_building_staffing',
  'grid_building_needs', 'grid_building_products', 'grid_building_storage',
  'grid_subject_id', 'grid_subject_name', 'grid_subject_health', 'grid_subject_phase',
  'grid_subject_residence', 'grid_subject_occupation', 'grid_subject_role', 'grid_subject_medical', 'grid_subject_timers',
  'building_info_staffing', 'building_info_individuals', 'building_info_no_individuals',
  'subject_info_unassigned', 'subject_info_needs', 'subject_info_no_needs',
  'work_phase_idle', 'work_phase_resting', 'work_phase_reserved', 'work_phase_moving_to_work', 'work_phase_working', 'work_phase_extra_working',
  'medical_status_none', 'medical_status_pending_evacuation', 'medical_status_evacuating', 'medical_status_hospitalized', 'medical_status_returning',
  'production_state_operational', 'production_state_inactive', 'production_state_warming_up', 'production_state_unstaffed', 'production_state_missing_input', 'production_state_output_full',
  ...Object.keys(EXTRA_FORMAT_TOKENS),
  'window_title',
  'menu_title',
  'resume_game',
  'play',
  'load',
  'settings',
  'exit_game',
  'building_control_unit_name',
  'building_control_unit_description',
  'load_unavailable',
  'settings_unavailable',
  ...POWER_FORMAT_KEYS,
  'hud_clock_format',
  'notice_insufficient_power',
  'notice_generator_required',
  'notice_control_unit_locked',
  'notice_insufficient_health',
  'notice_staffing_lost',
  'notice_staffing_restored',
  'notice_medical_evacuation',
  'notice_medical_return',
  'notice_subject_died',
];

// Same relative tolerance as logic.power_shortage: f32 rounding only, no free power.
const powerShortage = (produced, consumed) => consumed - produced > Math.max(produced, consumed) * 1e-7;

export function detectKind(path) {
  if (path.startsWith('localization/')) return 'localization';
  if (path.startsWith('levels/')) return 'level';
  if (path === BUILDINGS_PATH) return 'buildings';
  if (path === RESOURCES_PATH) return 'resources';
  if (path === SUBJECTS_PATH) return 'subjects';
  if (path === SUBJECT_ROLES_PATH) return 'subject_roles';
  if (path === SHIPS_PATH) return 'ships';
  if (path === STATIONS_PATH) return 'space_stations';
  if (path === KEY_BINDINGS_PATH) return 'key_bindings';
  return 'generic';
}

function checkShape(value, schema, path, issues) {
  const error = (message) => issues.push({ level: 'error', path, message });
  if (schema.nullable && value === null) return;
  switch (schema.type) {
    case 'object': {
      if (!isPlainObject(value)) return error('expected an object');
      for (const [name, child] of Object.entries(schema.fields)) {
        if (name in value) checkShape(value[name], child, `${path}.${name}`, issues);
        else if (!child.optional && !schema.oneOf.includes(name)) issues.push({ level: 'error', path: `${path}.${name}`, message: 'required field is missing' });
      }
      if (schema.oneOf.length > 0 && schema.oneOf.filter((name) => name in value).length !== 1)
        error(`exactly one of ${schema.oneOf.join(', ')} is required`);
      for (const key of Object.keys(value)) if (!(key in schema.fields)) error(`unknown field "${key}"`);
      return;
    }
    case 'array':
      if (!Array.isArray(value)) return error('expected an array (use [] for an empty list)');
      value.forEach((child, i) => checkShape(child, schema.item, `${path}[${i}]`, issues));
      return;
    case 'string':
      if (schema.optional && value === '') return;
      if (typeof value !== 'string' || value.trim() === '' || value.includes('\0'))
        error('expected a nonempty string without NUL characters');
      return;
    case 'bool':
      if (typeof value !== 'boolean') error('expected true or false');
      return;
    case 'enum':
      if (!schema.values.includes(value)) error(`expected one of: ${schema.values.join(', ')}`);
      return;
    default: {
      if (typeof value !== 'number' || !Number.isFinite(value)) return error('expected a finite number');
      if (schema.type === 'u8' && (value < 0 || value > 255 || !Number.isInteger(value)))
        error('RGB channel must be an integer in [0,255]');
      if (schema.type === 'int' && (!Number.isInteger(value) || Math.abs(value) > 2147483647))
        error('expected a 32-bit integer');
      if (schema.type === 'f32' && Math.abs(value) > 3.402823466e38) error('number exceeds the f32 range');
    }
  }
}

function checkTextKey(key, texts, path, issues) {
  if (typeof key !== 'string' || key.trim() === '') return;
  const value = texts?.[key];
  if (typeof value !== 'string' || value.trim() === '')
    issues.push({ level: 'error', path, message: `localization key "${key}" is missing or empty in ${TEXTS_PATH}`, textKey: key });
}

export function validateResources(data, texts) {
  if (!Array.isArray(data)) return [{ level: 'error', path: '$', message: 'expected an array of resources' }];
  const issues = [];
  data.forEach((resource, i) => {
    const path = `$[${i}]`;
    checkShape(resource, resourceSchema, path, issues);
    if (!isPlainObject(resource)) return;
    if (data.slice(0, i).some((r) => r?.id === resource.id))
      issues.push({ level: 'error', path, message: `duplicate resource ID "${resource.id}"` });
    for (const field of ['name_key', 'description_key', 'unit_type_key']) checkTextKey(resource[field], texts, `${path}.${field}`, issues);
  });
  return issues;
}

/**
 * Product checks shared by building and subject types (config.decode_catalog / decode_subjects).
 * Building products take a rate and a capacity (stock lives in level `stored`); subject products only a units_per_hour.
 */
function checkProducts(list, path, label, resourceIds, issues, isSubject) {
  (Array.isArray(list) ? list : []).forEach((product, j) => {
    const error = (message) => issues.push({ level: 'error', path: `${path}.produces[${j}]`, message: `${label} product: ${message}` });
    // Absent rate fields count as zero, like the decoded Odin struct. Subject products have only units_per_hour.
    const rateFields = isSubject ? ['units_per_hour'] : PRODUCT_RATE_FIELDS;
    if (!(Math.max(...rateFields.map((f) => Math.fround(product?.[f] ?? 0))) > 0))
      error('units_per_hour must be positive');
    if (resourceIds && !resourceIds.has(product?.resource_id)) error(`resource_id "${product?.resource_id}" is not defined in ${RESOURCES_PATH}`);
    if (!isSubject && Math.fround(product?.capacity) < 0) error('capacity must be nonnegative');
  });
}

// Syntax only in the browser; python tools/build.py validates files before compilation.
export const SPRITE_PATH_ERROR = 'expected a normalized assets/.../*.png path using forward slashes, without parent traversal';
export function validSpritePath(path) {
  if (path === undefined || path === '') return true;
  return typeof path === 'string' && path.startsWith('assets/') && path.endsWith('.png') && path.trim() === path
    && !/[\\\\:\u0000]/.test(path) && path.split('/').every((part) => part && part !== '.' && part !== '..');
}
export function validateRoles(data, texts) {
  const issues = [];
  checkShape(data, arr(roleSchema), '$', issues);
  if (!Array.isArray(data)) return issues;
  data.forEach((role, i) => {
    if (!isPlainObject(role)) return;
    const path = `$[${i}]`;
    if (!SUBJECT_ROLES.includes(role.id)) issues.push({ level: 'error', path: `${path}.id`, message: 'unknown simulation role ID' });
    if (data.slice(0, i).some((previous) => previous?.id === role.id)) issues.push({ level: 'error', path: `${path}.id`, message: 'duplicate role ID' });
    checkTextKey(role.name_key, texts, `${path}.name_key`, issues);
  });
  for (const id of SUBJECT_ROLES) if (!data.some((role) => role?.id === id))
    issues.push({ level: 'error', path: '$', message: `missing required role "${id}"` });
  return issues;
}

export function validateBuildings(data, texts, resources, subjects) {
  if (!Array.isArray(data)) return [{ level: 'error', path: '$', message: 'expected an array of building types' }];
  const issues = [];
  if (data.length === 0) issues.push({ level: 'error', path: '$', message: 'at least one building type is required' });
  const subjectIds = Array.isArray(subjects) ? new Set(subjects.map((s) => s?.id)) : null;
  const resourceIds = Array.isArray(resources) ? new Set(resources.map((r) => r?.id)) : null;
  if (!resourceIds) issues.push({ level: 'warning', path: '$', message: `${RESOURCES_PATH} is missing or invalid; resource references are not checked` });

  data.forEach((d, i) => {
    const path = `$[${i}]`;
    checkShape(d, buildingTypeSchema, path, issues);
    if (!isPlainObject(d)) return;
    const label = `building "${d.id}"`;
    if (!validSpritePath(d.sprite)) issues.push({ level: 'error', path: `${path}.sprite`, message: SPRITE_PATH_ERROR });
    const previous = data.slice(0, i);
    if (previous.some((p) => p?.id === d.id)) issues.push({ level: 'error', path: `${path}.id`, message: `${label}: duplicate ID` });
    if (previous.some((p) => p?.code === d.code)) issues.push({ level: 'error', path: `${path}.code`, message: `${label}: duplicate code "${d.code}"` });
    // Range checks use Math.fround: the loader compares the stored f32, so 1e-50 is 0.
    if (!(Math.fround(d.width) > 0) || !(Math.fround(d.height) > 0))
      issues.push({ level: 'error', path, message: `${label}: width and height must be positive pixel dimensions` });
    if (Math.fround(d.power_need_kw) < 0 || Math.fround(d.power_output_kw) < 0)
      issues.push({ level: 'error', path, message: `${label}: power values must be nonnegative kW` });
    // Mirrors config.decode_catalog: a building either produces or consumes power, and
    // an always_on type must never consume because it can never be stopped.
    if (Math.fround(d.power_need_kw) > 0 && Math.fround(d.power_output_kw) > 0)
      issues.push({ level: 'error', path, message: `${label}: power_need_kw and power_output_kw are mutually exclusive; a building either produces or consumes power` });
    if (d.always_on === true && Math.fround(d.power_need_kw) > 0)
      issues.push({ level: 'error', path: `${path}.power_need_kw`, message: `${label}: always_on requires power_need_kw == 0` });
    if (Math.fround(d.warmup_time) < 0 || Math.fround(d.cooldown_time) < 0)
      issues.push({ level: 'error', path, message: `${label}: warmup_time and cooldown_time must be nonnegative hours` });
    const minHealth = Math.fround(d.min_operative_health);
    if (!(minHealth >= 0 && minHealth <= 1))
      issues.push({ level: 'error', path: `${path}.min_operative_health`, message: `${label}: min_operative_health must be in [0,1]` });
    if (Math.fround(d.materials_amount) < 0) issues.push({ level: 'error', path: `${path}.materials_amount`, message: `${label}: materials_amount must be nonnegative` });
    if (Array.isArray(d.subject_roles)) d.subject_roles.forEach((role, j) => {
      if (!Number.isInteger(role?.quantity) || role.quantity < 0) issues.push({ level: 'error', path: `${path}.subject_roles[${j}].quantity`, message: 'quantity must be a nonnegative integer' });
      if (d.subject_roles.slice(0, j).some((r) => r?.role_id === role?.role_id)) issues.push({ level: 'error', path: `${path}.subject_roles[${j}].role_id`, message: 'duplicate role_id' });
    });
    // Mirrors config.decode_catalog / validate_residents: null, or a subject type with a positive capacity.
    const hostsResidents = isPlainObject(d.residents);
    if (hostsResidents) {
      if (!(Math.fround(d.residents.capacity) > 0))
        issues.push({ level: 'error', path: `${path}.residents.capacity`, message: `${label}: residents.capacity must be positive` });
      if (subjectIds && typeof d.residents.type === 'string' && !subjectIds.has(d.residents.type))
        issues.push({ level: 'error', path: `${path}.residents.type`, message: `${label}: residents.type "${d.residents.type}" is not defined in ${SUBJECTS_PATH}` });
    }
    checkTextKey(d.name_key, texts, `${path}.name_key`, issues);
    checkTextKey(d.description_key, texts, `${path}.description_key`, issues);
    // Absent amount fields count as zero, like the decoded Odin struct.
    const checkRecipe = (list, field, what, amountFields, amountMessage) =>
      (Array.isArray(list) ? list : []).forEach((item, j) => {
        const p = `${path}.${field}[${j}]`;
        const amount = Math.max(...amountFields.map((f) => Math.fround(item?.[f] ?? 0)));
        if (!(amount > 0)) issues.push({ level: 'error', path: p, message: `${label} ${what}: ${amountMessage}` });
        if (resourceIds && !resourceIds.has(item?.resource_id))
          issues.push({ level: 'error', path: p, message: `${label} ${what}: resource_id "${item?.resource_id}" is not defined in ${RESOURCES_PATH}` });
      });
    checkRecipe(d.needs, 'needs', 'need', NEED_AMOUNT_FIELDS, 'amount_per_unit or amount_per_hour must be positive');
    (Array.isArray(d.needs) ? d.needs : []).forEach((need, j) => {
      if (Math.fround(need?.capacity) < 0) issues.push({ level: 'error', path: `${path}.needs[${j}]`, message: `${label} need: capacity must be nonnegative` });
      // The first product is the reference ratio for every per-unit need.
      const reference = Array.isArray(d.produces) ? Math.fround(d.produces[0]?.units_per_hour ?? 0) : 0;
      if (Math.fround(need?.amount_per_unit) > 0 && !(reference > 0))
        issues.push({ level: 'error', path: `${path}.needs[${j}]`, message: `${label} need: amount_per_unit requires the first produces entry to have a positive units_per_hour (the reference product)` });
    });
    checkProducts(d.produces, path, label, resourceIds, issues, false);
    // Mirrors config.decode_catalog: storage entries reference resources, without duplicates.
    (Array.isArray(d.storage) ? d.storage : []).forEach((stock, j) => {
      const error = (message) => issues.push({ level: 'error', path: `${path}.storage[${j}]`, message: `${label} storage: ${message}` });
      if (Math.fround(stock?.capacity) < 0) error('capacity must be nonnegative');
      if (resourceIds && !resourceIds.has(stock?.resource_id)) error(`resource_id "${stock?.resource_id}" is not defined in ${RESOURCES_PATH}`);
      if (d.storage.findIndex((o) => o?.resource_id === stock?.resource_id) !== j) error(`duplicate resource_id "${stock?.resource_id}"`);
    });
  });
  return issues;
}

export function validateSubjects(data, texts, resources) {
  if (!Array.isArray(data)) return [{ level: 'error', path: '$', message: 'expected an array of subject types' }];
  const issues = [];
  const resourceIds = Array.isArray(resources) ? new Set(resources.map((r) => r?.id)) : null;
  if (!resourceIds) issues.push({ level: 'warning', path: '$', message: `${RESOURCES_PATH} is missing or invalid; resource references are not checked` });
  data.forEach((s, i) => {
    const path = `$[${i}]`;
    checkShape(s, subjectTypeSchema, path, issues);
    if (!isPlainObject(s)) return;
    const label = `subject "${s.id}"`;
    for (const field of ['width', 'height']) if (!(Math.fround(s[field]) > 0))
      issues.push({ level: 'error', path: `${path}.${field}`, message: `${field} must be a positive pixel dimension` });
    if (!validSpritePath(s.sprite)) issues.push({ level: 'error', path: `${path}.sprite`, message: SPRITE_PATH_ERROR });
    if (data.slice(0, i).some((p) => p?.id === s.id)) issues.push({ level: 'error', path: `${path}.id`, message: `${label}: duplicate ID` });
    checkTextKey(s.name_key, texts, `${path}.name_key`, issues);
    (Array.isArray(s.needs) ? s.needs : []).forEach((need, j) => {
      const p = `${path}.needs[${j}]`;
      if (!(Math.fround(need?.amount_per_hour) > 0)) issues.push({ level: 'error', path: p, message: `${label} need: amount_per_hour must be positive` });
      if (Math.fround(need?.shortage_alert_time) < 0) issues.push({ level: 'error', path: p, message: `${label} need: shortage_alert_time must be nonnegative hours` });
      if (Math.fround(need?.shortage_max_time) < 0) issues.push({ level: 'error', path: p, message: `${label} need: shortage_max_time must be nonnegative hours` });
      if (!(Math.fround(need?.satisfied_health_gain_per_hour) >= 0)) issues.push({ level: 'error', path: p, message: `${label} need: satisfied_health_gain_per_hour must be nonnegative` });
      if (!(Math.fround(need?.max_shortage_health_loss_per_hour) >= 0)) issues.push({ level: 'error', path: p, message: `${label} need: max_shortage_health_loss_per_hour must be nonnegative` });
      if (resourceIds && !resourceIds.has(need?.resource_id))
        issues.push({ level: 'error', path: p, message: `${label} need: resource_id "${need?.resource_id}" is not defined in ${RESOURCES_PATH}` });
    });
    if (Array.isArray(s.needs) && s.needs.length > SUBJECT_NEED_LIMIT)
      issues.push({ level: 'error', path: `${path}.needs`, message: `${label}: at most ${SUBJECT_NEED_LIMIT} needs are supported per subject type` });
    if (Math.fround(s.rest_time) < 0 || Math.fround(s.work_time) < 0)
      issues.push({ level: 'error', path, message: `${label}: rest_time and work_time must be nonnegative hours` });
    if (!(Math.fround(s.extra_work_time) >= 0))
      issues.push({ level: 'error', path: `${path}.extra_work_time`, message: `${label}: extra_work_time must be nonnegative hours` });
    const minColony = Math.fround(s.min_colony_health);
    const minWork = Math.fround(s.min_work_health);
    if (!(minColony >= 0 && minWork <= 1 && minColony < minWork))
      issues.push({ level: 'error', path, message: `${label}: health thresholds must satisfy 0 <= min_colony_health < min_work_health <= 1` });
    if (isPlainObject(s.health_rates)) {
      for (const [field, value] of Object.entries(s.health_rates)) {
        if (!(Math.fround(value) >= 0))
          issues.push({ level: 'error', path: `${path}.health_rates.${field}`, message: `${label}: health rate must be nonnegative` });
      }
    }
    if (Array.isArray(s.roles)) {
      if (new Set(s.roles.map((r) => r?.role_id)).size !== s.roles.length)
        issues.push({ level: 'error', path: `${path}.roles`, message: `${label}: duplicate role` });
      s.roles.forEach((r, j) => {
        if (!validSpritePath(r?.sprite)) issues.push({ level: 'error', path: `${path}.roles[${j}].sprite`, message: SPRITE_PATH_ERROR });
      });
    }
    checkProducts(s.produces, path, label, resourceIds, issues, true);
  });
  return issues;
}

export function validateLevel(data, buildings, path, subjects, stations) {
  const issues = [];
  checkShape(data, levelSchema, '$', issues);
  if (!isPlainObject(data)) return issues;
  issues.push(...validateStationInstance(data.space_station, stations, false));
  const initialSubjects = Array.isArray(data.subjects) ? data.subjects : [];
  let population = initialSubjects.length;
  for (const stock of Array.isArray(data.space_station?.subjects) ? data.space_station.subjects : []) population += Number.isFinite(stock?.units) ? stock.units : 0;
  for (const building of Array.isArray(data.buildings) ? data.buildings : []) {
    const explicit = initialSubjects.filter((s) => s?.residence === building?.id).length;
    population += Math.max(0, (Number.isFinite(building?.residents_amount) ? building.residents_amount : 0) - explicit);
  }
  if (population > 16384) issues.push({ level: 'error', path: '$', message: 'initial subjects exceed the runtime limit of 16384; reduce station stock or initial residents' });
  if (data.version !== 1) issues.push({ level: 'error', path: '$.version', message: 'expected 1' });
  if (data.level !== 0)
    issues.push({
      level: path === 'levels/level_0.json' ? 'error' : 'warning',
      path: '$.level',
      message: 'the game currently only loads level 0 (expected 0 for the initial scene)',
    });
  const typeIds = Array.isArray(buildings) ? new Set(buildings.map((b) => b?.id)) : null;
  const typeById = Array.isArray(buildings) ? new Map(buildings.filter(isPlainObject).map((t) => [t.id, t])) : null;
  (Array.isArray(data.buildings) ? data.buildings : []).forEach((b, i) => {
    const p = `$.buildings[${i}]`;
    if (!isPlainObject(b)) return;
    if (typeIds && !typeIds.has(b.building_id))
      issues.push({ level: 'error', path: `${p}.building_id`, message: `unknown building_id "${b.building_id}"; define it in ${BUILDINGS_PATH}` });
    const health = Math.fround(b.health);
    if (!(health >= 0 && health <= 1)) issues.push({ level: 'error', path: `${p}.health`, message: 'health must be in [0,1]' });
    if (data.buildings.slice(0, i).some((prev) => prev?.id === b.id))
      issues.push({ level: 'error', path: `${p}.id`, message: `duplicate instance ID "${b.id}"` });
    // Mirrors logic.toggle: a building below its operative health cannot be activated.
    const type = typeById?.get(b.building_id);
    if (type?.always_on === true && b.enable_at_start !== true)
      issues.push({ level: 'error', path: `${p}.enable_at_start`, message: `enable_at_start must be true because "${b.building_id}" is always_on` });
    if (type && b.enable_at_start === true && b.building_id !== CONTROL_UNIT_ID && Math.fround(b.health) < Math.fround(type.min_operative_health))
      issues.push({
        level: 'error',
        path: `${p}.enable_at_start`,
        message: `enable_at_start requires health of at least min_operative_health (${type.min_operative_health})`,
      });
    if (type && Array.isArray(b.stored)) issues.push(...storedIssues(b, type, p));
    // Mirrors config.decode_level: a number in [0, residents.capacity] with residents, null otherwise.
    if (type && 'residents_amount' in b) {
      const hosted = isPlainObject(type.residents) ? type.residents : null;
      const amount = b.residents_amount;
      const error = (message) => issues.push({ level: 'error', path: `${p}.residents_amount`, message });
      if (hosted && typeof amount !== 'number') error(`residents_amount must be a number because "${b.building_id}" has residents`);
      else if (hosted && !Number.isInteger(amount)) error('residents_amount must be a whole number of subjects');
      else if (hosted && !(Math.fround(amount) >= 0 && Math.fround(amount) <= Math.fround(hosted.capacity)))
        error(`residents_amount must be in [0, residents.capacity] (${hosted.capacity})`);
      else if (!hosted && amount !== null) error(`residents_amount must be null because "${b.building_id}" has no residents`);
    }
  });
  // Mirrors config.decode_level: subjects reference their type and building instances of this level.
  const subjectTypeIds = Array.isArray(subjects) ? new Set(subjects.map((s) => s?.id)) : null;
  const instanceIds = new Set((Array.isArray(data.buildings) ? data.buildings : []).map((b) => b?.id));
  const instanceById = new Map((Array.isArray(data.buildings) ? data.buildings : []).filter(isPlainObject).map((b) => [b.id, b]));
  (Array.isArray(data.subjects) ? data.subjects : []).forEach((s, i) => {
    const p = `$.subjects[${i}]`;
    if (!isPlainObject(s)) return;
    if (subjectTypeIds && !subjectTypeIds.has(s.subject_id))
      issues.push({ level: 'error', path: `${p}.subject_id`, message: `unknown subject_id "${s.subject_id}"; define it in ${SUBJECTS_PATH}` });
    if (data.subjects.slice(0, i).some((prev) => prev?.id === s.id))
      issues.push({ level: 'error', path: `${p}.id`, message: `duplicate subject ID "${s.id}"` });
    if (typeof s.residence === 'string' && !instanceIds.has(s.residence))
      issues.push({ level: 'error', path: `${p}.residence`, message: `residence "${s.residence}" is not a building instance ID in this level` });
    // The residence type must host this subject type, within residents.capacity per instance.
    const home = instanceById.get(s.residence);
    const homeType = home && typeById?.get(home.building_id);
    if (homeType) {
      const hosted = isPlainObject(homeType.residents) ? homeType.residents : null;
      if (hosted?.type !== s.subject_id)
        issues.push({
          level: 'error',
          path: `${p}.residence`,
          message: `residence "${s.residence}" (${home.building_id}) cannot host subject type "${s.subject_id}"; set residents.type`,
        });
      const residents = data.subjects.slice(0, i + 1).filter((o) => o?.residence === s.residence).length;
      if (hosted && residents > Math.fround(hosted.capacity))
        issues.push({ level: 'error', path: `${p}.residence`, message: `residence "${s.residence}" exceeds its residents.capacity (${hosted.capacity})` });
    }
    if (!(Math.fround(s.health) >= 0 && Math.fround(s.health) <= 1))
      issues.push({ level: 'error', path: `${p}.health`, message: 'health must be in [0,1]' });
    if (!(Math.fround(s.speed) > 0)) issues.push({ level: 'error', path: `${p}.speed`, message: 'speed must be positive' });
    if (Array.isArray(s.roles) && new Set(s.roles).size !== s.roles.length)
      issues.push({ level: 'error', path: `${p}.roles`, message: 'duplicate role' });
    // Instance roles come from the subject type's roles; a type with null roles takes none, so its instances use [].
    const subjectType = Array.isArray(subjects) ? subjects.find((t) => isPlainObject(t) && t.id === s.subject_id) : null;
    const allowedRoles = subjectType && Array.isArray(subjectType.roles) ? subjectType.roles.map((r) => r?.role_id) : [];
    if (subjectType && Array.isArray(s.roles)) {
      if (s.roles.length === 0 && allowedRoles.length > 0)
        issues.push({ level: 'error', path: `${p}.roles`, message: `roles must list at least one role of subject type "${s.subject_id}"` });
      for (const role of new Set(s.roles))
        if (!allowedRoles.includes(role))
          issues.push({ level: 'error', path: `${p}.roles`, message: `role "${role}" is not in the roles of subject type "${s.subject_id}"` });
    }
    // Mirrors config.decode_level: initial_assignment references a continuous slot the subject can perform.
    if (isPlainObject(s.initial_assignment)) {
      const assignment = s.initial_assignment;
      const assignedPath = `${p}.initial_assignment`;
      if (typeof assignment.building_id === 'string' && !instanceIds.has(assignment.building_id))
        issues.push({ level: 'error', path: `${assignedPath}.building_id`, message: `"${assignment.building_id}" must be a building instance ID in this level` });
      if (subjectType && Array.isArray(s.roles) && !s.roles.includes(assignment.role_id))
        issues.push({ level: 'error', path: `${assignedPath}.role_id`, message: `subject cannot perform role "${assignment.role_id}"; list it in the subject's roles` });
      const assignedBuilding = instanceById.get(assignment.building_id);
      const assignedType = assignedBuilding && typeById?.get(assignedBuilding.building_id);
      if (assignedType) {
        const rows = Array.isArray(assignedType.subject_roles) ? assignedType.subject_roles : [];
        const slot = rows.some((row) => isPlainObject(row) && row.role_id === assignment.role_id && row.staffing_mode === 'continuous' && Number.isInteger(row.quantity) && row.quantity > 0);
        if (!slot)
          issues.push({ level: 'error', path: `${assignedPath}.role_id`, message: `"${assignment.building_id}" has no continuous slot for role "${assignment.role_id}"` });
      }
    }
  });
  // Mirrors logic.initial_balance: Control Units and enable_at_start buildings start active,
  // so their combined output must cover their combined need.
  if (typeById && Array.isArray(data.buildings)) {
    let produced = 0;
    let consumed = 0;
    for (const b of data.buildings) {
      if (!isPlainObject(b) || !(b.building_id === CONTROL_UNIT_ID || b.enable_at_start === true)) continue;
      const type = typeById.get(b.building_id);
      if (!type) continue;
      produced += Math.fround(type.power_output_kw);
      consumed += Math.fround(type.power_need_kw);
    }
    if (powerShortage(produced, consumed))
      issues.push({ level: 'error', path: '$.buildings', message: 'initial power demand of Control Units and enable_at_start buildings exceeds their output' });
  }
  return issues;
}

export function validateLocalization(data) {
  if (!isPlainObject(data)) return [{ level: 'error', path: '$', message: 'expected an object of key → text' }];
  const issues = [];
  for (const [key, value] of Object.entries(data)) {
    if (typeof value !== 'string') issues.push({ level: 'error', path: `$.${key}`, message: 'value must be a string' });
    else if (value.trim() === '' || value.includes('\0'))
      issues.push({ level: 'error', path: `$.${key}`, message: 'text must be nonempty and without NUL characters' });
  }
  for (const key of REQUIRED_TEXT_KEYS)
    if (!(key in data)) issues.push({ level: 'error', path: `$.${key}`, message: 'required UI text is missing' });
  for (const [key, tokens] of Object.entries(EXTRA_FORMAT_TOKENS))
    for (const token of tokens)
      if (typeof data[key] === 'string' && !data[key].includes(token))
        issues.push({ level: 'error', path: `$.${key}`, message: `format must contain the ${token} placeholder` });
  for (const key of POWER_FORMAT_KEYS)
    if (typeof data[key] === 'string' && !data[key].includes('{value}'))
      issues.push({ level: 'error', path: `$.${key}`, message: 'power format must contain the {value} placeholder' });
  for (const placeholder of ['{hours}', '{speed}'])
    if (typeof data.hud_clock_format === 'string' && !data.hud_clock_format.includes(placeholder))
      issues.push({ level: 'error', path: '$.hud_clock_format', message: `clock format must contain the ${placeholder} placeholder` });
  return issues;
}

export function validateKeyBindings(data) {
  const issues = [];
  checkShape(data, keyBindingsSchema, '$', issues);
  if (!isPlainObject(data)) return issues;
  const error = (path, message) => issues.push({ level: 'error', path, message });
  if (data.version !== 1) error('$.version', 'expected 1');
  for (const action of Object.keys(KEY_DEFAULTS).filter((k) => k !== 'version')) {
    const inputs = data[action];
    if (!Array.isArray(inputs)) continue;
    if (!inputs.length) error(`$.${action}`, 'bind at least one input');
    inputs.forEach((input, i) => {
      const path = `$.${action}[${i}]`;
      const normalized = normalizeInput(input);
      if (!INPUT_NAMES.includes(normalized)) error(path, 'unknown input; select a key, mouse button, or wheel direction');
      if (action === 'pan' && normalized.startsWith('wheel:')) error(path, 'pan requires an input that can be held, not a wheel direction');
      if (inputs.indexOf(input) !== i) error(path, 'duplicate input');
    });
  }
  return issues;
}

export function validateShips(data, texts, subjects) {
  const issues = [];
  checkShape(data, arr(shipSchema), '$', issues);
  if (!Array.isArray(data)) return issues;
  data.forEach((ship, i) => {
    if (!isPlainObject(ship)) return;
    checkTextKey(ship.name_key, texts, `$[${i}].name_key`, issues);
    if (!validSpritePath(ship.sprite)) issues.push({ level: 'error', path: `$[${i}].sprite`, message: SPRITE_PATH_ERROR });
    for (const field of ['width', 'height']) if (!(Math.fround(ship[field]) > 0))
      issues.push({ level: 'error', path: `$[${i}].${field}`, message: `${field} must be a positive pixel dimension` });
    for (const field of ['max_speed_hours', 'units_per_hour']) {
      if (!(Math.fround(ship[field]) >= 0)) issues.push({ level: 'error', path: `$[${i}].${field}`, message: `${field} must be nonnegative (${field === 'units_per_hour' ? 'cargo units per simulated hour; zero disables dispatch' : 'acceleration/braking hours'})` });
    }
    if (!(Math.fround(ship.max_speed) >= 0)) issues.push({ level: 'error', path: `$[${i}].max_speed`, message: 'max_speed must be nonnegative (km/h)' });
    if (data.slice(0, i).some((s) => s?.id === ship.id)) issues.push({ level: 'error', path: `$[${i}].id`, message: 'duplicate ship ID' });
    const passengers = Array.isArray(ship.subjects) ? ship.subjects : [];
    passengers.forEach((row, j) => {
      if (!isPlainObject(row)) return;
      const path = `$[${i}].subjects[${j}]`;
      if (!Array.isArray(subjects) || !subjects.some((s) => s?.id === row.subject_id))
        issues.push({ level: 'error', path: `${path}.subject_id`, message: 'subject_id must reference subjects.json' });
      if (!(Math.fround(row.capacity) >= 0))
        issues.push({ level: 'error', path: `${path}.capacity`, message: 'capacity must be nonnegative' });
      if (passengers.slice(0, j).some((previous) => previous?.subject_id === row.subject_id))
        issues.push({ level: 'error', path: `${path}.subject_id`, message: 'duplicate subject_id' });
    });
  });
  return issues;
}

export function validateStation(data, texts, catalogs) {
  const issues = [];
  checkShape(data, stationSchema, '$', issues);
  if (!isPlainObject(data)) return issues;
  checkTextKey(data.name_key, texts, '$.name_key', issues);
  for (const [field, idField, source] of [['resources', 'resource_id', RESOURCES_PATH], ['subjects', 'subject_id', SUBJECTS_PATH], ['ships', 'ship_id', SHIPS_PATH]]) {
    const catalog = catalogs[field];
    const ids = Array.isArray(catalog) ? new Set(catalog.map((x) => x?.id)) : null;
    if (!ids) issues.push({ level: 'warning', path: `$.${field}`, message: `${source} is missing or invalid; references are not checked` });
    const rows = Array.isArray(data[field]) ? data[field] : [];
    rows.forEach((row, i) => {
      if (!isPlainObject(row)) return;
      const path = `$.${field}[${i}]`;
      const error = (key, message) => issues.push({ level: 'error', path: `${path}.${key}`, message });
      if (ids && !ids.has(row[idField])) error(idField, `unknown ID; define it in ${source}`);
      if (rows.slice(0, i).some((r) => r?.[idField] === row[idField])) error(idField, 'duplicate stock ID');
      if (field === 'ships') {
        if (!(row.units >= 0)) error('units', 'units must be nonnegative');
      } else if (!(Math.fround(row.capacity) >= 0)) error('capacity', 'capacity must be nonnegative');
    });
  }
  return issues;
}

export function validateStationInstance(data, stations, shape = true) {
  const issues = [];
  const root = '$.space_station';
  if (shape) checkShape(data, stationInstanceSchema, root, issues);
  if (!isPlainObject(data)) return issues;
  const error = (path, message) => issues.push({ level: 'error', path, message });
  if (!(Math.fround(data.distance) >= 0)) error(`${root}.distance`, 'distance must be nonnegative (km)');
  if (!Array.isArray(stations)) {
    issues.push({ level: 'warning', path: root, message: `${STATIONS_PATH} is missing or invalid; station references are not checked` });
    return issues;
  }
  const station = stations.find((s) => isPlainObject(s) && s.id === data.station_id);
  if (!station) { error(`${root}.station_id`, `unknown station_id; define it in ${STATIONS_PATH}`); return issues; }
  for (const [field, idField] of [['resources', 'resource_id'], ['subjects', 'subject_id']]) {
    const definitions = Array.isArray(station[field]) ? station[field] : [];
    const rows = Array.isArray(data[field]) ? data[field] : [];
    for (const definition of definitions) {
      if (isPlainObject(definition) && !rows.some((r) => r?.[idField] === definition[idField]))
        error(`${root}.${field}`, `missing stock for ${definition[idField]}; sync with station template`);
    }
    rows.forEach((row, i) => {
      if (!isPlainObject(row)) return;
      const path = `${root}.${field}[${i}]`;
      const definition = definitions.find((d) => isPlainObject(d) && d[idField] === row[idField]);
      if (!definition) error(`${path}.${idField}`, 'ID is not in the selected station template');
      if (rows.slice(0, i).some((r) => r?.[idField] === row[idField])) error(`${path}.${idField}`, 'duplicate stock ID');
      if (field === 'subjects' && !Number.isInteger(row.units)) error(`${path}.units`, 'must be a whole number of subjects');
      if (!(Math.fround(row.units) >= 0) || (definition && Math.fround(row.units) > Math.fround(definition.capacity)))
        error(`${path}.units`, `units must be in [0, capacity]${definition ? ` (${definition.capacity})` : ''}`);
    });
  }
  return issues;
}

export function validateStations(data, texts, catalogs) {
  if (!Array.isArray(data)) return [{ level: 'error', path: '$', message: 'expected an array of space stations' }];
  return data.flatMap((station, i) => {
    const issues = validateStation(station, texts, catalogs).map((issue) => ({ ...issue, path: `$[${i}]${issue.path.slice(1)}` }));
    if (isPlainObject(station) && data.slice(0, i).some((s) => s?.id === station.id))
      issues.push({ level: 'error', path: `$[${i}].id`, message: 'duplicate station ID' });
    return issues;
  });
}

export function validateDoc(path, docs) {
  const data = docs[path]?.data;
  switch (detectKind(path)) {
    case 'key_bindings': return validateKeyBindings(data);
    case 'ships': return validateShips(data, docs[TEXTS_PATH]?.data, docs[SUBJECTS_PATH]?.data);
    case 'space_stations': return validateStations(data, docs[TEXTS_PATH]?.data, { resources: docs[RESOURCES_PATH]?.data, subjects: docs[SUBJECTS_PATH]?.data, ships: docs[SHIPS_PATH]?.data });
    case 'buildings':
      return validateBuildings(data, docs[TEXTS_PATH]?.data, docs[RESOURCES_PATH]?.data, docs[SUBJECTS_PATH]?.data);
    case 'resources':
      return validateResources(data, docs[TEXTS_PATH]?.data);
    case 'subject_roles':
      return validateRoles(data, docs[TEXTS_PATH]?.data);
    case 'subjects':
      return validateSubjects(data, docs[TEXTS_PATH]?.data, docs[RESOURCES_PATH]?.data);
    case 'level':
      return validateLevel(data, docs[BUILDINGS_PATH]?.data, path, docs[SUBJECTS_PATH]?.data, docs[STATIONS_PATH]?.data);
    case 'localization':
      return validateLocalization(data);
    default:
      return [];
  }
}

/** Collects every `*_key` string reference across non-localization docs. */
export function collectTextReferences(docs) {
  const refs = new Map();
  const walk = (value, file, path) => {
    if (Array.isArray(value)) value.forEach((v, i) => walk(v, file, `${path}[${i}]`));
    else if (isPlainObject(value))
      for (const [k, v] of Object.entries(value)) {
        if (k.endsWith('_key') && typeof v === 'string') {
          if (!refs.has(v)) refs.set(v, []);
          refs.get(v).push({ file, path: `${path}.${k}` });
        } else walk(v, file, `${path}.${k}`);
      }
  };
  for (const [file, doc] of Object.entries(docs)) if (!file.startsWith('localization/') && doc.data !== undefined) walk(doc.data, file, '$');
  for (const key of REQUIRED_TEXT_KEYS) {
    if (!refs.has(key)) refs.set(key, []);
    refs.get(key).push({ file: 'game code', path: 'required UI text' });
  }
  return refs;
}
