// Edits the game loader rejects must also be errors in the asset manager.
// Each case starts from a fresh copy of the shipped assets.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { BUILDINGS_PATH, CONTROL_UNIT_ID, POWER_FORMAT_KEYS, RESOURCES_PATH, SUBJECTS_PATH, SHIPS_PATH, STATIONS_PATH, TEXTS_PATH, validateDoc } from '../src/lib/schema.js';

const LEVEL_PATH = 'levels/level_0.json';
const assetsDir = new URL('../../assets/', import.meta.url);
const shipped = Object.fromEntries(
  [TEXTS_PATH, RESOURCES_PATH, BUILDINGS_PATH, SUBJECTS_PATH, SHIPS_PATH, STATIONS_PATH, LEVEL_PATH].map((path) => [path, JSON.parse(readFileSync(new URL(path, assetsDir), 'utf8'))]),
);

/** Fresh copy of the shipped assets, shaped like the App's docs map. */
const loadDocs = () => Object.fromEntries(Object.entries(shipped).map(([path, data]) => [path, { data: structuredClone(data) }]));
const errors = (docs, path) => validateDoc(path, docs).filter((issue) => issue.level === 'error');
const hasError = (docs, file, path) => errors(docs, file).some((issue) => issue.path === path);

test('shipped assets have no errors', () => {
  const docs = loadDocs();
  for (const path of Object.keys(docs)) assert.deepEqual(errors(docs, path), [], path);
});

test('localization: every text field the game requires is checked', () => {
  const keys = [
    ...POWER_FORMAT_KEYS,
    'hud_clock_format',
    'notice_insufficient_power',
    'notice_generator_required',
    'notice_control_unit_locked',
    'notice_insufficient_health',
  ];
  for (const key of keys) {
    const docs = loadDocs();
    delete docs[TEXTS_PATH].data[key];
    assert.ok(hasError(docs, TEXTS_PATH, `$.${key}`), `missing ${key}`);
  }
});

test('localization: power formats need the {value} placeholder', () => {
  for (const key of POWER_FORMAT_KEYS) {
    const docs = loadDocs();
    docs[TEXTS_PATH].data[key] = 'kW';
    assert.ok(hasError(docs, TEXTS_PATH, `$.${key}`), key);
  }
});

test('localization: the clock format needs {hours} and {speed}', () => {
  for (const format of ['Hour {hours}', 'x{speed}']) {
    const docs = loadDocs();
    docs[TEXTS_PATH].data.hud_clock_format = format;
    assert.ok(hasError(docs, TEXTS_PATH, '$.hud_clock_format'), format);
  }
});

test('level: Control Unit demand above its output is rejected', () => {
  const docs = loadDocs();
  assert.ok(docs[LEVEL_PATH].data.buildings.some((b) => b.building_id === CONTROL_UNIT_ID), 'level 0 places a Control Unit');
  const controlUnit = docs[BUILDINGS_PATH].data.find((t) => t.id === CONTROL_UNIT_ID);
  // Independent of the shipped level: only Control Units start active here.
  for (const b of docs[LEVEL_PATH].data.buildings) if (b.building_id !== CONTROL_UNIT_ID) b.enable_at_start = false;

  controlUnit.power_output_kw = 0;
  controlUnit.power_need_kw = 0.001;
  assert.ok(hasError(docs, LEVEL_PATH, '$.buildings'), 'positive demand with zero output');

  controlUnit.power_output_kw = 1000;
  controlUnit.power_need_kw = 1000.00005;
  assert.ok(!hasError(docs, LEVEL_PATH, '$.buildings'), 'differences within f32 rounding are tolerated');
});

test('buildings: positive values that round to zero as f32 are rejected', () => {
  const docs = loadDocs();
  const [building] = docs[BUILDINGS_PATH].data;
  const resourceId = docs[RESOURCES_PATH].data[0].id;
  building.width = 1e-50;
  building.needs = [{ resource_id: resourceId, amount_per_unit: 1e-50 }];
  building.produces = [{ resource_id: resourceId, units_per_hour: 1e-50 }];
  assert.ok(hasError(docs, BUILDINGS_PATH, '$[0]'), 'width');
  assert.ok(hasError(docs, BUILDINGS_PATH, '$[0].needs[0]'), 'amount_per_unit');
  assert.ok(hasError(docs, BUILDINGS_PATH, '$[0].produces[0]'), 'units_per_hour');
});

