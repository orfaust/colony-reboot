import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

// ASSETS_DIR is read at import time, so point it at a fixture before loading the API.
const root = await fs.mkdtemp(path.join(os.tmpdir(), 'colony-profiles-'));
await fs.mkdir(path.join(root, 'config', 'default', 'levels'), { recursive: true });
await fs.writeFile(path.join(root, 'config', 'default', 'buildings.json'), '[]');
await fs.writeFile(path.join(root, 'config', 'default', 'levels', 'level_0.json'), '{}');
await fs.mkdir(path.join(root, 'config', 'experiment'), { recursive: true });
await fs.writeFile(path.join(root, 'config', 'experiment', 'buildings.json'), '[1]');
await fs.writeFile(path.join(root, 'outside.json'), '{}');
process.env.ASSETS_DIR = root;
const { handleApi } = await import('../server/api.js');

const call = (url, method = 'GET', body) => new Promise((resolve) => {
  const req = { url, method, async *[Symbol.asyncIterator]() { if (body !== undefined) yield Buffer.from(JSON.stringify(body)); } };
  const res = { headers: {}, body: undefined, setHeader: (k, v) => { res.headers[k] = v; }, end: (payload) => resolve({ status: res.statusCode, body: payload ? JSON.parse(payload) : undefined }) };
  handleApi(req, res).then((handled) => { if (!handled) resolve({ status: 0 }); });
});

test('versions are listed with their file counts', async () => {
  const { status, body } = await call('/api/profiles');
  assert.equal(status, 200);
  assert.equal(body.default, 'default');
  assert.deepEqual(body.profiles, [{ name: 'default', files: 2 }, { name: 'experiment', files: 1 }]);
});

test('file listing and reads are scoped to the requested version', async () => {
  const listing = await call('/api/files?profile=experiment');
  assert.equal(listing.status, 200);
  assert.deepEqual(listing.body.files.map((f) => f.path), ['buildings.json']);
  const doc = await call('/api/file?profile=experiment&path=buildings.json');
  assert.equal(doc.body.text, '[1]');
  // With no profile the server edits the default version.
  const fallback = await call('/api/files');
  assert.deepEqual(fallback.body.files.map((f) => f.path), ['buildings.json', 'levels/level_0.json']);
});

test('unknown, invalid and escaping version names are rejected', async () => {
  assert.equal((await call('/api/files?profile=missing')).status, 404);
  assert.equal((await call('/api/files?profile=..%2F..')).status, 400);
  assert.equal((await call('/api/file?profile=default&path=../../outside.json')).status, 400);
  assert.equal((await call('/api/file?profile=default&path=notes.txt')).status, 400);
});

test('a version can be duplicated and deleted, but not default or the last one', async () => {
  assert.equal((await call('/api/profiles', 'POST', { name: 'copy', from: 'experiment' })).status, 201);
  const copied = await call('/api/file?profile=copy&path=buildings.json');
  assert.equal(copied.body.text, '[1]');
  assert.equal((await call('/api/profiles', 'POST', { name: 'copy', from: 'default' })).status, 409);
  assert.equal((await call('/api/profiles', 'POST', { name: 'bad/name', from: 'default' })).status, 400);
  assert.equal((await call('/api/profiles', 'POST', { name: 'orphan', from: 'missing' })).status, 404);
  assert.equal((await call('/api/profiles?name=copy', 'DELETE')).status, 200);
  assert.equal((await call('/api/profiles?name=copy', 'DELETE')).status, 404);
  assert.equal((await call('/api/profiles?name=default', 'DELETE')).status, 400);
});

test.after(async () => { await fs.rm(root, { recursive: true, force: true }); });
