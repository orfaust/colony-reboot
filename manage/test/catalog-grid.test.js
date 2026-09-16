import test from 'node:test';
import assert from 'node:assert/strict';
import { GRID_SCHEMAS, commonGridFields, updateGridCell } from '../src/lib/catalogGrid.js';

test('grid exposes only declared shared scalar/color fields, not IDs or nested lists', () => {
  const rows = [{ id: 'a', name_key: 'a_name', color: {}, sprite: '', roles: [], extra: 2 }, { id: 'b', name_key: 'b_name', color: {}, roles: [], extra: 3 }];
  assert.deepEqual(commonGridFields(rows, GRID_SCHEMAS.subjects).map(([key]) => key), ['name_key', 'color']);
  for (const data of [[], null, {}, [null], [rows[0], 2]]) assert.deepEqual(commonGridFields(data, GRID_SCHEMAS.subjects), []);
});
test('editing a cell preserves other rows, unknown fields and nested structures', () => {
  const rows = [{ id: 'a', name_key: 'a_name', color: {}, extra: { preserved: true } }, { id: 'b', name_key: 'b_name', color: {} }];
  const next = updateGridCell(rows, 0, 'name_key', 'new_name', GRID_SCHEMAS.subjects);
  assert.equal(next[0].name_key, 'new_name');
  assert.equal(rows[0].name_key, 'a_name');
  assert.equal(next[0].extra, rows[0].extra);
  assert.equal(next[1], rows[1]);
  assert.equal(updateGridCell(rows, 0, 'id', 'renamed', GRID_SCHEMAS.subjects), rows);
  assert.equal(updateGridCell(rows, 0, 'extra', null, GRID_SCHEMAS.subjects), rows);
  assert.equal(updateGridCell(rows, 99, 'name_key', 'invalid', GRID_SCHEMAS.subjects), rows);
});
test('all six catalogs support grid mode; confirmed invalid values remain for validation', () => {
  assert.equal(Object.keys(GRID_SCHEMAS).length, 6);
  const rows = [{ name_key: 'original' }];
  assert.equal(updateGridCell(rows, 0, 'name_key', '', GRID_SCHEMAS.ships)[0].name_key, '');
});