test('buildings: operative health, materials, staffing and product storage ranges', () => {
  const resource_id = shipped[RESOURCES_PATH][0].id;
  const buildingErrors = (patch, remove) => {
    const docs = loadDocs();
    const building = docs[BUILDINGS_PATH].data[0];
    Object.assign(building, patch);
    if (remove) delete building[remove];
    return errors(docs, BUILDINGS_PATH).length > 0;
  };
  const product = { resource_id, units_per_hour: 1, capacity: 10 };
  assert.ok(!buildingErrors({ min_operative_health: 1, materials_amount: 25, subject_roles: [{ role_id: 'supervisor', quantity: 1, required: true }, { role_id: 'worker', quantity: 2.5, required: true }], produces: [product] }), 'valid');
  assert.ok(buildingErrors({ min_operative_health: 1.5 }), 'health above 1');
  assert.ok(buildingErrors({ min_operative_health: -0.1 }), 'negative health');
  assert.ok(!buildingErrors({ always_on: true }), 'always_on true');
  assert.ok(!buildingErrors({ always_on: false }), 'always_on false');
  assert.ok(buildingErrors({ always_on: 'true' }), 'always_on not a boolean');
  assert.ok(buildingErrors({ always_on: null }), 'null always_on');
  assert.ok(buildingErrors({}, 'always_on'), 'missing always_on');
  for (const field of ['materials_amount']) {
    assert.ok(buildingErrors({ [field]: -1 }), `negative ${field}`);
    assert.ok(buildingErrors({}, field), `missing ${field}`);
  }
  assert.ok(buildingErrors({ produces: [{ ...product, capacity: -1 }] }), 'negative capacity');
  assert.ok(buildingErrors({ produces: [{ ...product, stored: 0 }] }), 'stored belongs to level instances');
  const { capacity: _capacity, ...withoutCapacity } = product;
  assert.ok(buildingErrors({ produces: [withoutCapacity] }), 'missing capacity');
  const need = { resource_id, amount_per_unit: 1, capacity: 5 };
  assert.ok(!buildingErrors({ needs: [need] }), 'need with capacity');
  assert.ok(buildingErrors({ needs: [{ ...need, capacity: -1 }] }), 'negative need capacity');
  const { capacity: _needCapacity, ...needWithoutCapacity } = need;
  assert.ok(buildingErrors({ needs: [needWithoutCapacity] }), 'missing need capacity');
  const subjectId = shipped[SUBJECTS_PATH][0].id;
  const residents = { type: subjectId, capacity: 4 };
  assert.ok(!buildingErrors({ residents }), 'valid residents');
  assert.ok(!buildingErrors({ residents: null }), 'no residents');
  assert.ok(buildingErrors({ residents: { ...residents, type: 'unknown_subject' } }), 'unknown residents.type');
  assert.ok(buildingErrors({ residents: { ...residents, capacity: 0 } }), 'zero residents.capacity');
  assert.ok(buildingErrors({ residents: { type: subjectId } }), 'missing residents.capacity');
  assert.ok(buildingErrors({ residents: { capacity: 4 } }), 'missing residents.type');
  assert.ok(buildingErrors({ residents: [subjectId] }), 'residents not an object');
  assert.ok(buildingErrors({}, 'residents'), 'missing residents');
  assert.ok(buildingErrors({ residents, host_type: [subjectId] }), 'legacy host_type field');
  const residentNeed = { resource_id, amount_per_resident: 0.08, capacity: 10 };
  assert.ok(!buildingErrors({ residents, needs: [residentNeed] }), 'per-resident need with residents');
  assert.ok(buildingErrors({ residents: null, needs: [residentNeed] }), 'per-resident need without residents');
  const residentProduct = { resource_id, amount_per_resident: 0.25, capacity: 10 };
  assert.ok(!buildingErrors({ residents, produces: [residentProduct] }), 'per-resident product with residents');
  assert.ok(buildingErrors({ residents: null, produces: [residentProduct] }), 'per-resident product without residents');
  assert.ok(buildingErrors({ residents, produces: [{ ...residentProduct, amount_per_resident: 0 }] }), 'zero per-resident product');
  assert.ok(buildingErrors({ residents, produces: [{ ...residentProduct, units_per_hour: 1 }] }), 'units_per_hour and amount_per_resident');
  assert.ok(buildingErrors({ produces: [{ resource_id, time_per_unit: 1, capacity: 10 }] }), 'legacy time_per_unit on a building product');
  assert.ok(buildingErrors({ produces: [{ ...product, units_per_hour: 0 }] }), 'zero units_per_hour');
  assert.ok(buildingErrors({ residents, produces: [{ resource_id, capacity: 10 }] }), 'product without a rate');
  const stock = { resource_id, capacity: 50 };
  assert.ok(!buildingErrors({ storage: [stock] }), 'storage entry');
  assert.ok(!buildingErrors({ storage: [] }), 'empty storage');
  assert.ok(buildingErrors({ storage: [{ ...stock, capacity: -1 }] }), 'negative storage capacity');
  assert.ok(buildingErrors({ storage: [{ resource_id: 'unknown_resource', capacity: 1 }] }), 'unknown storage resource');
  assert.ok(buildingErrors({ storage: [stock, stock] }), 'duplicate storage resource');
  assert.ok(buildingErrors({ storage: [{ resource_id }] }), 'missing storage capacity');
  assert.ok(buildingErrors({ storage: [{ ...stock, amount: 1 }] }), 'unknown storage field');
  assert.ok(buildingErrors({}, 'storage'), 'missing storage');
});

