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

// Every document path is relative to the selected configuration version, which the
// server maps to assets/config/<version>/.
const withProfile = (profile, path) => `/api/file?profile=${encodeURIComponent(profile)}&path=${encodeURIComponent(path)}`;
const jsonBody = (method, body) => ({
  method,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});

export const listProfiles = () => request('/api/profiles');
export const createProfile = (name, from) => request('/api/profiles', jsonBody('POST', { name, from }));
export const deleteProfile = (name) => request(`/api/profiles?name=${encodeURIComponent(name)}`, { method: 'DELETE' });
export const listFiles = (profile) => request(`/api/files?profile=${encodeURIComponent(profile)}`);
export const readFile = (profile, path) => request(withProfile(profile, path));
/** `text` is the already formatted JSON document; the server checks it parses before writing. */
export const saveFile = (profile, path, text, expectedMtime, force = false) =>
  request(withProfile(profile, path), jsonBody('PUT', { text, expectedMtime, force }));
export const createFile = (profile, path, text) => request(withProfile(profile, path), jsonBody('POST', { text }));
