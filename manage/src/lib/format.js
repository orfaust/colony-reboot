// Serializes JSON in the same style as the hand-edited asset it came from, so saving
// does not reformat untouched parts of a file.
import { isPlainObject } from './object.js';

const INLINE_LIMIT = 72;

/** Detects the style of an existing file: short objects on one line or fully expanded. */
export function detectStyle(text) {
  return { compact: /\{ "/.test(text), eol: text.endsWith('\n') };
}

function inline(value) {
  if (Array.isArray(value)) return `[${value.map(inline).join(', ')}]`;
  if (isPlainObject(value)) {
    const entries = Object.entries(value);
    if (entries.length === 0) return '{}';
    return `{ ${entries.map(([k, v]) => `${JSON.stringify(k)}: ${inline(v)}`).join(', ')} }`;
  }
  return JSON.stringify(value);
}

function write(value, compact, indent) {
  if (!Array.isArray(value) && !isPlainObject(value)) return JSON.stringify(value);
  if (compact) {
    const single = inline(value);
    if (single.length <= INLINE_LIMIT) return single;
  }
  const inner = indent + '  ';
  if (Array.isArray(value)) {
    if (value.length === 0) return '[]';
    return `[\n${value.map((v) => inner + write(v, compact, inner)).join(',\n')}\n${indent}]`;
  }
  const entries = Object.entries(value);
  if (entries.length === 0) return '{}';
  return `{\n${entries.map(([k, v]) => `${inner}${JSON.stringify(k)}: ${write(v, compact, inner)}`).join(',\n')}\n${indent}}`;
}

export function formatJson(value, style = { compact: false, eol: false }) {
  return write(value, style.compact, '') + (style.eol ? '\n' : '');
}