test('level: enable_at_start instances need operative health and count toward initial power', () => {
  const docs = loadDocs();
  const types = docs[BUILDINGS_PATH].data;
  const instances = docs[LEVEL_PATH].data.buildings;
  // Isolate this power scenario from always_on flags in editable shipped types.
  for (const type of types) if (type.id !== CONTROL_UNIT_ID) type.always_on = false;
  // Independent of the shipped level: no other building starts active.
  for (const b of instances) if (b.building_id !== CONTROL_UNIT_ID) b.enable_at_start = false;
  const generator = instances.find((b) => b.building_id !== CONTROL_UNIT_ID);
  const consumer = instances.find((b) => b.building_id !== CONTROL_UNIT_ID && b.building_id !== generator.building_id);
  const typeOf = (instance) => types.find((t) => t.id === instance.building_id);
  Object.assign(typeOf(generator), { power_output_kw: 5, power_need_kw: 0, min_operative_health: 0 });
  Object.assign(typeOf(consumer), { power_output_kw: 0, power_need_kw: 5, min_operative_health: 0.5 });
  Object.assign(generator, { enable_at_start: true });
  Object.assign(consumer, { enable_at_start: true, health: 0.5 });
  assert.deepEqual(errors(docs, LEVEL_PATH), [], 'enabled generator covers enabled consumer');
  consumer.health = 0.4;
  assert.ok(hasError(docs, LEVEL_PATH, `$.buildings[${instances.indexOf(consumer)}].enable_at_start`), 'health below minimum');
  consumer.health = 0.5;
  generator.enable_at_start = false;
  assert.ok(hasError(docs, LEVEL_PATH, '$.buildings'), 'enabled consumer without enabled generator');
});

test('buildings: warmup_time and cooldown_time are required nonnegative hours', () => {
  for (const field of ['warmup_time', 'cooldown_time']) {
    const docs = loadDocs();
    const [building] = docs[BUILDINGS_PATH].data;
    building[field] = 2.5;
    assert.deepEqual(errors(docs, BUILDINGS_PATH), [], `${field} positive`);
    building[field] = -1;
    assert.ok(hasError(docs, BUILDINGS_PATH, '$[0]'), `${field} negative`);
    delete building[field];
    assert.ok(hasError(docs, BUILDINGS_PATH, `$[0].${field}`), `${field} missing`);
  }
});

