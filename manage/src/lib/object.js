// Small immutable helpers. Key order is preserved because the game files are hand-read.

export const isPlainObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

/** Object entries of an array document; anything else yields an empty list. */
export const objectItems = (list) => (Array.isArray(list) ? list.filter(isPlainObject) : []);

export function getIn(value, path) {
  return path.reduce((node, key) => (node == null ? undefined : node[key]), value);
}

export function setIn(value, path, next) {
  if (path.length === 0) return next;
  const [head, ...rest] = path;
  const child = setIn(value?.[head], rest, next);
  if (Array.isArray(value)) {
    const copy = value.slice();
    copy[head] = child;
    return copy;
  }
  return { ...value, [head]: child };
}

export function removeIn(value, path) {
  const parentPath = path.slice(0, -1);
  const key = path[path.length - 1];
  const parent = getIn(value, parentPath);
  if (Array.isArray(parent)) return setIn(value, parentPath, parent.filter((_, i) => i !== key));
  const { [key]: _removed, ...rest } = parent;
  return setIn(value, parentPath, rest);
}

/** Renames an object key in place, keeping its position. */
export function renameKey(object, from, to) {
  return Object.fromEntries(Object.entries(object).map(([k, v]) => [k === from ? to : k, v]));
}

/** Inserts an entry right before `beforeKey` (or at the end when absent). */
export function insertKeyBefore(object, key, value, beforeKey) {
  const entries = Object.entries(object);
  const index = entries.findIndex(([k]) => k === beforeKey);
  entries.splice(index < 0 ? entries.length : index, 0, [key, value]);
  return Object.fromEntries(entries);
}

export function moveItem(array, from, to) {
  if (to < 0 || to >= array.length) return array;
  const copy = array.slice();
  const [item] = copy.splice(from, 1);
  copy.splice(to, 0, item);
  return copy;
}

export function uniqueName(base, taken) {
  const set = new Set(taken);
  if (!set.has(base)) return base;
  for (let i = 2; ; i++) if (!set.has(`${base}_${i}`)) return `${base}_${i}`;
}

export const clone = (value) => structuredClone(value);

export const rgbToHex = (c) =>
  '#' + ['r', 'g', 'b'].map((k) => Math.max(0, Math.min(255, Math.round(Number(c?.[k]) || 0))).toString(16).padStart(2, '0')).join('');

export const hexToRgb = (hex) => ({
  r: parseInt(hex.slice(1, 3), 16),
  g: parseInt(hex.slice(3, 5), 16),
  b: parseInt(hex.slice(5, 7), 16),
});

export const isColor = (value) =>
  isPlainObject(value) && ['r', 'g', 'b'].every((k) => typeof value[k] === 'number') && Object.keys(value).length === 3;

/** Picks black or white text for a readable label on the given RGB color. */
export const contrastText = (c) => ((c?.r ?? 0) * 0.299 + (c?.g ?? 0) * 0.587 + (c?.b ?? 0) * 0.114 > 150 ? '#000' : '#fff');
