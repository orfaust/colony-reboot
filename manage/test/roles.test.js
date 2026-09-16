import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { SUBJECT_ROLES, SUBJECT_ROLES_PATH, TEXTS_PATH, BUILDINGS_PATH, RESOURCES_PATH, SUBJECTS_PATH, detectKind, validateRoles, validateBuildings, validateDoc, collectTextReferences, validSpritePath } from '../src/lib/schema.js';
import { newRole, roleLabel } from '../src/lib/roles.js';

const roles = SUBJECT_ROLES.map(newRole);
const texts = Object.fromEntries(roles.map((role) => [role.name_key, `Localized ${role.id}`]));
const load = (path) => JSON.parse(readFileSync(new URL(`../../assets/${path}`, import.meta.url), 'utf8'));

test('role metadata defaults and editor routing use localized names', () => {
  assert.equal(detectKind(SUBJECT_ROLES_PATH), 'subject_roles');
  assert.deepEqual(validateRoles(roles, texts), []);
  assert.equal(roleLabel('worker', { subject_roles: roles, texts }), 'Localized worker');
  const docs = Object.fromEntries([SUBJECT_ROLES_PATH, TEXTS_PATH, BUILDINGS_PATH, RESOURCES_PATH, SUBJECTS_PATH].map((path) => [path, { data: load(path) }]));
  assert.deepEqual(validateDoc(SUBJECT_ROLES_PATH, docs), []);
  assert.deepEqual(validateDoc(BUILDINGS_PATH, docs), []);
  const refs = collectTextReferences(docs);
  assert.ok(refs.has('subject_role_worker_name'));
});

test('roles require every supported ID once, valid RGB, localization and sprite paths', () => {
  for (const data of [[], null, {}, [null], roles.slice(1), [...roles, roles[0]]]) assert.ok(validateRoles(data, texts).length);
  for (const patch of [
    { id: 'Worker' }, { id: '' }, { id: 'supervisor' }, { name_key: 'missing' },
    { color: { r: -1, g: 0, b: 0 } }, { color: { r: 0, g: 256, b: 0 } }, { color: { r: 0, g: 0, b: 0.5 } },
    { sprite: null }, { sprite: 42 }, { sprite: '../worker.png' }, { unknown: true },
  ]) assert.ok(validateRoles([{ ...roles[0], ...patch }, ...roles.slice(1)], texts).length, JSON.stringify(patch));
  for (const key of ['id', 'name_key', 'color']) {
    const copy = structuredClone(roles);
    delete copy[0][key];
    assert.ok(validateRoles(copy, texts).length, key);
  }
  assert.ok(validateRoles(roles, { ...texts, [roles[0].name_key]: ' ' }).length);
});

test('building sprite is optional; nonempty path syntax agrees with Odin', () => {
  const buildings = load(BUILDINGS_PATH);
  const resources = load(RESOURCES_PATH);
  const subjects = load(SUBJECTS_PATH);
  const english = load(TEXTS_PATH);
  for (const path of ['assets/building.png', 'assets/sprites/roles/worker.png', 'assets/sprites/my building.png']) assert.ok(validSpritePath(path), path);
  for (const path of [' ', 'assets/../worker.png', 'assets/./worker.png', 'assets//worker.png', '/assets/worker.png', 'C:/worker.png', 'assets\\worker.png', 'https://example.com/worker.png', 'worker.png', 'assets/worker.jpg', 'assets/worker.png ', 'assets/a\0.png']) assert.ok(!validSpritePath(path), path);
  for (const sprite of [undefined, null, 1, '../custom.png']) {
    const data = [{ ...buildings[0], sprite }, ...buildings.slice(1)];
    assert.ok(validateBuildings(data, english, resources, subjects).some((issue) => issue.path === '$[0].sprite'));
  }
  const data = structuredClone(buildings);
  delete data[0].sprite;
  assert.deepEqual(validateBuildings(data, english, resources, subjects), []);
  data[0].sprite = '';
  assert.deepEqual(validateBuildings(data, english, resources, subjects), []);
  data[0].sprite = 'assets/sprites/not-created-by-this-task.png';
  assert.deepEqual(validateBuildings(data, english, resources, subjects), []);
});
