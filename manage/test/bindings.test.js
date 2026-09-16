import test from 'node:test';
import assert from 'node:assert/strict';
import { BINDING_GROUPS, availableBindings, nextBinding, filterBindingGroups, inputLabel } from '../src/lib/bindings.js';
import { INPUT_NAMES, KEY_DEFAULTS } from '../src/lib/station.js';

test('every configured action appears exactly once', () => {
  const ids = BINDING_GROUPS.flatMap((g) => g.actions.map((a) => a.id));
  assert.deepEqual(ids.toSorted(), Object.keys(KEY_DEFAULTS).filter((k) => k !== 'version').toSorted());
});
test('binding options exclude duplicates, retain current input and respect devices', () => {
  const rows = ['key:ENTER', 'key:space'];
  const options = availableBindings('activate', rows, 0, 'key');
  assert.ok(options.includes('key:enter'));
  assert.ok(!options.includes('key:space'));
  assert.ok(options.every((o) => o.startsWith('key:')));
  assert.deepEqual(availableBindings('pan', [], -1, 'wheel'), []);
  assert.ok(availableBindings('activate', [null, 7], 0).includes('key:enter'));
});
test('add prefers defaults and never returns an occupied or unsupported input', () => {
  assert.equal(nextBinding('activate', []), 'key:enter');
  assert.equal(nextBinding('activate', ['key:ENTER']), 'key:space');
  assert.ok(!nextBinding('pan', KEY_DEFAULTS.pan).startsWith('wheel:'));
  assert.equal(nextBinding('activate', INPUT_NAMES), undefined);
});
test('search matches action IDs, labels and groups', () => {
  assert.equal(filterBindingGroups(' ZOOM_IN ')[0].actions[0].id, 'zoom_in');
  assert.equal(filterBindingGroups('simulation')[0].actions.length, 2);
  assert.equal(filterBindingGroups('confirm')[0].actions[0].id, 'activate');
  assert.deepEqual(filterBindingGroups('not an action'), []);
  assert.equal(inputLabel('key:page_up'), 'Page Up');
});
