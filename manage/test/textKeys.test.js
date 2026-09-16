// Localization keys derived from an element id must follow id renames.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { TEXTS_PATH } from '../src/lib/schema.js';
import { followIdRename } from '../src/lib/textKeys.js';

/** Minimal ctx: records en.json updates and answers confirm() with `answer`. */
function makeCtx(texts, answer = true) {
  const ctx = { texts, updates: [], asked: 0 };
  ctx.updateDoc = (path, updater) => ctx.updates.push([path, updater(texts)]);
  globalThis.confirm = () => {
    ctx.asked++;
    return answer;
  };
  return ctx;
}

const item = (id, prefix = 'building') => ({ id, name_key: `${prefix}_${id}_name`, description_key: `${prefix}_${id}_description` });

test('new element: keys without text follow the id silently', () => {
  const ctx = makeCtx({ unit_kg: 'kg' });
  const next = followIdRename(item('new_building'), 'building', 'new_building', 'farm', ctx);
  assert.equal(next.name_key, 'building_farm_name');
  assert.equal(next.description_key, 'building_farm_description');
  assert.equal(ctx.asked, 0);
  assert.equal(ctx.updates.length, 0);
});

test('existing text is moved to the new keys in en.json after confirmation', () => {
  const texts = { resource_water_name: 'Water', resource_water_description: 'Drinkable', unit_l: 'L' };
  const ctx = makeCtx(texts, true);
  const next = followIdRename(item('water', 'resource'), 'resource', 'water', 'fresh_water', ctx);
  assert.equal(next.name_key, 'resource_fresh_water_name');
  const [[path, updated]] = ctx.updates;
  assert.equal(path, TEXTS_PATH);
  assert.deepEqual(Object.keys(updated), ['resource_fresh_water_name', 'resource_fresh_water_description', 'unit_l']);
  assert.equal(updated.resource_fresh_water_name, 'Water');
});

test('declining keeps the keys pointing at the existing text', () => {
  const ctx = makeCtx({ building_farm_name: 'Farm', building_farm_description: 'Grows food' }, false);
  const original = item('farm');
  assert.deepEqual(followIdRename(original, 'building', 'farm', 'big_farm', ctx), original);
  assert.equal(ctx.updates.length, 0);
});

test('custom keys that do not follow the convention are left alone', () => {
  const ctx = makeCtx({});
  const custom = { id: 'farm', name_key: 'farm_title', description_key: 'building_farm_description' };
  const next = followIdRename(custom, 'building', 'farm', 'orchard', ctx);
  assert.equal(next.name_key, 'farm_title');
  assert.equal(next.description_key, 'building_orchard_description');
});
