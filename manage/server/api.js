// JSON asset API shared by the Vite dev middleware and the production server.
// Every path is resolved inside ASSETS_DIR; anything escaping it is rejected.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const ASSETS_DIR = path.resolve(process.env.ASSETS_DIR ?? path.join(here, '..', '..', 'assets'));
// One directory per configuration version, mirroring config.CONFIG_ROOT in Odin.
export const PROFILES_DIR = path.join(ASSETS_DIR, 'config');
export const DEFAULT_PROFILE = 'default';
// Same rule as config.valid_profile_name: one safe path segment, nothing else.
const PROFILE_NAME = /^[A-Za-z0-9_-]{1,64}$/;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/** Resolves a version name to its directory, rejecting anything outside PROFILES_DIR. */
function resolveProfile(name) {
  const value = name === null || name === undefined || name === '' ? DEFAULT_PROFILE : name;
  if (typeof value !== 'string' || !PROFILE_NAME.test(value)) {
    throw new HttpError(400, 'Invalid version name: use 1-64 letters, digits, "-" or "_"');
  }
  const dir = path.resolve(PROFILES_DIR, value);
  const rel = path.relative(PROFILES_DIR, dir);
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new HttpError(400, 'Version escapes the configuration directory');
  return { name: value, dir };
}

// Paths are relative to the selected version, so the same document keeps the same
// name in every version.
function resolveAssetPath(profile, relative) {
  if (typeof relative !== 'string' || relative.trim() === '') throw new HttpError(400, 'Missing "path" parameter');
  if (!relative.endsWith('.json')) throw new HttpError(400, 'Only .json files can be managed');
  const absolute = path.resolve(profile.dir, relative);
  const rel = path.relative(profile.dir, absolute);
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new HttpError(400, 'Path escapes the configuration version');
  return absolute;
}

async function listJsonFiles(dir, base = dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await listJsonFiles(full, base)));
    else if (entry.isFile() && entry.name.endsWith('.json')) {
      const stat = await fs.stat(full);
      files.push({
        path: path.relative(base, full).split(path.sep).join('/'),
        size: stat.size,
        mtime: stat.mtimeMs,
      });
    }
  }
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

/** Configuration versions, ordered by name, with their JSON file count. */
async function listProfiles() {
  let entries;
  try {
    entries = await fs.readdir(PROFILES_DIR, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  const profiles = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || !PROFILE_NAME.test(entry.name)) continue;
    profiles.push({ name: entry.name, files: (await listJsonFiles(path.join(PROFILES_DIR, entry.name))).length });
  }
  return profiles.sort((a, b) => a.name.localeCompare(b.name));
}

// Browse existing PNG assets only; directory symlinks and file symlinks are not followed.
export async function listSpritePaths(root = ASSETS_DIR, dir = root) {
  const files = [];
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...await listSpritePaths(root, full));
    else if (entry.isFile() && /\.png$/i.test(entry.name)) files.push(`assets/${path.relative(root, full).split(path.sep).join('/')}`);
  }
  return files.sort();
}

// Reads a PNG sprite for previewing. Same containment rule as JSON assets.
function resolveSpritePath(relative) {
  if (typeof relative !== 'string' || !relative.trim()) throw new HttpError(400, 'Missing "path" parameter');
  if (!relative.endsWith('.png')) throw new HttpError(400, 'Only .png files can be previewed');
  const withinAssets = relative.startsWith('assets/') ? relative.slice('assets/'.length) : relative;
  const absolute = path.resolve(ASSETS_DIR, withinAssets);
  const rel = path.relative(ASSETS_DIR, absolute);
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new HttpError(400, 'Path escapes the assets directory');
  return absolute;
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 10 * 1024 * 1024) throw new HttpError(413, 'Request body too large');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HttpError(400, 'Request body is not valid JSON');
  }
}

