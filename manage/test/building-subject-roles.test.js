import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createServer } from 'vite';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { validateBuildings } from '../src/lib/schema.js';

const building = JSON.parse(readFileSync(new URL('../../assets/config/default/buildings.json', import.meta.url)))[0];
const texts = JSON.parse(readFileSync(new URL('../../assets/config/default/localization/en.json', import.meta.url)));
const errors = (subject_roles) => validateBuildings([{ ...building, subject_roles }], texts).filter((i) => i.level === 'error');
test('building staffing objects validate IDs, integer quantities and staffing modes', () => {
  for (const roles of [[], [{ role_id: 'worker', quantity: 0, staffing_mode: 'continuous' }], [{ role_id: 'repairer', quantity: 2, staffing_mode: 'on_demand' }]]) assert.deepEqual(errors(roles), []);
  for (const roles of [undefined, null, ['worker'], [{}], [{ role_id: 'unknown', quantity: 1, staffing_mode: 'continuous' }], [{ role_id: 'worker', staffing_mode: 'continuous' }], [{ role_id: 'worker', quantity: 1 }], [{ role_id: 'worker', quantity: 1, required: true }], [{ role_id: 'worker', quantity: 1, staffing_mode: 'sometimes' }], [{ role_id: 'worker', quantity: 1, staffing_mode: 'continuous' }, { role_id: 'worker', quantity: 0, staffing_mode: 'on_demand' }]]) assert.ok(errors(roles).length, JSON.stringify(roles));
  for (const quantity of [-1, 1.5, Infinity, NaN, 1e100, null, '1', true]) assert.ok(errors([{ role_id: 'worker', quantity, staffing_mode: 'continuous' }]).length);
  for (const staffing_mode of [null, 0, 1, 'true', [], {}, 'sometimes']) assert.ok(errors([{ role_id: 'worker', quantity: 1, staffing_mode }]).length);
  assert.ok(validateBuildings([{ ...building, workers_required: 1 }], texts).some((i) => i.level === 'error'));
});

let server, Editor, defaults;
before(async () => {
  server = await createServer({ server: { middlewareMode: true, hmr: false, ws: false }, appType: 'custom' });
  ({ default: Editor, newBuildingRoles: defaults } = await server.ssrLoadModule('/src/components/BuildingSubjectRoles.jsx'));
});
after(async () => { await server?.close(); });
test('staffing table preserves malformed data and defaults without mutating on render', () => {
  assert.deepEqual(defaults().map((r) => [r.role_id, r.quantity, r.staffing_mode]), [['supervisor', 0, 'continuous'], ['worker', 0, 'continuous'], ['repairer', 0, 'on_demand']]);
  for (const value of [undefined, null, [], ['worker'], [{ role_id: {} }], [{ role_id: 'worker', quantity: 111, staffing_mode: 'continuous', extra: 'retained' }, { role_id: 'repairer', quantity: 222, staffing_mode: 'on_demand' }]]) {
    const original = JSON.stringify(value);
    const html = renderToStaticMarkup(createElement(Editor, { value, ctx: { texts: {}, subject_roles: [{ id: 'worker' }, { id: 'repairer' }] }, onChange() { assert.fail('render must not edit'); } }));
    assert.equal(JSON.stringify(value), original);
    assert.ok(html.includes('building-roles-table'));
    if (value?.length === 2) {
      assert.ok(html.includes('value="111"'));
      assert.ok(html.includes('value="222"'), 'all catalog rows are editable');
    }
  }
});
