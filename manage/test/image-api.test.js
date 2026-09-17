import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// ASSETS_DIR is read at import time, so point it at a fixture before loading the API.
const root = await fs.mkdtemp(path.join(os.tmpdir(), 'colony-assets-'));
await fs.mkdir(path.join(root, 'sprites'), { recursive: true });
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
await fs.writeFile(path.join(root, 'sprites', 'unit.png'), png);
await fs.writeFile(path.join(root, 'outside.txt'), 'secret');
process.env.ASSETS_DIR = root;
const { handleApi } = await import('../server/api.js');

const call = (url) => new Promise((resolve) => {
  const res = { headers: {}, body: undefined, setHeader: (k, v) => { res.headers[k] = v; }, end: (body) => resolve({ status: res.statusCode, res, body }) };
  handleApi({ url, method: 'GET' }, res).then((handled) => { if (!handled) resolve({ status: 0 }); });
});
test('sprite preview serves assets-relative PNGs with a cache-busting content type', async () => {
  const { status, res, body } = await call('/api/image?path=assets/sprites/unit.png');
  assert.equal(status, 200);
  assert.equal(res.headers['Content-Type'], 'image/png');
  assert.deepEqual(body, png);
});
test('sprite preview rejects traversal, non-PNG and missing files', async () => {
  assert.equal((await call('/api/image?path=assets/../../outside.txt')).status, 400);
  assert.equal((await call('/api/image?path=assets/sprites/unit.txt')).status, 400);
  assert.equal((await call('/api/image?path=assets/sprites/missing.png')).status, 404);
  assert.equal((await call('/api/image')).status, 400);
});
test.after(async () => { await fs.rm(root, { recursive: true, force: true }); });
