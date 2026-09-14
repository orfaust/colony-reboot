// Edits the game loader rejects must also be errors in the asset manager.
// Each case starts from a fresh copy of the shipped assets.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { BUILDINGS_PATH, CONTROL_UNIT_ID, POWER_FORMAT_KEYS, RESOURCES_PATH, TEXTS_PATH, validateDoc } from '../src/lib/schema.js';

const LEVEL_PATH = 'levels/level_0.json';
const assetsDir = new URL('../../assets/', import.meta.url);
const shipped = Object.fromEntries(
  [TEXTS_PATH, RESOURCES_PATH, BUILDINGS_PATH, LEVEL_PATH].map((path) => [path, JSON.parse(readFileSync(new URL(path, assetsDir), 'utf8'))]),
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
  const keys = [...POWER_FORMAT_KEYS, 'notice_insufficient_power', 'notice_generator_required', 'notice_control_unit_locked'];
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

test('level: Control Unit demand above its output is rejected', () => {
  const docs = loadDocs();
  assert.ok(docs[LEVEL_PATH].data.buildings.some((b) => b.building_id === CONTROL_UNIT_ID), 'level 0 places a Control Unit');
  const controlUnit = docs[BUILDINGS_PATH].data.find((t) => t.id === CONTROL_UNIT_ID);

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
  building.produces = [{ resource_id: resourceId, time_per_unit: 1e-50 }];
  assert.ok(hasError(docs, BUILDINGS_PATH, '$[0]'), 'width');
  assert.ok(hasError(docs, BUILDINGS_PATH, '$[0].needs[0]'), 'amount_per_unit');
  assert.ok(hasError(docs, BUILDINGS_PATH, '$[0].produces[0]'), 'time_per_unit');
});
