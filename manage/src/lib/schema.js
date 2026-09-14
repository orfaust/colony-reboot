// Validation rules for the asset files, derived from the strict Odin loaders
// (src/config, src/localization) and the current JSON layout:
//   config/buildings.json  — array of building types, identified by `id`
//   config/resources.json  — array of resources, identified by `id`
//   levels/*.json          — instances referencing a building type through `building_id`
// Keep these rules in sync when the Odin structures change.
import { isPlainObject } from './object.js';

export const BUILDINGS_PATH = 'config/buildings.json';
export const RESOURCES_PATH = 'config/resources.json';
export const TEXTS_PATH = 'localization/en.json';
export const CONTROL_UNIT_ID = 'control_unit'; // contracts.CONTROL_UNIT_ID

const u8 = { type: 'u8' };
const int = { type: 'int' };
const f32 = { type: 'f32' };
const str = { type: 'string' };
const bool = { type: 'bool' };
const obj = (fields) => ({ type: 'object', fields });
const arr = (item) => ({ type: 'array', item });

export const colorSchema = obj({ r: u8, g: u8, b: u8 });
export const needSchema = obj({ resource_id: str, amount_per_unit: f32 });
export const productSchema = obj({ resource_id: str, time_per_unit: f32 });
export const buildingTypeSchema = obj({
  id: str,
  name_key: str,
  description_key: str,
  code: str,
  width: f32,
  height: f32,
  color: colorSchema,
  power_need_kw: f32,
  power_output_kw: f32,
  needs: arr(needSchema),
  produces: arr(productSchema),
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
});
export const levelSchema = obj({ version: int, level: int, buildings: arr(buildingInstanceSchema) });

// Named fields of localization.Text; the game refuses to start without them.
export const POWER_FORMAT_KEYS = ['power_output_format', 'power_need_format', 'power_available_format'];
export const REQUIRED_TEXT_KEYS = [
  'window_title',
  'menu_title',
  'play',
  'load',
  'settings',
  'exit_game',
  'building_control_unit_name',
  'building_control_unit_description',
  'load_unavailable',
  'settings_unavailable',
  ...POWER_FORMAT_KEYS,
  'notice_insufficient_power',
  'notice_generator_required',
  'notice_control_unit_locked',
];

// Same relative tolerance as logic.power_shortage: f32 rounding only, no free power.
const powerShortage = (produced, consumed) => consumed - produced > Math.max(produced, consumed) * 1e-7;

export function detectKind(path) {
  if (path.startsWith('localization/')) return 'localization';
  if (path.startsWith('levels/')) return 'level';
  if (path === BUILDINGS_PATH) return 'buildings';
  if (path === RESOURCES_PATH) return 'resources';
  return 'generic';
}

