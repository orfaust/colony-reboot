import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { detectKind, validateDoc, validateLevel, validateKeyBindings, validateShips, validateStation, validateStations, validateStationInstance } from '../src/lib/schema.js';
import { KEY_DEFAULTS, newShip, newStation, newStock, syncStationInstance } from '../src/lib/station.js';

test('station-related shipped assets are routed and validated', () => {
  const paths = ['key_bindings.json', 'ships.json', 'space_stations.json', 'resources.json', 'subjects.json', 'localization/en.json'];
  const docs = Object.fromEntries(paths.map((p) => [p, { data: JSON.parse(readFileSync(new URL(`../../assets/config/default/${p}`, import.meta.url), 'utf8')) }]));
  for (const path of paths.slice(0, 3)) {
    assert.notEqual(detectKind(path), 'generic');
    const issues = validateDoc(path, docs);
    assert.deepEqual(issues, [], path);
  }
});
test('station lists require unique IDs and preserve indexed error paths', () => {
  const first = newStation('first');
  const second = newStation('second');
  const texts = { first_name: 'First', second_name: 'Second' };
  const catalogs = { resources: [], subjects: [], ships: [] };
  assert.deepEqual(validateStations([first, second], texts, catalogs), []);
  assert.deepEqual(validateStations([], texts, catalogs), []);
  assert.ok(validateStations(first, texts, catalogs).some((i) => i.path === '$'));
  assert.ok(validateStations([first, first], texts, catalogs).some((i) => i.path === '$[1].id'));
  assert.ok(validateStations([{ ...first, id: '' }], texts, catalogs).some((i) => i.path === '$[0].id'));
  assert.ok(validateStations([first, { ...second, ships: [{ ship_id: 'missing', units: 1 }] }], texts, catalogs).some((i) => i.path === '$[1].ships[0].ship_id'));
});

test('bindings reject unknown names, empty actions, duplicates and wheel pan', () => {
  assert.deepEqual(validateKeyBindings(KEY_DEFAULTS), []);
  for (const patch of [{ version: 2 }, { pan: ['wheel:up'] }, { back: [] }, { select: ['mouse:left', 'mouse:left'] }, { activate: ['key:not_real'] }, { back: ['Key:escape'] }, { extra: [] }])
    assert.ok(validateKeyBindings({ ...KEY_DEFAULTS, ...patch }).length);
  assert.deepEqual(validateKeyBindings({ ...KEY_DEFAULTS, activate: ['key:ENTER'] }), []);
});
test('ship defaults, duplicate IDs, localization and shape errors', () => {
  const ship = newShip('transport');
  const texts = { [ship.name_key]: 'Transport' };
  assert.deepEqual(validateShips([ship], texts), []);
  assert.ok(validateShips([ship, ship], texts).some((i) => i.message.includes('duplicate')));
  assert.ok(validateShips([ship], {}).length);
  for (const data of [null, {}, [null], [{ ...ship, type: '' }]]) assert.ok(validateShips(data, texts).length);
});
test('ship code/color and station code are required and validated', () => {
  const ship = newShip('shuttle');
  const station = newStation('orbital');
  const texts = { [ship.name_key]: 'Shuttle', [station.name_key]: 'Orbital' };
  const catalogs = { resources: [], subjects: [], ships: [] };
  assert.equal(ship.code, 'SHUTTLE');
  assert.equal(station.code, 'ORBITAL');
  assert.deepEqual(ship.color, { r: 200, g: 200, b: 200 });
  for (const code of [undefined, '', ' ', 1, null]) {
    assert.ok(validateShips([{ ...ship, code }], texts).length);
    assert.ok(validateStations([{ ...station, code }], texts, catalogs).length);
  }
  for (const color of [undefined, null, {}, { r: -1, g: 0, b: 0 }, { r: 0, g: 256, b: 0 }, { r: 0, g: 0, b: 0.5 }])
    assert.ok(validateShips([{ ...ship, color }], texts).length);
  assert.deepEqual(validateShips([{ ...ship, color: { r: 0, g: 255, b: 128 } }], texts), []);
  const copy = structuredClone(ship);
  copy.color.r = 0;
  assert.equal(ship.color.r, 200);
});

