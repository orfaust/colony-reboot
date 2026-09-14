async function request(url, options) {
  const response = await fetch(url, options);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error ?? `HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return payload;
}

const fileUrl = (path) => `/api/file?path=${encodeURIComponent(path)}`;
const jsonBody = (method, body) => ({
  method,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});

export const listFiles = () => request('/api/files');
export const readFile = (path) => request(fileUrl(path));
/** `text` is the already formatted JSON document; the server checks it parses before writing. */
export const saveFile = (path, text, expectedMtime, force = false) => request(fileUrl(path), jsonBody('PUT', { text, expectedMtime, force }));
export const createFile = (path, text) => request(fileUrl(path), jsonBody('POST', { text }));
