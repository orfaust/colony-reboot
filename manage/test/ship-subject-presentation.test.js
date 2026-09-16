import test from 'node:test';
import assert from 'node:assert/strict';
import { newShip } from '../src/lib/station.js';
import { validateShips, validateSubjects } from '../src/lib/schema.js';

test('ship dimensions are required positive finite f32 values', () => {
  const ship = newShip('example');
  const texts = { [ship.name_key]: 'Example' };
  assert.equal(ship.sprite, '');
  assert.equal(ship.width, 1);
  assert.equal(ship.height, 1);
  assert.deepEqual(validateShips([{ ...ship, width: 2.5, height: 0.5 }], texts), []);
  for (const field of ['width', 'height']) {
    for (const value of [undefined, null, '2', 0, -1, 1e-100, 1e100, Infinity, NaN])
      assert.ok(validateShips([{ ...ship, [field]: value }], texts).some((i) => i.path === `$[0].${field}`));
    const missing = { ...ship };
    delete missing[field];
    assert.ok(validateShips([missing], texts).length);
  }
});

test('ship and subject sprite paths follow the optional sprite contract', () => {
  const ship = newShip('example');
  const subject = { id: 'example', width: 1, height: 1, name_key: 'subject_example_name', color: { r: 1, g: 2, b: 3 }, rest_time: 0, work_time: 0, roles: null, needs: [], produces: [] };
  const texts = { [ship.name_key]: 'Ship', [subject.name_key]: 'Subject' };
  for (const [definition, validate] of [[ship, (d) => validateShips(d, texts)], [subject, (d) => validateSubjects(d, texts, [])]]) {
    for (const sprite of ['', 'assets/sprites/example.png']) assert.deepEqual(validate([{ ...definition, sprite }]), []);
    const omitted = { ...definition };
    delete omitted.sprite;
    assert.deepEqual(validate([omitted]), []);
    for (const sprite of [null, 42, ' ', '../bad.png', '/assets/bad.png', 'assets/bad.jpg', 'assets/../bad.png', 'assets\\bad.png'])
      assert.ok(validate([{ ...definition, sprite }]).some((i) => i.path === '$[0].sprite'), String(sprite));
  }
});
