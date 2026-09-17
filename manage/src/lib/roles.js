// Identity metadata for existing simulation jobs. Color and sprite belong to the
// subject type and its per-role overrides, never to this catalog.
export const newRole = (id) => ({ id, name_key: `subject_role_${id}_name` });

// This fallback is an identifier in the developer editor, not player-facing UI.
export function roleLabel(role, ctx) {
  const definition = Array.isArray(ctx.subject_roles) ? ctx.subject_roles.find((r) => r?.id === role) : null;
  return ctx.texts?.[definition?.name_key] ?? role;
}
