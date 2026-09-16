import test from 'node:test';
import assert from 'node:assert/strict';
import { hoursPerUnitText } from '../src/lib/rate.js';

test('hourly rates display a signed read-only reciprocal', () => {
  assert.equal(hoursPerUnitText(2), '0.5');
  assert.equal(hoursPerUnitText(0.25), '4');
  assert.equal(hoursPerUnitText(-2), '-0.5');
  assert.equal(hoursPerUnitText(3), '0.333333');
  assert.equal(hoursPerUnitText(0), '∞');
  assert.equal(hoursPerUnitText(-0), '∞');
  for (const rate of [null, undefined, '', '2', NaN, Infinity]) assert.equal(hoursPerUnitText(rate), '—');
  assert.equal(hoursPerUnitText(1e20), '1e-20');
  assert.equal(hoursPerUnitText(Number.MIN_VALUE), '∞');
});