test('buildings: needs take exactly one of amount_per_unit, amount_per_hour, or amount_per_resident', () => {
  const docs = loadDocs();
  const [building] = docs[BUILDINGS_PATH].data;
  const resource_id = docs[RESOURCES_PATH].data[0].id;
  const needErrors = (need) => {
    building.needs = [need];
    return hasError(docs, BUILDINGS_PATH, '$[0].needs[0]');
  };
  assert.ok(!needErrors({ resource_id, amount_per_hour: 4 }), 'hourly amount is valid');
  assert.ok(!needErrors({ resource_id, amount_per_unit: 2 }), 'per-unit amount is valid');
  building.residents = { type: docs[SUBJECTS_PATH].data[0].id, capacity: 1 }; // amount_per_resident requires residents
  assert.ok(!needErrors({ resource_id, amount_per_resident: 0.08 }), 'per-resident amount is valid');
  assert.ok(needErrors({ resource_id }), 'neither amount');
  assert.ok(needErrors({ resource_id, amount_per_unit: 2, amount_per_hour: 4 }), 'both amounts');
  assert.ok(needErrors({ resource_id, amount_per_hour: 0 }), 'zero hourly amount');
  assert.ok(needErrors({ resource_id, amount_per_resident: 0 }), 'zero per-resident amount');
  assert.ok(needErrors({ resource_id, amount_per_hour: 4, amount_per_resident: 1 }), 'hourly and per-resident amounts');
  assert.ok(needErrors({ resource_id, amount_per_unit: 2, amount_per_resident: 1 }), 'per-unit and per-resident amounts');
});