test('distance and max_speed are required finite nonnegative floats', () => {
  const ship = newShip('shuttle');
  const station = newStation('orbital');
  const texts = { [ship.name_key]: 'Shuttle', [station.name_key]: 'Orbital' };
  const catalogs = { resources: [], subjects: [], ships: [] };
  assert.equal(ship.max_speed, 0);
  assert.ok(!Object.hasOwn(station, 'distance'));
  const instance = syncStationInstance(null, station);
  assert.equal(instance.distance, 0);
  assert.equal(syncStationInstance({ ...instance, distance: 123.5 }, station).distance, 123.5);
  assert.equal(syncStationInstance({ ...instance, distance: null }, station).distance, null);
  assert.ok(validateStations([{ ...station, distance: 0 }], texts, catalogs).length);
  for (const value of [0, 1234.5]) {
    assert.deepEqual(validateShips([{ ...ship, max_speed: value }], texts), []);
    assert.deepEqual(validateStationInstance({ ...instance, distance: value }, [station]), []);
  }
  for (const value of [undefined, null, '100', -1, NaN, Infinity, 1e100]) {
    assert.ok(validateShips([{ ...ship, max_speed: value }], texts).some((i) => i.path === '$[0].max_speed'));
    assert.ok(validateStationInstance({ ...instance, distance: value }, [station]).some((i) => i.path === '$.space_station.distance'));
  }
  const { max_speed, ...missingSpeed } = ship;
  const { distance, ...missingDistance } = instance;
  assert.ok(validateShips([missingSpeed], texts).length);
  assert.ok(validateStationInstance(missingDistance, [station]).length);
});

test('ship ramp hours and handling throughput are required finite nonnegative values', () => {
  const ship = newShip('shuttle');
  const texts = { [ship.name_key]: 'Shuttle' };
  assert.equal(ship.max_speed_hours, 1);
  assert.equal(ship.units_per_hour, 0.25);
  for (const field of ['max_speed_hours', 'units_per_hour']) {
    for (const value of [0, 0.25, 2.5]) assert.deepEqual(validateShips([{ ...ship, [field]: value }], texts), []);
    for (const value of [undefined, null, '1', -1, NaN, Infinity, 1e100]) {
      assert.ok(validateShips([{ ...ship, [field]: value }], texts).some((i) => i.path === `$[0].${field}`));
    }
    const missing = { ...ship };
    delete missing[field];
    assert.ok(validateShips([missing], texts).some((i) => i.path === `$[0].${field}`));
  }
});

test('level subject stock is whole while rates and resource stock may be fractional', () => {
  const station = { ...newStation('orbital'), subjects: [{ subject_id: 'human', capacity: 10 }], resources: [{ resource_id: 'water', capacity: 10 }] };
  const instance = syncStationInstance(null, station);
  instance.resources[0].units = 2.5;
  instance.subjects[0].units = 2;
  instance.subjects[0].units_per_hour = 0.5;
  assert.deepEqual(validateStationInstance(instance, [station]), []);
  instance.subjects[0].units = 2.5;
  assert.ok(validateStationInstance(instance, [station]).some((i) => i.path === '$.space_station.subjects[0].units'));
});

test('levels exceeding the individual subject pool receive actionable errors', () => {
  const station = { ...newStation('orbital'), subjects: [{ subject_id: 'human', capacity: 20000 }] };
  const instance = syncStationInstance(null, station);
  instance.subjects[0].units = 20000;
  const level = { version: 1, level: 0, buildings: [], subjects: [], space_station: instance };
  assert.ok(validateLevel(level, [], 'levels/level_0.json', [], [station]).some((i) => i.message.includes('runtime limit')));
});

