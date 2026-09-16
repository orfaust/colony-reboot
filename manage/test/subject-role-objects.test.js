import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'vite';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { validateSubjects } from '../src/lib/schema.js';

const subject = { id: 'human', name_key: 'name', width: 1, height: 1, color: { r: 1, g: 2, b: 3 }, rest_time: 0, work_time: 0, needs: [], produces: [] };
const validate = (roles) => validateSubjects([{ ...subject, roles }], { name: 'Human' }, []);
test('subject roles validate object IDs, optional paths and duplicate IDs', () => {
  for (const roles of [null, [], [{ role_id: 'worker' }], [{ role_id: 'worker', sprite: 'assets/human.png' }]]) assert.deepEqual(validate(roles), []);
  for (const roles of [['worker'], [null], [{}], [{ role_id: 'farmer' }], [{ role_id: 'worker', sprite: null }], [{ role_id: 'worker', sprite: '../bad.png' }], [{ role_id: 'worker' }, { role_id: 'worker', sprite: 'assets/other.png' }]]) assert.ok(validate(roles).some((i) => i.level === 'error'), JSON.stringify(roles));
});

let server, Editor;
before(async () => {
  server = await createServer({ server: { middlewareMode: true, hmr: false, ws: false }, appType: 'custom' });
  ({ default: Editor } = await server.ssrLoadModule('/src/components/SubjectRoleAssignments.jsx'));
});
after(async () => { await server?.close(); });
test('role editor shows localized names, sprite inheritance, browse and duplicate diagnostics', () => {
  const value = [{ role_id: 'worker', sprite: '' }, { role_id: 'worker', sprite: 'assets/custom.png' }];
  const html = renderToStaticMarkup(createElement(Editor, { value, onChange() {}, ctx: {
    texts: { worker_name: 'Worker' }, subject_roles: [{ id: 'worker', name_key: 'worker_name', sprite: 'assets/default.png' }],
  } }));
  assert.match(html, /Worker/);
  assert.match(html, /Inherited/);
  assert.match(html, /Override/);
  assert.match(html, /Duplicate role/);
  assert.match(html, /assets\/default.png/);
  assert.match(html, /Browse PNG asset paths/);
  assert.match(html, /Move role 1 up/);
  assert.match(html, /class="panel list-panel"/);
  assert.match(html, /class="panel detail-panel"/);
});

test('nested role editor uses master-detail and keeps malformed entries repairable without mutation', () => {
  for (const value of [null, [], 'broken', ['worker'], [{ role_id: {} }], [{ role_id: 'worker', sprite: 'assets/first.png', custom: 1 }, { role_id: 'repairer', sprite: 'assets/second.png' }]]) {
    const original = JSON.stringify(value);
    const html = renderToStaticMarkup(createElement(Editor, { value, onChange() { assert.fail('render must not edit data'); }, ctx: { texts: {} } }));
    for (const cls of ['master-detail', 'list-panel', 'item-list', 'detail-panel']) assert.ok(html.includes(cls));
    assert.equal(JSON.stringify(value), original);
    if (Array.isArray(value) && value.length === 2) { assert.ok(html.includes('assets/first.png')); assert.ok(!html.includes('assets/second.png')); }
    if (value === 'broken' || value?.[0] === 'worker') assert.match(html, /Reset to no roles|Repair as object/);
  }
});
