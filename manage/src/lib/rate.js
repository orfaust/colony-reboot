// Presentation only: never store the reciprocal in the asset JSON.
export function hoursPerUnitText(rate) {
  if (typeof rate !== 'number' || !Number.isFinite(rate)) return '—';
  if (rate === 0) return '∞';
  const hours = 1 / rate;
  if (!Number.isFinite(hours)) return hours < 0 ? '−∞' : '∞';
  return String(Number(hours.toPrecision(6)));
}