// Write to a sibling temp file first so a crash never leaves a truncated asset.
async function atomicWrite(file, text) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.${Date.now()}.tmp`;
  await fs.writeFile(temp, text, 'utf8');
  await fs.rename(temp, file);
}

function send(res, status, payload) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(payload));
}

/** Handles /api/* requests. Returns false when the URL is not an API route. */
export async function handleApi(req, res) {
  const url = new URL(req.url, 'http://localhost');
  if (!url.pathname.startsWith('/api/')) return false;
  try {
    if (url.pathname === '/api/image' && req.method === 'GET') {
      const file = resolveSpritePath(url.searchParams.get('path'));
      let data;
      try {
        data = await fs.readFile(file);
      } catch (error) {
        if (error.code === 'ENOENT') throw new HttpError(404, 'Sprite not found');
        throw error;
      }
      res.statusCode = 200;
      res.setHeader('Content-Type', 'image/png');
      res.setHeader('Cache-Control', 'no-store');
      res.end(data);
      return true;
    }
    if (url.pathname === '/api/sprites' && req.method === 'GET') {
      send(res, 200, { paths: await listSpritePaths() });
      return true;
    }
    if (url.pathname === '/api/profiles') {
      if (req.method === 'GET') {
        send(res, 200, { root: PROFILES_DIR, default: DEFAULT_PROFILE, profiles: await listProfiles() });
        return true;
      }
      if (req.method === 'POST') {
        const body = await readBody(req);
        const created = resolveProfile(body.name);
        const source = resolveProfile(body.from);
        if (await fs.stat(created.dir).catch(() => null)) throw new HttpError(409, `Version "${created.name}" already exists`);
        const sourceStat = await fs.stat(source.dir).catch(() => null);
        if (!sourceStat?.isDirectory()) throw new HttpError(404, `Version "${source.name}" does not exist`);
        // Copy the whole version so the new one is immediately loadable by the game.
        await fs.cp(source.dir, created.dir, { recursive: true, errorOnExist: true });
        send(res, 201, { name: created.name });
        return true;
      }
      if (req.method === 'DELETE') {
        const removed = resolveProfile(url.searchParams.get('name'));
        if (removed.name === DEFAULT_PROFILE) throw new HttpError(400, `The "${DEFAULT_PROFILE}" version cannot be deleted; copy it to create a variant`);
        if ((await listProfiles()).length < 2) throw new HttpError(400, 'The last remaining version cannot be deleted');
        const stat = await fs.stat(removed.dir).catch(() => null);
        if (!stat?.isDirectory()) throw new HttpError(404, `Version "${removed.name}" does not exist`);
        await fs.rm(removed.dir, { recursive: true, force: true });
        send(res, 200, { removed: removed.name });
        return true;
      }
    }
    if (url.pathname === '/api/files' && req.method === 'GET') {
      const profile = resolveProfile(url.searchParams.get('profile'));
      const stat = await fs.stat(profile.dir).catch(() => null);
      if (!stat?.isDirectory()) throw new HttpError(404, `Version "${profile.name}" does not exist`);
      send(res, 200, { root: profile.dir, profile: profile.name, files: await listJsonFiles(profile.dir) });
      return true;
    }
    if (url.pathname === '/api/file') {
      const profile = resolveProfile(url.searchParams.get('profile'));
      const file = resolveAssetPath(profile, url.searchParams.get('path'));
      if (req.method === 'GET') {
        let text, stat;
        try {
          [text, stat] = await Promise.all([fs.readFile(file, 'utf8'), fs.stat(file)]);
        } catch (error) {
          if (error.code === 'ENOENT') throw new HttpError(404, 'File not found');
          throw error;
        }
        send(res, 200, { text, mtime: stat.mtimeMs });
        return true;
      }
      if (req.method === 'PUT' || req.method === 'POST') {
        const body = await readBody(req);
        const exists = await fs.stat(file).catch(() => null);
        if (req.method === 'POST' && exists) throw new HttpError(409, 'File already exists');
        if (req.method === 'PUT') {
          if (!exists) throw new HttpError(404, 'File not found');
          // Optimistic concurrency: refuse to overwrite edits made outside the tool.
          if (!body.force && typeof body.expectedMtime === 'number' && Math.abs(exists.mtimeMs - body.expectedMtime) > 1) {
            throw new HttpError(409, 'The file changed on disk since it was loaded');
          }
        }
        // Clients send preformatted text to preserve each file's style; never write invalid JSON.
        if (typeof body.text !== 'string') throw new HttpError(400, 'Missing "text" field');
        try {
          JSON.parse(body.text);
        } catch (error) {
          throw new HttpError(400, `Refusing to write invalid JSON: ${error.message}`);
        }
        await atomicWrite(file, body.text);
        const stat = await fs.stat(file);
        send(res, 200, { mtime: stat.mtimeMs });
        return true;
      }
    }
    throw new HttpError(404, `Unknown API route ${req.method} ${url.pathname}`);
  } catch (error) {
    send(res, error.status ?? 500, { error: error.message });
  }
  return true;
}
