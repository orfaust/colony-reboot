package contracts

// Immutable catalog metadata. IDs are stable, untranslated role identifiers; name
// is resolved localization text. All strings borrow startup storage through shutdown.
// Sprite is a repository-relative assets/.../*.png path, never a texture/GPU handle.
Role :: struct {
    id, name: string,
    color: RGB,
    sprite: string,
}
