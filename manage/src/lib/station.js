// Defaults and input names mirror the config loaders and vendored raylib enums.
export const KEY_DEFAULTS = {
  version: 1, menu_up: ['key:up'], menu_down: ['key:down'], activate: ['key:enter', 'key:space'],
  back: ['key:escape'], select: ['mouse:left'], zoom_in: ['wheel:up'], zoom_out: ['wheel:down'],
  pan: ['mouse:right', 'mouse:middle'], speed_up: ['key:e'], slow_down: ['key:q'],
};
const keys = `apostrophe comma minus period slash zero one two three four five six seven eight nine semicolon equal
left_bracket backslash right_bracket grave space escape enter tab backspace insert delete right left down up page_up page_down home end
caps_lock scroll_lock num_lock print_screen pause left_shift left_control left_alt left_super right_shift right_control right_alt right_super kb_menu
kp_decimal kp_divide kp_multiply kp_subtract kp_add kp_enter kp_equal back menu volume_up volume_down`.split(/\s+/);
keys.push(...'abcdefghijklmnopqrstuvwxyz', ...Array.from({ length: 12 }, (_, i) => `f${i + 1}`), ...Array.from({ length: 10 }, (_, i) => `kp_${i}`));
export const INPUT_NAMES = [...keys.map((k) => `key:${k}`), ...['left', 'right', 'middle', 'side', 'extra', 'forward', 'back'].map((k) => `mouse:${k}`), 'wheel:up', 'wheel:down'];
export function normalizeInput(value) {
  if (typeof value !== 'string') return '';
  const colon = value.indexOf(':');
  return value.slice(0, colon + 1) + value.slice(colon + 1).toLowerCase();
}
export const newShip = (id) => ({ id, code: id.toUpperCase(), color: { r: 200, g: 200, b: 200 }, name_key: `ship_${id}_name`, type: 'transport', sprite: '', width: 1, height: 1, max_speed: 0, max_speed_hours: 1, units_per_hour: 0.25, subjects: [] });
export const newStation = (id = 'space_station') => ({ id, code: id.toUpperCase(), name_key: `${id}_name`, resources: [], subjects: [], ships: [] });
export const newStock = (field, id) => field === 'ships' ? { ship_id: id, units: 0 } : { [field === 'resources' ? 'resource_id' : 'subject_id']: id, capacity: 100 };

// Explicit synchronization keeps existing values for matching IDs, seeds zeroes
// for additions and removes obsolete entries. It does not clamp invalid quantities.
export function syncStationInstance(instance, station) {
  const result = { station_id: station?.id ?? '', distance: instance && Object.hasOwn(instance, 'distance') ? instance.distance : 0, resources: [], subjects: [] };
  for (const [field, idField] of [['resources', 'resource_id'], ['subjects', 'subject_id']]) {
    const rows = Array.isArray(instance?.[field]) ? instance[field] : [];
    const definitions = Array.isArray(station?.[field]) ? station[field] : [];
    result[field] = definitions.filter((d) => d && typeof d[idField] === 'string').map((d) => {
      const old = rows.find((r) => r?.[idField] === d[idField]);
      return { [idField]: d[idField], units: old?.units ?? 0, units_per_hour: old?.units_per_hour ?? 0 };
    });
  }
  return result;
}
