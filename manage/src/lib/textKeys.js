// Localization keys derived from an element id by convention: <prefix>_<id>_name, <prefix>_<id>_description.
import { renameKey } from './object.js';
import { TEXTS_PATH } from './schema.js';

const DERIVED_SUFFIXES = ['name', 'description'];

/** Key fields of `item` that still follow the convention for `oldId`, with their name for `newId`. */
export function derivedKeyRenames(item, prefix, oldId, newId) {
  return DERIVED_SUFFIXES.flatMap((suffix) => {
    const field = `${suffix}_key`;
    const from = `${prefix}_${oldId}_${suffix}`;
    return item?.[field] === from ? [{ field, from, to: `${prefix}_${newId}_${suffix}` }] : [];
  });
}

/**
 * Returns `item` with its derived keys renamed after an id change. Keys that already have
 * English text are renamed in en.json too (after confirmation), so the text is not orphaned;
 * if the user declines, the keys are left unchanged.
 */
export function followIdRename(item, prefix, oldId, newId, ctx) {
  const renames = derivedKeyRenames(item, prefix, oldId, newId);
  if (renames.length === 0) return item;
  const texts = ctx.texts ?? {};
  const movable = renames.filter((r) => r.from in texts && !(r.to in texts));
  if (movable.length) {
    const list = movable.map((r) => `${r.from} → ${r.to}`).join('\n');
    if (!confirm(`Rename the localization keys in ${TEXTS_PATH} too?\n${list}`)) return item;
    ctx.updateDoc(TEXTS_PATH, (all) => movable.reduce((acc, r) => (r.from in acc && !(r.to in acc) ? renameKey(acc, r.from, r.to) : acc), all));
  }
  return { ...item, ...Object.fromEntries(renames.map((r) => [r.field, r.to])) };
}
