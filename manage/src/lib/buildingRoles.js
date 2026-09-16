import { isPlainObject } from './object.js';
export const newBuildingRole = (role_id) => ({ role_id, quantity: 0, required: role_id !== 'repairer' });

export function updateBuildingRole(rows, roleId, field, value) {
  if (!Array.isArray(rows) || !['quantity', 'required'].includes(field)) return rows;
  const matches = rows.filter((row) => isPlainObject(row) && row.role_id === roleId);
  if (matches.length > 1) return rows;
  if (!matches.length) return [...rows, { ...newBuildingRole(roleId), [field]: value }];
  return rows.map((row) => row === matches[0] ? { ...row, [field]: value } : row);
}
