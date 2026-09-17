import { isPlainObject } from './object.js';

// `continuous` keeps every slot covered; `on_demand` waits for a future request.
// The former `required` boolean mapped true→continuous and false→on_demand.
export const newBuildingRole = (role_id) => ({ role_id, quantity: 0, staffing_mode: role_id === 'repairer' ? 'on_demand' : 'continuous' });

export function updateBuildingRole(rows, roleId, field, value) {
  if (!Array.isArray(rows) || !['quantity', 'staffing_mode'].includes(field)) return rows;
  const matches = rows.filter((row) => isPlainObject(row) && row.role_id === roleId);
  if (matches.length > 1) return rows;
  if (!matches.length) return [...rows, { ...newBuildingRole(roleId), [field]: value }];
  return rows.map((row) => row === matches[0] ? { ...row, [field]: value } : row);
}
