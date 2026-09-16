import test from 'node:test';
import assert from 'node:assert/strict';
import { editTranslation } from '../src/lib/translation.js';

test('confirmed translation preserves stable keys, other texts and source', () => {
  const texts = { ship_robot_transport_name: 'Robot transport', other: 'Other' };
  const next = editTranslation(texts, 'ship_robot_transport_name', (message, initial) => {
    assert.equal(initial, 'Robot transport');
    assert.match(message, /shared by all references/);
    return 'Robot shuttle';
  });
  assert.deepEqual(next, { ...texts, ship_robot_transport_name: 'Robot shuttle' });
  assert.equal(texts.ship_robot_transport_name, 'Robot transport');
  assert.deepEqual(Object.keys(next), Object.keys(texts));
});
test('cancel and unchanged confirmation do not create an edit', () => {
  assert.equal(editTranslation({ key: 'Text' }, 'key', () => null), null);
  assert.equal(editTranslation({ key: 'Text' }, 'key', () => 'Text'), null);
});
test('invalid documents and absent keys cannot be silently replaced', () => {
  for (const texts of [undefined, null, [], {}, { key: 42 }])
    assert.equal(editTranslation(texts, 'key', () => assert.fail('Must not prompt')), null);
});
test('empty translations can be repaired and invalid confirmed text stays subject to validation', () => {
  assert.deepEqual(editTranslation({ key: '' }, 'key', () => 'Fixed'), { key: 'Fixed' });
  assert.deepEqual(editTranslation({ key: '{value}' }, 'key', () => ''), { key: '' });
});
