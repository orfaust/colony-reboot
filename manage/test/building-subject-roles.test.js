import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createServer } from 'vite';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { validateBuildings } from '../src/lib/schema.js';

const building = JSON.parse(readFileSync(new URL('../../assets/config/buildings.json', import.meta.url)))[0];
const texts = JSON.parse(readFileSync(new URL('../../assets/localization/en.json', import.meta.url)));
const errors = (subject_roles) => validateBuildings([{ ...building, subject_roles }], texts).filter((i) => i.level === 'error');
test('building staffing objects validate IDs, quantities and strict required booleans', () => {
  for (const roles of [[], [{ role_id: 'worker', quantity: 0, required: true }], [{ role_id: 'repairer', quantity: 0.5, required: false }]]) assert.deepEqual(errors(roles), []);
  for (const roles of [undefined, null, ['worker'], [{}], [{ role_id: 'unknown', quantity: 1, required: true }], [{ role_id: 'worker', required: true }], [{ role_id: 'worker', quantity: 1 }], [{ role_id: 'worker', quantity: 1, required: true }, { role_id: 'worker', quantity: 0, required: false }]]) assert.ok(errors(roles).length, JSON.stringify(roles));
  for (const quantity of [-1, Infinity, NaN, 1e100, null, '1', true]) assert.ok(errors([{ role_id: 'worker', quantity, required: true }]).length);
  for (const required of [null, 0, 1, 'true', [], {}]) assert.ok(errors([{ role_id: 'worker', quantity: 1, required }]).length);
  assert.ok(validateBuildings([{ ...building, workers_required: 1 }], texts).some((i) => i.level === 'error'));
});

let server, Editor, defaults;
before(async () => {
  server = await createServer({ server: { middlewareMode: true, hmr: false, ws: false }, appType: 'custom' });
  ({ default: Editor, newBuildingRoles: defaults } = await server.ssrLoadModule('/src/components/BuildingSubjectRoles.jsx'));
});
after(async () => { await server?.close(); });
test('staffing table preserves malformed data and defaults without mutating on render', () => {
  assert.deepEqual(defaults().map((r) => [r.role_id, r.quantity, r.required]), [['supervisor', 0, true], ['worker', 0, true], ['repairer', 0, false]]);
  for (const value of [undefined, null, [], ['worker'], [{ role_id: {} }], [{ role_id: 'worker', quantity: 111, required: true, extra: 'retained' }, { role_id: 'repairer', quantity: 222, required: false }]]) {
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
