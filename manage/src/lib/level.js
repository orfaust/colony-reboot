import { isPlainObject, moveItem } from './object.js';

export function buildingReferences(level, id) {
  const subjects = Array.isArray(level.subjects) ? level.subjects : [];
  return {
    residents: subjects.filter((s) => isPlainObject(s) && s.residence === id),
    workers: subjects.filter((s) => isPlainObject(s) && isPlainObject(s.initial_assignment) && s.initial_assignment.building_id === id),
  };
}

// Rename and reference updates are one level edit, hence one undo operation.
export function renameLevelBuilding(level, index, next) {
  if (!Array.isArray(level.buildings) || !isPlainObject(level.buildings[index])) return null;
  next = next.trim();
  if (!next || next.includes('\0') || level.buildings.some((b, i) => i !== index && b?.id === next)) return null;
  const old = level.buildings[index].id;
  // An already ambiguous ID must not silently redirect another instance's subjects.
  const ambiguous = level.buildings.some((b, i) => i !== index && b?.id === old);
  return {
    ...level,
    buildings: level.buildings.map((b, i) => i === index ? { ...b, id: next } : b),
    subjects: Array.isArray(level.subjects) ? level.subjects.map((s) => !isPlainObject(s) || ambiguous ? s : {
      ...s,
      residence: s.residence === old ? next : s.residence,
      initial_assignment: isPlainObject(s.initial_assignment) && s.initial_assignment.building_id === old
        ? { ...s.initial_assignment, building_id: next }
        : s.initial_assignment,
    }) : level.subjects,
  };
}

// Residences are mandatory: rehouse residents before deleting their building.
// Jobs are optional and become unassigned when their building is deleted.
export function removeLevelBuilding(level, index) {
  if (!Array.isArray(level.buildings) || index < 0 || index >= level.buildings.length) return null;
  const id = level.buildings[index]?.id;
  if (typeof id === 'string' && buildingReferences(level, id).residents.length) return null;
  return {
    ...level,
    buildings: level.buildings.filter((_, i) => i !== index),
    subjects: Array.isArray(level.subjects) ? level.subjects.map((s) => isPlainObject(s) && typeof id === 'string' && isPlainObject(s.initial_assignment) && s.initial_assignment.building_id === id ? { ...s, initial_assignment: null } : s) : level.subjects,
  };
}

export function reorderLevelBuildings(level, selected, from, to) {
  return { data: { ...level, buildings: moveItem(level.buildings, from, to) }, selected: selected === from ? to : selected === to ? from : selected };
}