function checkShape(value, schema, path, issues) {
  const error = (message) => issues.push({ level: 'error', path, message });
  switch (schema.type) {
    case 'object': {
      if (!isPlainObject(value)) return error('expected an object');
      for (const [name, child] of Object.entries(schema.fields)) {
        if (!(name in value)) issues.push({ level: 'error', path: `${path}.${name}`, message: 'required field is missing' });
        else checkShape(value[name], child, `${path}.${name}`, issues);
      }
      for (const key of Object.keys(value)) if (!(key in schema.fields)) error(`unknown field "${key}"`);
      return;
    }
    case 'array':
      if (!Array.isArray(value)) return error('expected an array (use [] for an empty list)');
      value.forEach((child, i) => checkShape(child, schema.item, `${path}[${i}]`, issues));
      return;
    case 'string':
      if (typeof value !== 'string' || value.trim() === '' || value.includes('\0'))
        error('expected a nonempty string without NUL characters');
      return;
    case 'bool':
      if (typeof value !== 'boolean') error('expected true or false');
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

export function validateBuildings(data, texts, resources) {
  if (!Array.isArray(data)) return [{ level: 'error', path: '$', message: 'expected an array of building types' }];
  const issues = [];
  if (data.length === 0) issues.push({ level: 'error', path: '$', message: 'at least one building type is required' });
  const resourceIds = Array.isArray(resources) ? new Set(resources.map((r) => r?.id)) : null;
  if (!resourceIds) issues.push({ level: 'warning', path: '$', message: `${RESOURCES_PATH} is missing or invalid; resource references are not checked` });

  data.forEach((d, i) => {
    const path = `$[${i}]`;
    checkShape(d, buildingTypeSchema, path, issues);
    if (!isPlainObject(d)) return;
    const label = `building "${d.id}"`;
    const previous = data.slice(0, i);
    if (previous.some((p) => p?.id === d.id)) issues.push({ level: 'error', path: `${path}.id`, message: `${label}: duplicate ID` });
    if (previous.some((p) => p?.code === d.code)) issues.push({ level: 'error', path: `${path}.code`, message: `${label}: duplicate code "${d.code}"` });
    // Range checks use Math.fround: the loader compares the stored f32, so 1e-50 is 0.
    if (!(Math.fround(d.width) > 0) || !(Math.fround(d.height) > 0))
      issues.push({ level: 'error', path, message: `${label}: width and height must be positive world-unit dimensions` });
    if (Math.fround(d.power_need_kw) < 0 || Math.fround(d.power_output_kw) < 0)
      issues.push({ level: 'error', path, message: `${label}: power values must be nonnegative kW` });
    checkTextKey(d.name_key, texts, `${path}.name_key`, issues);
    checkTextKey(d.description_key, texts, `${path}.description_key`, issues);
    const checkRecipe = (list, field, what, amountField, amountMessage) =>
      (Array.isArray(list) ? list : []).forEach((item, j) => {
        const p = `${path}.${field}[${j}]`;
        if (!(Math.fround(item?.[amountField]) > 0)) issues.push({ level: 'error', path: p, message: `${label} ${what}: ${amountMessage}` });
        if (resourceIds && !resourceIds.has(item?.resource_id))
          issues.push({ level: 'error', path: p, message: `${label} ${what}: resource_id "${item?.resource_id}" is not defined in ${RESOURCES_PATH}` });
      });
    checkRecipe(d.needs, 'needs', 'need', 'amount_per_unit', 'amount_per_unit must be positive');
    checkRecipe(d.produces, 'produces', 'product', 'time_per_unit', 'time_per_unit must be positive (hours per unit)');
  });
  return issues;
}

export function validateLevel(data, buildings, path) {
  const issues = [];
  checkShape(data, levelSchema, '$', issues);
  if (!isPlainObject(data)) return issues;
  if (data.version !== 1) issues.push({ level: 'error', path: '$.version', message: 'expected 1' });
  if (data.level !== 0)
    issues.push({
      level: path === 'levels/level_0.json' ? 'error' : 'warning',
      path: '$.level',
      message: 'the game currently only loads level 0 (expected 0 for the initial scene)',
    });
  const typeIds = Array.isArray(buildings) ? new Set(buildings.map((b) => b?.id)) : null;
  (Array.isArray(data.buildings) ? data.buildings : []).forEach((b, i) => {
    const p = `$.buildings[${i}]`;
    if (!isPlainObject(b)) return;
    if (typeIds && !typeIds.has(b.building_id))
      issues.push({ level: 'error', path: `${p}.building_id`, message: `unknown building_id "${b.building_id}"; define it in ${BUILDINGS_PATH}` });
    const health = Math.fround(b.health);
    if (!(health >= 0 && health <= 1)) issues.push({ level: 'error', path: `${p}.health`, message: 'health must be in [0,1]' });
    if (data.buildings.slice(0, i).some((prev) => prev?.id === b.id))
      issues.push({ level: 'error', path: `${p}.id`, message: `duplicate instance ID "${b.id}"` });
  });
  // Mirrors logic.initial_balance: only Control Units start active, so their
  // combined output must cover their combined need.
  const controlUnit = Array.isArray(buildings) ? buildings.find((t) => isPlainObject(t) && t.id === CONTROL_UNIT_ID) : undefined;
  if (controlUnit && Array.isArray(data.buildings)) {
    let produced = 0;
    let consumed = 0;
    for (const b of data.buildings) {
      if (b?.building_id !== CONTROL_UNIT_ID) continue;
      produced += Math.fround(controlUnit.power_output_kw);
      consumed += Math.fround(controlUnit.power_need_kw);
    }
    if (powerShortage(produced, consumed))
      issues.push({ level: 'error', path: '$.buildings', message: 'initial Control Unit power demand exceeds its output; only Control Units start active' });
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
  for (const key of POWER_FORMAT_KEYS)
    if (typeof data[key] === 'string' && !data[key].includes('{value}'))
      issues.push({ level: 'error', path: `$.${key}`, message: 'power format must contain the {value} placeholder' });
  return issues;
}

export function validateDoc(path, docs) {
  const data = docs[path]?.data;
  switch (detectKind(path)) {
    case 'buildings':
      return validateBuildings(data, docs[TEXTS_PATH]?.data, docs[RESOURCES_PATH]?.data);
    case 'resources':
      return validateResources(data, docs[TEXTS_PATH]?.data);
    case 'level':
      return validateLevel(data, docs[BUILDINGS_PATH]?.data, path);
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
