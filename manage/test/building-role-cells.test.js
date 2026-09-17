import test from 'node:test';
import assert from 'node:assert/strict';
import { updateBuildingRole } from '../src/lib/buildingRoles.js';

test('editing an absent assignment creates only that role with defaults', () => {
  const rows = [];
  assert.deepEqual(updateBuildingRole(rows, 'worker', 'quantity', 2), [{ role_id: 'worker', quantity: 2, staffing_mode: 'continuous' }]);
  assert.deepEqual(rows, []);
  assert.deepEqual(updateBuildingRole(rows, 'repairer', 'staffing_mode', 'continuous'), [{ role_id: 'repairer', quantity: 0, staffing_mode: 'continuous' }]);
});
test('cell updates preserve unknown fields and other assignments, refusing ambiguous rows', () => {
  const row = { role_id: 'worker', quantity: 1, staffing_mode: 'continuous', extra: 'keep' };
  const rows = [row, { role_id: 'repairer', quantity: 2, staffing_mode: 'on_demand' }];
  const next = updateBuildingRole(rows, 'worker', 'staffing_mode', 'on_demand');
  assert.deepEqual(next[0], { ...row, staffing_mode: 'on_demand' });
  assert.equal(next[1], rows[1]);
  assert.equal(row.staffing_mode, 'continuous');
  const duplicate = [row, { ...row }];
  assert.equal(updateBuildingRole(duplicate, 'worker', 'quantity', 5), duplicate);
  assert.equal(updateBuildingRole(null, 'worker', 'quantity', 5), null);
});
