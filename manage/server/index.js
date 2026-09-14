// Production server: serves the built React app from dist/ plus the asset API.
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { handleApi, ASSETS_DIR } from './api.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(here, '..', 'dist');
const PORT = Number(process.env.PORT ?? 5174);
const HOST = process.env.HOST ?? '127.0.0.1';

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

async function serveStatic(req, res) {
  const url = new URL(req.url, 'http://localhost');
  let file = path.resolve(DIST, '.' + decodeURIComponent(url.pathname));
  if (!file.startsWith(DIST)) file = path.join(DIST, 'index.html');
  let data;
  try {
    const stat = await fs.stat(file);
    if (stat.isDirectory()) file = path.join(file, 'index.html');
    data = await fs.readFile(file);
  } catch {
    file = path.join(DIST, 'index.html');
    try {
      data = await fs.readFile(file);
    } catch {
      res.statusCode = 500;
      res.end('dist/ not found: run "npm run build" first, or use "npm run dev".');
      return;
    }
  }
  res.setHeader('Content-Type', TYPES[path.extname(file)] ?? 'application/octet-stream');
  res.end(data);
}

http
  .createServer(async (req, res) => {
    if (!(await handleApi(req, res))) await serveStatic(req, res);
  })
  .listen(PORT, HOST, () => {
    console.log(`Asset manager running at http://${HOST}:${PORT}`);
    console.log(`Editing JSON files in ${ASSETS_DIR}`);
  });
