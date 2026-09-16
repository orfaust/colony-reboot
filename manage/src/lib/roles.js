// Presentation metadata for existing simulation jobs; paths do not create assets.
export const newRole = (id) => ({ id, name_key: `subject_role_${id}_name`, color: { r: 200, g: 200, b: 200 }, sprite: '' });

// This fallback is an identifier in the developer editor, not player-facing UI.
export function roleLabel(role, ctx) {
  const definition = Array.isArray(ctx.subject_roles) ? ctx.subject_roles.find((r) => r?.id === role) : null;
  return ctx.texts?.[definition?.name_key] ?? role;
}
