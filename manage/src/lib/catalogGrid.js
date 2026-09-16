import { isPlainObject } from './object.js';
import { buildingTypeSchema, resourceSchema, subjectTypeSchema, roleSchema, shipSchema, stationSchema } from './schema.js';

export const GRID_SCHEMAS = { buildings: buildingTypeSchema, resources: resourceSchema, subjects: subjectTypeSchema, subject_roles: roleSchema, ships: shipSchema, space_stations: stationSchema };

// Only declared fields present in every row; no inferred schema or normalization.
export function commonGridFields(data, schema) {
  if (!Array.isArray(data) || !data.length || data.some((row) => !isPlainObject(row))) return [];
  return Object.entries(schema.fields).filter(([key, field]) => key !== 'id'
    && (['string', 'bool', 'int', 'u8', 'f32'].includes(field.type) || key === 'color')
    && data.every((row) => Object.hasOwn(row, key)));
}

export function updateGridCell(data, index, field, value, schema) {
  if (!commonGridFields(data, schema).some(([key]) => key === field) || !isPlainObject(data[index])) return data;
  return data.map((row, i) => i === index ? { ...row, [field]: value } : row);
}
