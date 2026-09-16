// Per-instance resource storage (level `stored`): one { resource_id, amount } entry for each
// resource the building type needs, produces, or lists in `storage`, with amount in
// [0, capacity]. A resource in several lists has a single entry bounded by the largest
// capacity (config.stock_capacity).
import { isPlainObject } from './object.js';

const recipe = (list) => (Array.isArray(list) ? list.filter(isPlainObject) : []);

/** Capacity per stored resource id: products, then needs, then storage, in declaration order. */
export function storageCapacities(type) {
  const capacities = new Map();
  for (const item of [...recipe(type?.produces), ...recipe(type?.needs), ...recipe(type?.storage)]) {
    if (typeof item.resource_id !== 'string') continue;
    const previous = capacities.get(item.resource_id);
    capacities.set(item.resource_id, previous === undefined ? item.capacity : Math.max(previous, item.capacity));
  }
  return capacities;
}

/** Resource ids a building type stores (needed, produced, or in storage), without duplicates. */
export const storedResourceIds = (type) => [...storageCapacities(type).keys()];

/**
 * `stored` rebuilt to match the type's needs and products. Amounts of resources still stored are
 * kept; new entries start from the product's legacy `stored` value when present, otherwise 0.
 */
export function syncStored(stored, type) {
  const current = new Map((Array.isArray(stored) ? stored : []).filter(isPlainObject).map((s) => [s.resource_id, s.amount]));
  return storedResourceIds(type).map((resource_id) => {
    const kept = current.get(resource_id);
    const legacy = recipe(type?.produces).find((p) => p.resource_id === resource_id)?.stored;
    return { resource_id, amount: typeof kept === 'number' ? kept : typeof legacy === 'number' ? legacy : 0 };
  });
}

/** True when `stored` has exactly one numeric entry per stored resource (order does not matter). */
export function storedInSync(stored, type) {
  if (!Array.isArray(stored)) return false;
  const ids = storedResourceIds(type);
  return (
    stored.length === ids.length &&
    ids.every((id) => {
      const entries = stored.filter((s) => isPlainObject(s) && s.resource_id === id);
      return entries.length === 1 && typeof entries[0].amount === 'number' && Object.keys(entries[0]).length === 2;
    })
  );
}

/** Validation issues for an instance's `stored` array against its building type. */
export function storedIssues(instance, type, path) {
  const issues = [];
  const error = (p, message) => issues.push({ level: 'error', path: p, message });
  const capacities = storageCapacities(type);
  const stored = instance.stored;
  stored.forEach((entry, j) => {
    if (!isPlainObject(entry)) return;
    const p = `${path}.stored[${j}]`;
    const capacity = capacities.get(entry.resource_id);
    if (stored.findIndex((o) => o?.resource_id === entry.resource_id) !== j) error(p, `duplicate stored resource "${entry.resource_id}"`);
    else if (capacity === undefined) error(p, `"${instance.building_id}" does not need, produce, or store "${entry.resource_id}"`);
    else {
      const amount = Math.fround(entry.amount);
      if (amount < 0 || amount > Math.fround(capacity)) error(p, `amount must be in [0, capacity] (capacity ${capacity})`);
    }
  });
  for (const id of capacities.keys())
    if (!stored.some((s) => s?.resource_id === id)) error(`${path}.stored`, `missing stored entry for resource "${id}"`);
  return issues;
}
