// Level instances keep one stored amount per resource their building type needs or produces.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { storageCapacities, storedInSync, storedIssues, syncStored } from '../src/lib/stored.js';

const type = {
  needs: [{ resource_id: 'ores', amount_per_unit: 2, capacity: 8 }],
  produces: [
    { resource_id: 'water', units_per_hour: 1, capacity: 10 },
    { resource_id: 'meals', units_per_hour: 0.5, capacity: 5, stored: 3 },
  ],
};

test('sync keeps amounts of stored resources, adds needs, and drops the others', () => {
  const next = syncStored([{ resource_id: 'meals', amount: 4 }, { resource_id: 'gold', amount: 9 }], type);
  assert.deepEqual(next, [
    { resource_id: 'water', amount: 0 },
    { resource_id: 'meals', amount: 4 },
    { resource_id: 'ores', amount: 0 },
  ]);
  assert.ok(storedInSync(next, type));
});

test('a legacy stored value on the type seeds new instance entries', () => {
  assert.deepEqual(syncStored(undefined, type), [
    { resource_id: 'water', amount: 0 },
    { resource_id: 'meals', amount: 3 },
    { resource_id: 'ores', amount: 0 },
  ]);
});

test('in sync means one numeric entry per needed or produced resource, in any order', () => {
  const full = [
    { resource_id: 'ores', amount: 1 },
    { resource_id: 'meals', amount: 1 },
    { resource_id: 'water', amount: 2 },
  ];
  assert.ok(storedInSync(full, type));
  assert.ok(!storedInSync(undefined, type), 'missing array');
  assert.ok(!storedInSync(full.slice(1), type), 'missing needed resource');
  assert.ok(!storedInSync([...full, { resource_id: 'water', amount: 1 }], type), 'duplicate');
  assert.ok(!storedInSync([{ resource_id: 'water' }, ...full.slice(0, 2)], type), 'missing amount');
  assert.ok(storedInSync([], { needs: [], produces: [] }), 'type without needs or products');
});

test('storage resources get an entry too, merged with needs and products at the largest capacity', () => {
  const warehouse = { ...type, storage: [{ resource_id: 'gold', capacity: 100 }, { resource_id: 'water', capacity: 40 }] };
  assert.deepEqual([...storageCapacities(warehouse)], [['water', 40], ['meals', 5], ['ores', 8], ['gold', 100]]);
  assert.deepEqual(syncStored([], warehouse).map((s) => s.resource_id), ['water', 'meals', 'ores', 'gold']);
  const stored = syncStored([], warehouse).map((s) => (s.resource_id === 'gold' ? { ...s, amount: 100 } : s));
  assert.deepEqual(storedIssues({ building_id: 'warehouse', stored }, warehouse, '$'), []);
  assert.equal(storedIssues({ building_id: 'warehouse', stored: stored.filter((s) => s.resource_id !== 'gold') }, warehouse, '$').length, 1);
});

test('a resource both needed and produced has one entry bounded by the larger capacity', () => {
  const both = { needs: [{ resource_id: 'water', amount_per_hour: 1, capacity: 50 }], produces: [{ resource_id: 'water', units_per_hour: 1, capacity: 10 }] };
  assert.deepEqual([...storageCapacities(both)], [['water', 50]]);
  const issues = (amount) => storedIssues({ building_id: 'b', stored: [{ resource_id: 'water', amount }] }, both, '$');
  assert.deepEqual(issues(50), []);
  assert.equal(issues(51).length, 1);
});

test('issues flag amounts above a need capacity and resources the type does not use', () => {
  const instance = (stored) => ({ building_id: 'refinery', stored });
  const valid = [
    { resource_id: 'water', amount: 10 },
    { resource_id: 'meals', amount: 0 },
    { resource_id: 'ores', amount: 8 },
  ];
  assert.deepEqual(storedIssues(instance(valid), type, '$'), []);
  assert.equal(storedIssues(instance([...valid.slice(0, 2), { resource_id: 'ores', amount: 9 }]), type, '$').length, 1);
  assert.match(storedIssues(instance([...valid, { resource_id: 'gold', amount: 1 }]), type, '$')[0].message, /does not need, produce, or store/);
  assert.match(storedIssues(instance(valid.slice(0, 2)), type, '$')[0].message, /missing stored entry for resource "ores"/);
});
