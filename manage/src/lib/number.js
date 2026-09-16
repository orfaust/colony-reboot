// Numbers typed in the asset manager use a dot as the only decimal separator, like JSON,
// whatever the browser locale is.
const DECIMAL = /^-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/;
const INTEGER = /^-?\d+$/;
const PARTIAL = /^-?\.?$/; // "", "-", "." or "-." while typing

/** Parses typed text: `{ value }` when complete, `{ partial: true }` while typing, `{ error }` otherwise. */
export function parseNumberText(text, integer = false) {
  const trimmed = String(text ?? '').trim();
  if (trimmed.includes(',')) return { error: 'Use a dot (.) as the decimal separator' };
  if (PARTIAL.test(trimmed) && !(integer && trimmed.includes('.'))) return { partial: true };
  if (!(integer ? INTEGER : DECIMAL).test(trimmed)) return { error: integer ? 'Expected a whole number' : 'Not a valid number' };
  const value = Number(trimmed);
  return Number.isFinite(value) ? { value } : { error: 'Number out of range' };
}

/** Arrow-key stepping, rounded to hide binary float noise (0.1 + 0.2) and clamped to min/max. */
export function stepNumber(value, direction, step, min, max) {
  let next = Number(((Number.isFinite(value) ? value : 0) + direction * step).toPrecision(12));
  if (typeof min === 'number') next = Math.max(min, next);
  if (typeof max === 'number') next = Math.min(max, next);
  return next;
}
