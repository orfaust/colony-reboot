import test from 'node:test';
import assert from 'node:assert/strict';
import { updateBuildingRole } from '../src/lib/buildingRoles.js';

test('editing an absent assignment creates only that role with defaults', () => {
  const rows = [];
  assert.deepEqual(updateBuildingRole(rows, 'worker', 'quantity', 2), [{ role_id: 'worker', quantity: 2, required: true }]);
  assert.deepEqual(rows, []);
  assert.deepEqual(updateBuildingRole(rows, 'repairer', 'required', true), [{ role_id: 'repairer', quantity: 0, required: true }]);
});
test('cell updates preserve unknown fields and other assignments, refusing ambiguous rows', () => {
  const row = { role_id: 'worker', quantity: 1, required: true, extra: 'keep' };
  const rows = [row, { role_id: 'repairer', quantity: 2, required: false }];
  const next = updateBuildingRole(rows, 'worker', 'required', false);
  assert.deepEqual(next[0], { ...row, required: false });
  assert.equal(next[1], rows[1]);
  assert.equal(row.required, true);
  const duplicate = [row, { ...row }];
  assert.equal(updateBuildingRole(duplicate, 'worker', 'quantity', 5), duplicate);
  assert.equal(updateBuildingRole(null, 'worker', 'quantity', 5), null);
});
