import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { EXTRA_FORMAT_TOKENS, REQUIRED_TEXT_KEYS, collectTextReferences, validateLocalization } from '../src/lib/schema.js';

const texts = JSON.parse(readFileSync(new URL('../../assets/localization/en.json', import.meta.url), 'utf8'));
test('every mandatory text is validated and protected as a game-code reference', () => {
  assert.deepEqual(validateLocalization(texts), []);
  const references = collectTextReferences({});
  for (const key of REQUIRED_TEXT_KEYS) {
    const copy = { ...texts };
    delete copy[key];
    assert.ok(validateLocalization(copy).some((i) => i.path === `$.${key}`), key);
    assert.ok(references.get(key)?.some((r) => r.file === 'game code'), key);
  }
});
test('station and building formats retain all mandatory placeholders', () => {
  for (const [key, tokens] of Object.entries(EXTRA_FORMAT_TOKENS))
    for (const token of tokens) {
      const copy = { ...texts, [key]: texts[key].replaceAll(token, 'missing') };
      assert.ok(validateLocalization(copy).some((i) => i.path === `$.${key}` && i.message.includes(token)));
    }
});
