import { isPlainObject, renameKey } from './object.js';
import { TEXTS_PATH, REQUIRED_TEXT_KEYS, detectKind, collectTextReferences, buildingTypeSchema, resourceSchema, subjectTypeSchema, roleSchema, shipSchema, stationSchema, levelSchema } from './schema.js';

const catalogs = { buildings: buildingTypeSchema, resources: resourceSchema, subjects: subjectTypeSchema, subject_roles: roleSchema, ships: shipSchema, space_stations: stationSchema };

// Traverse declared fields only. Unknown metadata is never rewritten by suffix alone.
function replaceReferences(value, schema, from, to, found) {
  if (schema.type === 'array' && Array.isArray(value)) return value.map((v) => replaceReferences(v, schema.item, from, to, found));
  if (schema.type !== 'object' || !isPlainObject(value)) return value;
  const next = { ...value };
  for (const [field, child] of Object.entries(schema.fields)) {
    if (child.type === 'string' && field.endsWith('_key') && value[field] === from) {
      next[field] = to;
      found.count++;
    } else if (Object.hasOwn(value, field)) next[field] = replaceReferences(value[field], child, from, to, found);
  }
  return next;
}

export function planTranslationRename(docs, origin, from, to) {
  const fail = (error) => ({ error });
  if (typeof to !== 'string' || !/^[a-z][a-z0-9_]*$/.test(to)) return fail('Use a nonempty lowercase key starting with a letter, followed by letters, digits or underscores.');
  if (to === from) return fail('The new key is unchanged.');
  if (REQUIRED_TEXT_KEYS.includes(from) || REQUIRED_TEXT_KEYS.includes(to)) return fail('Required game-code translation keys cannot be renamed or replaced.');
  const texts = docs[TEXTS_PATH]?.data;
  if (!isPlainObject(texts) || !Object.hasOwn(texts, from) || typeof texts[from] !== 'string') return fail('The source translation is missing or invalid in en.json. Repair it first.');
  if (Object.hasOwn(texts, to)) return fail('The destination key already exists, even if its text is identical.');
  for (const [file, doc] of Object.entries(docs)) if (doc.loadError || doc.data === undefined) return fail(`Cannot inspect ${file}. Repair or reload it before renaming.`);
  const refs = collectTextReferences(docs);
  if (refs.get(to)?.length) return fail('The destination key already has references. Repair those missing references first.');
  const changes = {};
  let count = 0;
  for (const [file, doc] of Object.entries(docs)) {
    const kind = detectKind(file);
    const schema = catalogs[kind] ? { type: 'array', item: catalogs[kind] } : kind === 'level' ? levelSchema : null;
    if (!schema) continue;
    const found = { count: 0 };
    const next = replaceReferences(doc.data, schema, from, to, found);
    if (found.count) { changes[file] = next; count += found.count; }
  }
  if (!changes[origin]) return fail('This key is not referenced by a declared localization field in the current element file.');
  if (count !== (refs.get(from)?.length ?? 0)) return fail('References exist outside declared localization fields. Repair them before renaming; unknown fields will not be rewritten.');
  changes[TEXTS_PATH] = renameKey(texts, from, to);
  return { changes, count };
}

// Transaction markers live only in editor history, never in asset data.
const TRANSACTION = Symbol('translation rename');
export function applyRenameTransaction(docs, changes) {
  const transaction = { paths: Object.keys(changes), before: {}, after: changes };
  const next = { ...docs };
  for (const path of transaction.paths) {
    const doc = docs[path];
    transaction.before[path] = doc.data;
    next[path] = { ...doc, data: changes[path], past: [...doc.past, { [TRANSACTION]: transaction }].slice(-200), future: [], lastKey: null };
  }
  return next;
}

export function stepRenameTransaction(docs, path, direction) {
  const undo = direction === 'undo';
  const stack = undo ? docs[path]?.past : docs[path]?.future;
  const marker = undo ? stack?.at(-1) : stack?.[0];
  const tx = marker?.[TRANSACTION];
  if (!tx) return null;
  for (const file of tx.paths) {
    const doc = docs[file];
    const top = undo ? doc?.past.at(-1) : doc?.future[0];
    if (top?.[TRANSACTION] !== tx || doc.data !== (undo ? tx.after[file] : tx.before[file])) {
      return { error: `Cannot ${direction} this rename independently. ${file} has intervening edits or was reloaded. Undo later edits first, or reload the affected files together.` };
    }
  }
  const next = { ...docs };
  for (const file of tx.paths) {
    const doc = docs[file];
    next[file] = { ...doc, data: undo ? tx.before[file] : tx.after[file], lastKey: null,
      past: undo ? doc.past.slice(0, -1) : [...doc.past, marker],
      future: undo ? [marker, ...doc.future] : doc.future.slice(1) };
  }
  return { docs: next };
}