test('ship subjects accept known types and nonnegative capacities only', () => {
  const ship = { ...newShip('transport'), subjects: [{ subject_id: 'human', capacity: 100 }] };
  const texts = { [ship.name_key]: 'Transport' };
  const types = [{ id: 'human' }, { id: 'robot' }];
  assert.deepEqual(validateShips([ship], texts, types), []);
  for (const row of [{ subject_id: 'human', capacity: -1 }, { subject_id: 'human', capacity: null },
    { subject_id: 'human', capacity: Infinity }, { subject_id: 'human', capacity: 1e100 },
    { subject_id: 'humans', capacity: 100 }, { resource_id: 'human', capacity: 100 }])
    assert.ok(validateShips([{ ...ship, subjects: [row] }], texts, types).length);
  assert.deepEqual(validateShips([{ ...ship, subjects: [{ subject_id: 'robot', capacity: 0 }] }], texts, types), []);
  assert.ok(validateShips([{ ...ship, subjects: [...ship.subjects, ...ship.subjects] }], texts, types).length);
  assert.ok(validateShips([{ ...ship, subjects: null }], texts, types).length);
  const { subjects: _subjects, ...missing } = ship;
  assert.ok(validateShips([missing], texts, types).length);
});
test('station defaults and stocks validate references, ranges and duplicates', () => {
  const catalogs = { resources: [{ id: 'water' }], subjects: [{ id: 'worker' }], ships: [{ id: 'transport' }] };
  const texts = { space_station_name: 'Station' };
  const station = newStation();
  for (const field of Object.keys(catalogs)) station[field] = [newStock(field, catalogs[field][0].id)];
  assert.deepEqual(validateStation(station, texts, catalogs), []);
  for (const patch of [{ units: 0 }, { units_per_hour: 0 }, { capacity: -1 }, { capacity: Infinity }, { resource_id: 'missing' }])
    assert.ok(validateStation({ ...station, resources: [{ ...station.resources[0], ...patch }] }, texts, catalogs).length);
  assert.ok(validateStation({ ...station, subjects: [{ ...station.subjects[0], units_per_hour: -2 }] }, texts, catalogs).length);
  assert.ok(validateStation({ ...station, ships: [{ ship_id: 'transport', units: 0.5 }] }, texts, catalogs).length);
  assert.ok(validateStation({ ...station, subjects: [...station.subjects, ...station.subjects] }, texts, catalogs).length);
  for (const data of [null, [], { ...station, resources: [null] }, { ...station, ships: {} }]) assert.ok(validateStation(data, texts, catalogs).length);
  assert.ok(validateStation(station, texts, {}).some((i) => i.level === 'warning'));
});

test('level station instance stock is complete, bounded and independent of its template', () => {
  const station = { ...newStation('orbital'), resources: [{ resource_id: 'water', capacity: 20 }], subjects: [{ subject_id: 'human', capacity: 8 }] };
  const first = syncStationInstance(null, station);
  const docs = {
    'space_stations.json': { data: [station] },
    'levels/level_0.json': { data: { version: 1, level: 0, buildings: [], subjects: [], space_station: first } },
  };
  assert.deepEqual(validateDoc('levels/level_0.json', docs), []);
  delete docs['levels/level_0.json'].data.space_station;
  assert.ok(validateDoc('levels/level_0.json', docs).some((i) => i.path === '$.space_station' && i.level === 'error'));
  const second = syncStationInstance(null, station);
  first.resources[0].units = 10;
  first.subjects[0].units_per_hour = -0.5;
  assert.equal(second.resources[0].units, 0);
  assert.equal(station.resources[0].units, undefined);
  assert.deepEqual(validateStationInstance(first, [station]), []);
  for (const patch of [{ units: -1 }, { units: 21 }, { capacity: 20 }, { units_per_hour: Infinity }, { units_per_hour: null }, { resource_id: 'missing' }]) {
    assert.ok(validateStationInstance({ ...first, resources: [{ ...first.resources[0], ...patch }] }, [station]).some((i) => i.level === 'error'));
  }
  for (const data of [null, {}, { ...first, station_id: 'missing' }, { ...first, resources: [] }, { ...first, subjects: [] }, { ...first, subjects: [...first.subjects, ...first.subjects] }, { ...first, subjects: [{ ...first.subjects[0], units: 9 }] }])
    assert.ok(validateStationInstance(data, [station]).length);
  const changed = { ...station, resources: [{ resource_id: 'water', capacity: 5 }, { resource_id: 'food', capacity: 1 }] };
  const synced = syncStationInstance(first, changed);
  assert.equal(synced.resources[0].units, 10); // No silent clamping after capacity changes.
  assert.equal(synced.resources[1].units, 0);
  assert.ok(validateStationInstance(synced, [changed]).length);
  assert.deepEqual(syncStationInstance(first, { ...station, resources: [] }).resources, []);
});
