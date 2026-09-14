// JSON asset API shared by the Vite dev middleware and the production server.
// Every path is resolved inside ASSETS_DIR; anything escaping it is rejected.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const ASSETS_DIR = path.resolve(process.env.ASSETS_DIR ?? path.join(here, '..', '..', 'assets'));

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function resolveAssetPath(relative) {
  if (typeof relative !== 'string' || relative.trim() === '') throw new HttpError(400, 'Missing "path" parameter');
  if (!relative.endsWith('.json')) throw new HttpError(400, 'Only .json files can be managed');
  const absolute = path.resolve(ASSETS_DIR, relative);
  const rel = path.relative(ASSETS_DIR, absolute);
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new HttpError(400, 'Path escapes the assets directory');
  return absolute;
}

async function listJsonFiles(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await listJsonFiles(full)));
    else if (entry.isFile() && entry.name.endsWith('.json')) {
      const stat = await fs.stat(full);
      files.push({
        path: path.relative(ASSETS_DIR, full).split(path.sep).join('/'),
        size: stat.size,
        mtime: stat.mtimeMs,
      });
    }
  }
  return files.sort((a, b) => a.path.localeCompare(b.path));
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
    if (url.pathname === '/api/files' && req.method === 'GET') {
      send(res, 200, { root: ASSETS_DIR, files: await listJsonFiles(ASSETS_DIR) });
      return true;
    }
    if (url.pathname === '/api/file') {
      const file = resolveAssetPath(url.searchParams.get('path'));
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