test('subjects: types need a localized name and hourly needs on known resources', () => {
  const docs = loadDocs();
  const resource_id = docs[RESOURCES_PATH].data[0].id;
  const product = { resource_id, units_per_hour: 2 };
  const subject = {
    id: 'human',
    name_key: 'building_control_unit_name',
    width: 1,
    height: 1,
    color: { r: 1, g: 2, b: 3 },
    rest_time: 8,
    work_time: 10,
    roles: [{ role_id: 'worker', sprite: '' }, { role_id: 'repairer', sprite: '' }],
    needs: [{ resource_id, amount_per_hour: 0.5, shortage_alert_time: 12, shortage_max_time: 6 }],
    produces: [product],
  };
  const subjectErrors = (patch) => {
    docs[SUBJECTS_PATH].data = [{ ...subject, ...patch }];
    return errors(docs, SUBJECTS_PATH).length > 0;
  };
  assert.ok(!subjectErrors({}), 'valid subject');
  assert.ok(subjectErrors({ name_key: 'missing_translation' }), 'missing text');
  assert.ok(subjectErrors({ color: { r: 256, g: 0, b: 0 } }), 'invalid color');
  assert.ok(subjectErrors({ color: undefined }), 'missing color');
  assert.ok(subjectErrors({ needs: [{ resource_id, amount_per_hour: 0 }] }), 'zero amount');
  assert.ok(subjectErrors({ needs: [{ resource_id, amount_per_unit: 1 }] }), 'per-unit amount');
  const need = { resource_id, amount_per_hour: 1, shortage_alert_time: 0, shortage_max_time: 0 };
  assert.ok(subjectErrors({ needs: [{ ...need, resource_id: 'unknown' }] }), 'unknown resource');
  assert.ok(!subjectErrors({ needs: [need] }), 'zero alert and shortage time');
  assert.ok(subjectErrors({ needs: [{ ...need, shortage_alert_time: -1 }] }), 'negative shortage_alert_time');
  assert.ok(subjectErrors({ needs: [{ ...need, shortage_max_time: -1 }] }), 'negative shortage_max_time');
  const { shortage_alert_time: _alert, ...withoutAlert } = need;
  assert.ok(subjectErrors({ needs: [withoutAlert] }), 'missing shortage_alert_time');
  assert.ok(subjectErrors({ needs: [{ ...withoutAlert, alert_time: 0 }] }), 'legacy alert_time');
  assert.ok(subjectErrors({ needs: [{ ...need, alert_time: 0 }] }), 'legacy alert_time alongside new field');
  for (const shortage_alert_time of [null, '1', Infinity, 1e100])
    assert.ok(subjectErrors({ needs: [{ ...need, shortage_alert_time }] }), 'invalid shortage_alert_time');
  assert.ok(subjectErrors({ needs: [{ ...withoutAlert, autonomy_time: 0 }] }), 'legacy autonomy_time');
  const { shortage_max_time: _shortage, ...withoutShortage } = need;
  assert.ok(subjectErrors({ needs: [withoutShortage] }), 'missing shortage_max_time');
  assert.ok(subjectErrors({ needs: [{ ...withoutShortage, starving_max_time: 0 }] }), 'legacy starving_max_time');
  assert.ok(subjectErrors({ needs: [{ ...need, starving_max_time: 0 }] }), 'legacy field alongside new field');
  for (const shortage_max_time of [null, '1', Infinity, 1e100])
    assert.ok(subjectErrors({ needs: [{ ...need, shortage_max_time }] }), 'invalid shortage_max_time');
  assert.ok(subjectErrors({ rest_time: -1 }), 'negative rest_time');
  assert.ok(subjectErrors({ work_time: -1 }), 'negative work_time');
  assert.ok(subjectErrors({ rest_time: undefined }), 'missing rest_time');
  assert.ok(!subjectErrors({ roles: null }), 'null roles');
  assert.ok(!subjectErrors({ roles: [] }), 'empty roles');
  assert.ok(subjectErrors({ roles: undefined }), 'missing roles');
  assert.ok(subjectErrors({ roles: [{ role_id: 'worker', sprite: '' }, { role_id: 'worker', sprite: '' }] }), 'duplicate type role');
  assert.ok(subjectErrors({ roles: [{ role_id: 'farmer', sprite: '' }] }), 'unknown type role');
  assert.ok(subjectErrors({ roles: 'worker' }), 'type roles not an array');
  assert.ok(subjectErrors({ produces: undefined }), 'missing produces');
  assert.ok(subjectErrors({ produces: [{ ...product, units_per_hour: 0 }] }), 'zero product rate');
  assert.ok(subjectErrors({ produces: [{ resource_id, time_per_unit: 0.5 }] }), 'legacy time_per_unit on a subject product');
  assert.ok(subjectErrors({ produces: [{ ...product, capacity: 5 }] }), 'subject product capacity is rejected');
  assert.ok(subjectErrors({ produces: [{ ...product, stored: 1 }] }), 'subject product stored is rejected');
  assert.ok(subjectErrors({ produces: [{ ...product, amount_per_resident: 1 }] }), 'subject product amount_per_resident is rejected');
  assert.ok(subjectErrors({ produces: [{ ...product, resource_id: 'unknown' }] }), 'unknown product resource');
  docs[SUBJECTS_PATH].data = [subject, subject];
  assert.ok(errors(docs, SUBJECTS_PATH).length > 0, 'duplicate id');
});

