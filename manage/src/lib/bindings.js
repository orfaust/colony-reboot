import { INPUT_NAMES, KEY_DEFAULTS, normalizeInput } from './station.js';

export const BINDING_GROUPS = [
  { title: 'Menu navigation', actions: [
    { id: 'menu_up', label: 'Move up', hint: 'Select the previous menu item.' },
    { id: 'menu_down', label: 'Move down', hint: 'Select the next menu item.' },
    { id: 'activate', label: 'Confirm', hint: 'Activate the selected menu item.' },
    { id: 'back', label: 'Back', hint: 'Go back or close the current screen.' },
  ] },
  { title: 'World and camera', actions: [
    { id: 'select', label: 'Select', hint: 'Select an item in the world.' },
    { id: 'pan', label: 'Pan camera', hint: 'Hold while moving the mouse. Wheel inputs cannot be held.' },
    { id: 'zoom_in', label: 'Zoom in', hint: 'Move the camera closer.' },
    { id: 'zoom_out', label: 'Zoom out', hint: 'Move the camera farther away.' },
  ] },
  { title: 'Simulation speed', actions: [
    { id: 'speed_up', label: 'Speed up', hint: 'Increase simulation speed.' },
    { id: 'slow_down', label: 'Slow down', hint: 'Decrease simulation speed.' },
  ] },
];
export const DEVICE_LABELS = { key: 'Keyboard', mouse: 'Mouse', wheel: 'Wheel' };
export const inputLabel = (input) => input.split(':').pop().replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());

// Keep the current option visible, but exclude other bindings of the same action.
// Other actions may deliberately share inputs (menu and world contexts differ).
export function availableBindings(action, rows, index = -1, device) {
  const used = new Set(rows.filter((_, i) => i !== index).map(normalizeInput));
  return INPUT_NAMES.filter((input) => !used.has(input) && (action !== 'pan' || !input.startsWith('wheel:')) && (!device || input.startsWith(`${device}:`)));
}
export function nextBinding(action, rows) {
  const options = availableBindings(action, rows);
  return KEY_DEFAULTS[action]?.find((input) => options.includes(input)) ?? options[0];
}
export function filterBindingGroups(query) {
  const search = query.trim().toLowerCase();
  return BINDING_GROUPS.map((group) => ({ ...group, actions: group.actions.filter((a) => `${group.title} ${a.id} ${a.label} ${a.hint}`.toLowerCase().includes(search)) })).filter((g) => g.actions.length);
}
