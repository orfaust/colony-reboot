import test from 'node:test';
import assert from 'node:assert/strict';
import { validateSubjects } from '../src/lib/schema.js';

const subject = { id: 'example', name_key: 'subject_example_name', width: 0.5, height: 1.25, color: { r: 1, g: 2, b: 3 }, rest_time: 0, work_time: 0, extra_work_time: 0, min_work_health: 0.4, min_colony_health: 0.1, health_rates: { work_gain_per_hour: 0, rest_gain_per_hour: 0, extra_work_loss_per_hour: 0, max_inactivity_loss_per_hour: 0, inactivity_max_time: 0, station_recovery_per_hour: 0 }, roles: null, needs: [], produces: [] };
const validate = (value) => validateSubjects([value], { subject_example_name: 'Example' }, []);

test('subject dimensions are required positive finite f32 values', () => {
  assert.deepEqual(validate(subject), []);
  for (const field of ['width', 'height']) {
    for (const value of [undefined, null, '2', true, [], {}, 0, -1, 1e-100, 1e100, Infinity, NaN]) {
      const invalid = { ...subject, [field]: value };
      assert.ok(validate(invalid).some((i) => i.path === `$[0].${field}`), `${field}: ${value}`);
      assert.equal(invalid[field], value, 'validation must not normalize loaded values');
    }
    const missing = { ...subject };
    delete missing[field];
    assert.ok(validate(missing).some((i) => i.path === `$[0].${field}`));
    assert.equal(field in missing, false);
  }
});
