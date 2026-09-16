import test from 'node:test';
import assert from 'node:assert/strict';
import { placementPosition } from '../src/lib/mapPlacement.js';
const rect = { left: 100, top: 50, width: 800, height: 600 };
test('placement converts screen position using map offset, pan and zoom', () => {
  assert.deepEqual(placementPosition(500, 350, rect, { cx: 0, cy: 0, scale: 40 }, 0), { x: 0, y: 0 });
  assert.deepEqual(placementPosition(580, 310, rect, { cx: 3, cy: -2, scale: 40 }, 0), { x: 5, y: -3 });
  assert.deepEqual(placementPosition(580, 310, rect, { cx: 3, cy: -2, scale: 80 }, 0), { x: 4, y: -2.5 });
});
test('placement applies snap in world coordinates and supports no snap', () => {
  const view = { cx: 0, cy: 0, scale: 40 };
  assert.deepEqual(placementPosition(527, 323, rect, view, 0.5), { x: 0.5, y: -0.5 });
  assert.deepEqual(placementPosition(527, 323, rect, view, 0), { x: 0.675, y: -0.675 });
});