test('level: subjects reference their type and building instances of the level', () => {
  const docs = loadDocs();
  const humanType = { id: 'human', name_key: 'building_control_unit_name', color: { r: 1, g: 2, b: 3 }, roles: ['worker', 'supervisor', 'repairer'].map((role_id) => ({ role_id, sprite: '' })), needs: [] };
  docs[SUBJECTS_PATH].data = [humanType];
  const [residence, workplace] = docs[LEVEL_PATH].data.buildings.map((b) => b.id);
  const residenceType = docs[BUILDINGS_PATH].data.find((t) => t.id === docs[LEVEL_PATH].data.buildings[0].building_id);
  residenceType.residents = { type: 'human', capacity: 1 };
  docs[LEVEL_PATH].data.buildings[0].residents_amount = 0; // a type with residents needs a number
  const base = { id: 'H1', subject_id: 'human', residence, occupation: workplace, roles: ['worker', 'supervisor'], speed: 1 };
  const subjectErrors = (patch) => {
    docs[LEVEL_PATH].data.subjects = [{ ...base, ...patch }];
    return errors(docs, LEVEL_PATH).length > 0;
  };
  assert.ok(!subjectErrors({}), 'valid subject');
  assert.ok(!subjectErrors({ occupation: null, roles: ['repairer'], speed: 0.5 }), 'unemployed repairer');
  assert.ok(subjectErrors({ subject_id: 'robot' }), 'unknown subject type');
  assert.ok(subjectErrors({ residence: 'missing' }), 'unknown residence');
  assert.ok(subjectErrors({ residence: null }), 'null residence');
  assert.ok(subjectErrors({ occupation: 'missing' }), 'unknown occupation');
  assert.ok(subjectErrors({ roles: ['farmer'] }), 'unknown role');
  assert.ok(subjectErrors({ roles: [] }), 'no roles');
  assert.ok(subjectErrors({ roles: ['worker', 'worker'] }), 'duplicate role');
  assert.ok(subjectErrors({ roles: 'worker' }), 'roles not an array');
  assert.ok(subjectErrors({ roles: undefined, role: 'worker' }), 'legacy role field');
  humanType.roles = ['worker', 'repairer'].map((role_id) => ({ role_id, sprite: '' }));
  assert.ok(subjectErrors({}), 'supervisor is not a role of the type');
  assert.ok(!subjectErrors({ roles: ['repairer'] }), 'a role of the type');
  humanType.roles = null;
  assert.ok(subjectErrors({ roles: ['repairer'] }), 'a type with null roles takes none');
  assert.ok(!subjectErrors({ roles: [] }), 'no roles for a type without roles');
  humanType.roles = [];
  assert.ok(!subjectErrors({ roles: [] }), 'empty type roles behave like null');
  humanType.roles = ['worker', 'supervisor', 'repairer'].map((role_id) => ({ role_id, sprite: '' }));
  assert.ok(subjectErrors({ speed: 0 }), 'zero speed');
  const { speed: _speed, ...withoutSpeed } = base;
  docs[LEVEL_PATH].data.subjects = [withoutSpeed];
  assert.ok(errors(docs, LEVEL_PATH).length > 0, 'missing speed');
  docs[LEVEL_PATH].data.subjects = [base, base];
  assert.ok(errors(docs, LEVEL_PATH).length > 0, 'duplicate subject id');
  docs[LEVEL_PATH].data.subjects = [base, { ...base, id: 'H2' }];
  assert.ok(hasError(docs, LEVEL_PATH, '$.subjects[1].residence'), 'more residents than residents.capacity');
  assert.ok(!hasError(docs, LEVEL_PATH, '$.subjects[0].residence'), 'the first resident fits');
  residenceType.residents.capacity = 2;
  assert.deepEqual(errors(docs, LEVEL_PATH), [], 'two residents fit residents.capacity 2');
  residenceType.residents = null;
  assert.ok(hasError(docs, LEVEL_PATH, '$.subjects[0].residence'), 'residence type does not host the subject type');
});

