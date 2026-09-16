// Typed numbers accept only a dot as decimal separator, independent of the browser locale.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseNumberText, stepNumber } from '../src/lib/number.js';

test('decimals use a dot; commas are rejected', () => {
  assert.deepEqual(parseNumberText('0.5'), { value: 0.5 });
  assert.deepEqual(parseNumberText(' -12.25 '), { value: -12.25 });
  assert.deepEqual(parseNumberText('.5'), { value: 0.5 });
  assert.deepEqual(parseNumberText('1e3'), { value: 1000 });
  for (const text of ['0,5', '1,000', '1.000,5', ',5']) assert.match(parseNumberText(text).error, /dot/, text);
  for (const text of ['abc', '1.2.3', '--1', '1e', '0x10']) assert.ok(parseNumberText(text).error, text);
});

test('partial input while typing is neither a value nor an error', () => {
  for (const text of ['', '-', '.', '-.']) assert.deepEqual(parseNumberText(text), { partial: true }, text);
  assert.deepEqual(parseNumberText('0.'), { value: 0 });
});

test('integer fields reject decimals', () => {
  assert.deepEqual(parseNumberText('3', true), { value: 3 });
  assert.ok(parseNumberText('3.5', true).error);
  assert.ok(parseNumberText('.', true).error);
  assert.deepEqual(parseNumberText('-', true), { partial: true });
});

test('arrow stepping rounds float noise and clamps', () => {
  assert.equal(stepNumber(0.2, 1, 0.1), 0.3);
  assert.equal(stepNumber(0.05, -1, 0.1, 0), 0);
  assert.equal(stepNumber(0.95, 1, 0.1, 0, 1), 1);
  assert.equal(stepNumber(undefined, 1, 1), 1);
});
