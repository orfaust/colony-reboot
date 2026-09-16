import test from 'node:test';
import assert from 'node:assert/strict';
import { buildingReferences, renameLevelBuilding, removeLevelBuilding, reorderLevelBuildings } from '../src/lib/level.js';

const fixture = () => ({ buildings: [{ id: 'home' }, { id: 'work' }, { id: 'other' }], subjects: [{ id: 'person', residence: 'home', occupation: 'work' }] });
test('building rename updates references atomically without mutating source', () => {
  const level = fixture();
  const renamed = renameLevelBuilding(level, 0, ' house ');
  assert.equal(renamed.subjects[0].residence, 'house');
  assert.equal(renamed.buildings[0].id, 'house');
  assert.equal(level.subjects[0].residence, 'home');
  assert.equal(renameLevelBuilding(level, 1, 'job').subjects[0].occupation, 'job');
  for (const id of ['', ' ', 'other', 'bad\0id']) assert.equal(renameLevelBuilding(level, 0, id), null);
});
test('deletion protects residences and clears optional occupations', () => {
  const level = fixture();
  assert.equal(buildingReferences(level, 'home').residents.length, 1);
  assert.equal(removeLevelBuilding(level, 0), null);
  const removed = removeLevelBuilding(level, 1);
  assert.equal(removed.subjects[0].occupation, null);
  assert.equal(level.subjects[0].occupation, 'work');
  assert.deepEqual(removed.buildings.map((b) => b.id), ['home', 'other']);
});
test('reordering preserves selection when either neighboring item moves', () => {
  const level = fixture();
  assert.equal(reorderLevelBuildings(level, 0, 1, 0).selected, 1);
  assert.equal(reorderLevelBuildings(level, 1, 1, 0).selected, 0);
  assert.equal(reorderLevelBuildings(level, 2, 1, 0).selected, 2);
  assert.equal(reorderLevelBuildings(level, null, 1, 0).selected, null);
});
test('repairing duplicate IDs does not guess which references to redirect', () => {
  const level = fixture();
  level.buildings.push({ id: 'home' });
  const next = renameLevelBuilding(level, 3, 'extra');
  assert.equal(next.subjects[0].residence, 'home');
});
