import { isPlainObject } from './object.js';

// A confirmed translation changes only the existing key's value. No normalization:
// empty text and missing placeholders remain visible to normal validation.
export function editTranslation(texts, key, ask) {
  if (!isPlainObject(texts) || !Object.hasOwn(texts, key) || typeof texts[key] !== 'string') return null;
  const next = ask(`English text for "${key}" (shared by all references). Confirm to update en.json; save it separately or use Save all:`, texts[key]);
  if (next === null || next === texts[key]) return null;
  return { ...texts, [key]: next };
}
