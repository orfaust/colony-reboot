import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'vite';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { newRole } from '../src/lib/roles.js';

let server, render, renderTextKey, renderLevel, renderBuildingRoles;
before(async () => {
  server = await createServer({ server: { middlewareMode: true }, appType: 'custom' });
  const { default: Editor } = await server.ssrLoadModule('/src/components/SubjectRolesEditor.jsx');
  const { default: LevelEditor } = await server.ssrLoadModule('/src/components/LevelEditor.jsx');
  renderLevel = (data) => renderToStaticMarkup(createElement(LevelEditor, {
    data, onChange() { assert.fail('Rendering must not mutate the level'); },
    ctx: { texts: {}, buildings: [], subjects: [], space_stations: [] },
  }));
  const { default: BuildingRoles } = await server.ssrLoadModule('/src/components/BuildingSubjectRoles.jsx');
  renderBuildingRoles = (value) => renderToStaticMarkup(createElement(BuildingRoles, {
    value, onChange() { assert.fail('Rendering must preserve loaded data'); }, ctx: { texts: {}, subject_roles: [{ id: 'worker' }, { id: 'repairer' }] },
  }));
  const { TextKeyInput } = await server.ssrLoadModule('/src/components/fields.jsx');
  renderTextKey = (texts) => renderToStaticMarkup(createElement(TextKeyInput, {
    value: 'name_key', texts, onChange() {}, onCreateKey() {}, onEditKey() {}, onRenameKey() {},
  }));
  render = (data, gridSelection) => renderToStaticMarkup(createElement(Editor, {
    data, onChange() {}, ctx: { gridSelection, texts: { subject_role_worker_name: 'Worker', subject_role_supervisor_name: 'Supervisor' } },
  }));
});
after(async () => { await server?.close(); });

test('building roles show all catalog rows in a three-column table', () => {
  const html = renderBuildingRoles([{ role_id: 'worker', quantity: 3, staffing_mode: 'continuous' }, { role_id: 'repairer', quantity: 1, staffing_mode: 'on_demand' }]);
  assert.match(html, /class="panel building-subject-roles"/);
  assert.match(html, /class="building-roles-table"/);
  assert.equal((html.match(/scope="col"/g) ?? []).length, 3);
  assert.equal((html.match(/scope="row"/g) ?? []).length, 2);
  assert.match(html, /value="3"/);
  assert.equal((html.match(/>Quantity</g) ?? []).length, 1);
});
test('building staffing mode is a select reflecting both modes without changing data', () => {
  const continuous = renderBuildingRoles([{ role_id: 'worker', quantity: 1, staffing_mode: 'continuous' }]);
  const onDemand = renderBuildingRoles([{ role_id: 'worker', quantity: 1, staffing_mode: 'on_demand' }]);
  assert.match(continuous, /<select[^>]*aria-label="worker: staffing mode"/);
  assert.match(continuous, /<option value="continuous"[^>]*>Continuous<\/option>/);
  assert.match(onDemand, /<option value="on_demand"[^>]*>On demand<\/option>/);
  assert.doesNotMatch(continuous, /type="checkbox"/);
});

test('building roles retain malformed values and expose actionable errors', () => {
  assert.match(renderBuildingRoles(null), /Expected an array/);
  assert.match(renderBuildingRoles([]), /Not configured/);
  assert.match(renderBuildingRoles([null]), /unknown or malformed/);
  const html = renderBuildingRoles([{ role_id: 'worker', quantity: -2, staffing_mode: null }, { role_id: 'worker', quantity: 0, staffing_mode: 'continuous' }]);
  assert.match(html, /Duplicate role/);
  assert.match(html, /Expected a nonnegative whole number of slots/);
  assert.match(html, /Choose continuous or on demand/);
});

test('level map has bounded panels and a focusable sidebar without the Subjects editor', () => {
  const level = { version: 1, level: 0, buildings: [], subjects: [{ id: 'kept' }], space_station: {} };
  const before = JSON.stringify(level);
  const html = renderLevel(level);
  assert.match(html, /class="level-map-panel" role="tabpanel"/);
  assert.match(html, /class="panel inspector" tabindex="0"/);
  assert.match(html, /aria-label="Building properties and instance list"/);
  assert.doesNotMatch(html, /subjects-panel|subjects-table|Add subject|Place at origin/);
  assert.match(html, /aria-label="Place buildings on map" aria-pressed="false"/);
  assert.equal(JSON.stringify(level), before);
});

test('grid detail requests select the requested row, including duplicate IDs', () => {
  const rows = [newRole('worker'), { ...newRole('worker'), name_key: 'subject_role_supervisor_name' }];
  const html = render(rows, { index: 1 });
  assert.match(html, /<h2>Supervisor<\/h2>/);
  assert.doesNotMatch(html, /<h2>Worker<\/h2>/);
});

test('roles use the existing master-detail layout and render only selected properties', () => {
  const html = render(['worker', 'supervisor', 'repairer'].map(newRole));
  assert.match(html, /class="master-detail"/);
  assert.match(html, /class="panel list-panel"/);
  assert.match(html, /class="panel detail-panel"/);
  assert.match(html, /<h2>Worker<\/h2>/);
  assert.equal((html.match(/>Sprite path</g) ?? []).length, 0);
  assert.match(html, /disabled="">Add missing role/);
  assert.match(html, /aria-pressed="true"/);
  assert.match(html, /Move role 1 up/);
});
test('translation preview is a keyboard-accessible button, including empty text repair', () => {
  const html = renderTextKey({ name_key: 'Robot transport' });
  assert.match(html, /<button type="button" class="text-preview translation-edit"/);
  assert.match(html, /aria-label="Edit English translation for name_key"/);
  assert.match(html, /Robot transport/);
  assert.match(html, /aria-label="Rename translation key name_key"/);
  assert.match(html, />Rename key…<\/button>/);
  assert.match(renderTextKey({ name_key: '' }), /Empty text — edit translation/);
  assert.match(renderTextKey({}), /\+ Add text/);
});

test('empty, malformed and duplicate role catalogs remain visible for repair', () => {
  assert.match(render([]), /No roles/);
  assert.match(render([]), /Select a role on the left/);
  assert.match(render({}), /Expected a role array/);
  assert.match(render([null]), /Invalid role at index 0/);
  assert.match(render([newRole('worker'), newRole('worker')]), /Subject roles \(2\)/);
});