test('level: stored holds one amount per needed or produced resource, within capacity', () => {
  const docs = loadDocs();
  const [resource, other] = docs[RESOURCES_PATH].data;
  const instance = docs[LEVEL_PATH].data.buildings[0];
  const type = docs[BUILDINGS_PATH].data.find((t) => t.id === instance.building_id);
  type.produces = [{ resource_id: resource.id, units_per_hour: 1, capacity: 10 }];
  const path = '$.buildings[0].stored';
  const storedErrors = (stored) => {
    instance.stored = stored;
    return errors(docs, LEVEL_PATH).filter((issue) => issue.path.startsWith(path));
  };
  assert.deepEqual(storedErrors([{ resource_id: resource.id, amount: 10 }]), [], 'full storage');
  assert.ok(storedErrors([{ resource_id: resource.id, amount: 11 }]).length, 'above capacity');
  assert.ok(storedErrors([{ resource_id: resource.id, amount: -1 }]).length, 'negative amount');
  assert.ok(storedErrors([]).length, 'produced resource without entry');
  assert.ok(storedErrors([{ resource_id: resource.id, amount: 1 }, { resource_id: other.id, amount: 1 }]).length, 'resource not produced');
  assert.ok(storedErrors([{ resource_id: resource.id, amount: 1 }, { resource_id: resource.id, amount: 1 }]).length, 'duplicate resource');
  assert.ok(storedErrors([{ resource_id: resource.id }]).length, 'missing amount');
  type.needs = [{ resource_id: other.id, amount_per_hour: 1, capacity: 4 }];
  assert.ok(storedErrors([{ resource_id: resource.id, amount: 1 }]).length, 'needed resource without entry');
  assert.deepEqual(storedErrors([{ resource_id: resource.id, amount: 1 }, { resource_id: other.id, amount: 4 }]), [], 'needed resource within capacity');
  assert.ok(storedErrors([{ resource_id: resource.id, amount: 1 }, { resource_id: other.id, amount: 5 }]).length, 'needed resource above capacity');
  type.needs = [{ resource_id: resource.id, amount_per_hour: 1, capacity: 20 }];
  assert.deepEqual(storedErrors([{ resource_id: resource.id, amount: 20 }]), [], 'needed and produced: larger capacity');
  type.storage = [{ resource_id: other.id, capacity: 3 }];
  assert.ok(storedErrors([{ resource_id: resource.id, amount: 1 }]).length, 'storage resource without entry');
  assert.deepEqual(storedErrors([{ resource_id: resource.id, amount: 1 }, { resource_id: other.id, amount: 3 }]), [], 'storage resource within capacity');
  assert.ok(storedErrors([{ resource_id: resource.id, amount: 1 }, { resource_id: other.id, amount: 4 }]).length, 'storage resource above capacity');
  delete instance.stored;
  assert.ok(hasError(docs, LEVEL_PATH, path), 'missing stored');
});

test('level: residents_amount is a number within residents.capacity only for buildings with residents', () => {
  const docs = loadDocs();
  const [instance] = docs[LEVEL_PATH].data.buildings;
  const type = docs[BUILDINGS_PATH].data.find((t) => t.id === instance.building_id);
  const path = '$.buildings[0].residents_amount';
  const invalid = (amount) => {
    instance.residents_amount = amount;
    return hasError(docs, LEVEL_PATH, path);
  };
  type.residents = null;
  assert.ok(!invalid(null), 'null without residents');
  assert.ok(invalid(0), 'number without residents');
  type.residents = { type: 'human', capacity: 4 };
  assert.ok(!invalid(0), 'no residents yet');
  assert.ok(!invalid(4), 'full capacity');
  assert.ok(invalid(4.5), 'above capacity');
  assert.ok(invalid(1.5), 'fractional people');
  assert.ok(invalid(-1), 'negative');
  assert.ok(invalid('2'), 'not a number');
  assert.ok(invalid(null), 'null with residents');
  delete instance.residents_amount;
  assert.ok(hasError(docs, LEVEL_PATH, path), 'missing');
});

test('level: instances of always_on building types must set enable_at_start', () => {
  const docs = loadDocs();
  const instances = docs[LEVEL_PATH].data.buildings;
  const instance = instances.find((b) => b.building_id !== CONTROL_UNIT_ID);
  const type = docs[BUILDINGS_PATH].data.find((t) => t.id === instance.building_id);
  const path = `$.buildings[${instances.indexOf(instance)}].enable_at_start`;
  Object.assign(type, { always_on: true, min_operative_health: 0 });
  instance.enable_at_start = false;
  assert.ok(hasError(docs, LEVEL_PATH, path), 'always_on type not enabled at start');
  instance.enable_at_start = true;
  assert.ok(!hasError(docs, LEVEL_PATH, path), 'always_on type enabled at start');
  type.always_on = false;
  instance.enable_at_start = false;
  assert.ok(!hasError(docs, LEVEL_PATH, path), 'regular type may start disabled');
});
