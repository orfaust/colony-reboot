package contracts

// Immutable catalog metadata. IDs are stable, untranslated role identifiers; name
// is resolved localization text. All strings borrow startup storage through shutdown.
// The catalog intentionally carries no color or sprite: subject presentation resolves
// its sprite from the subject type or its per-role overrides, never from a role-global
// asset or texture/GPU handle.
Role :: struct {
    id, name: string,
}
