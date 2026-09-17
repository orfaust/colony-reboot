import test from 'node:test';
import assert from 'node:assert/strict';
import { planTranslationRename, applyRenameTransaction, stepRenameTransaction } from '../src/lib/translationRename.js';
import { SHIPS_PATH, TEXTS_PATH, SUBJECT_ROLES_PATH } from '../src/lib/schema.js';
const doc = (data) => ({ data, past: [], future: [], saved: JSON.stringify(data), mtime: 1 });
const fixture = () => ({
  [TEXTS_PATH]: doc({ old_key: 'Robot transport', untouched: 'Other' }),
  [SHIPS_PATH]: doc([{ id: 'robot', name_key: 'old_key', note: 'old_key', extra: { text: 'old_key' } }]),
  [SUBJECT_ROLES_PATH]: doc([{ id: 'worker', name_key: 'old_key' }]),
});
test('schema rename changes all shared references, preserves values and unknown fields', () => {
  const docs = fixture();
  const plan = planTranslationRename(docs, SHIPS_PATH, 'old_key', 'new_key');
  assert.equal(plan.error, undefined);
  assert.equal(plan.count, 2);
  assert.deepEqual(plan.changes[TEXTS_PATH], { new_key: 'Robot transport', untouched: 'Other' });
  assert.equal(plan.changes[SHIPS_PATH][0].name_key, 'new_key');
  assert.equal(plan.changes[SHIPS_PATH][0].note, 'old_key');
  assert.equal(plan.changes[SHIPS_PATH][0].extra.text, 'old_key');
  assert.equal(plan.changes[SUBJECT_ROLES_PATH][0].name_key, 'new_key');
  assert.equal(docs[SHIPS_PATH].data[0].name_key, 'old_key');
});
test('invalid keys, collisions, missing translations and unrelated origin are rejected without edits', () => {
  const docs = fixture(), snapshot = JSON.stringify(docs);
  for (const key of ['', ' ', 'New', 'bad key', 'bad.key', 'bad\0key', '1key', 'old_key', 'untouched', 'window_title'])
    assert.ok(planTranslationRename(docs, SHIPS_PATH, 'old_key', key).error, key);
  assert.ok(planTranslationRename(docs, SHIPS_PATH, 'absent', 'new_key').error);
  assert.ok(planTranslationRename(docs, SHIPS_PATH, 'untouched', 'new_key').error);
  assert.ok(planTranslationRename(docs, TEXTS_PATH, 'old_key', 'new_key').error);
  assert.equal(JSON.stringify(docs), snapshot);
});
test('unknown references, unloaded data, reserved sources and dangling target references block rename', () => {
  let docs = fixture();
  docs[SHIPS_PATH].data[0].extra.name_key = 'old_key';
  assert.match(planTranslationRename(docs, SHIPS_PATH, 'old_key', 'new_key').error, /outside declared/);
  docs = fixture(); docs[SHIPS_PATH].data.push({ name_key: 'new_key' });
  assert.match(planTranslationRename(docs, SHIPS_PATH, 'old_key', 'new_key').error, /already has references/);
  docs = fixture(); docs['broken.json'] = { loadError: 'bad JSON' };
  assert.match(planTranslationRename(docs, SHIPS_PATH, 'old_key', 'new_key').error, /Cannot inspect/);
  assert.match(planTranslationRename(fixture(), SHIPS_PATH, 'window_title', 'new_key').error, /game-code/);
});
test('rename undo and redo restore every file together from any affected file', () => {
  const docs = fixture();
  const plan = planTranslationRename(docs, SHIPS_PATH, 'old_key', 'new_key');
  const changed = applyRenameTransaction(docs, plan.changes);
  assert.equal(changed[TEXTS_PATH].saved, docs[TEXTS_PATH].saved);
  assert.notEqual(JSON.stringify(changed[TEXTS_PATH].data), changed[TEXTS_PATH].saved);
  const undone = stepRenameTransaction(changed, SHIPS_PATH, 'undo').docs;
  for (const path of Object.keys(docs)) assert.equal(undone[path].data, docs[path].data);
  const redone = stepRenameTransaction(undone, TEXTS_PATH, 'redo').docs;
  for (const path of Object.keys(docs)) assert.equal(redone[path].data, changed[path].data);
});
test('intervening edits, reloads and discarded redo branches cannot cause partial undo', () => {
  const docs = fixture();
  const changed = applyRenameTransaction(docs, planTranslationRename(docs, SHIPS_PATH, 'old_key', 'new_key').changes);
  const edited = { ...changed, [TEXTS_PATH]: { ...changed[TEXTS_PATH], past: [...changed[TEXTS_PATH].past, changed[TEXTS_PATH].data], data: { new_key: 'Edited' } } };
  assert.ok(stepRenameTransaction(edited, SHIPS_PATH, 'undo').error);
  assert.equal(stepRenameTransaction(edited, TEXTS_PATH, 'undo'), null, 'ordinary edit is handled by normal undo');
  const reloaded = { ...changed, [TEXTS_PATH]: doc(changed[TEXTS_PATH].data) };
  assert.ok(stepRenameTransaction(reloaded, SHIPS_PATH, 'undo').error);
  const undone = stepRenameTransaction(changed, SHIPS_PATH, 'undo').docs;
  undone[TEXTS_PATH] = { ...undone[TEXTS_PATH], future: [] };
  assert.ok(stepRenameTransaction(undone, SHIPS_PATH, 'redo').error);
});
