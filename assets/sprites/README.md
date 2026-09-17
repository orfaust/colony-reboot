# Original placeholder sprites

These 11 static 32×32 RGBA PNGs in `buildings/` were created for this project with
`tools/generate_sprites.py` during the sprite-rendering implementation. They are
original geometric pixel art, not copied, traced, downloaded, or derived from
third-party assets. No image-generation service or external image library was used.

`roles/` holds three more original 32×32 placeholders (`worker`, `supervisor`,
`repairer`) from that same earlier iteration, drawn by `original_sprite(color,
role=True)`. Subject types still reference them through `subject.roles[].sprite`
overrides in `subjects.json`, but they are no longer regenerated: role-global colors
were removed from `subject_roles.json`, so the current generator has no color source
for them. Treat them as static checked-in art whose drawing algorithm is still
available in the generator.

Asset license: **CC0-1.0** (public-domain dedication),
https://creativecommons.org/publicdomain/zero/1.0/ . This dedication applies to
the PNGs in `buildings/` and `roles/`. No attribution is required.

The editable source is the drawing algorithm in `tools/generate_sprites.py` plus
the RGB colors in the building catalog. These small generated PNGs are checked in
as runtime assets, separate from the generator and ignored build output. Regenerate
from the repository root using Python 3.10+ and its standard library:

```sh
python tools/generate_sprites.py
python tools/build.py --check-assets
```

The generator only writes the documented conventional placeholder path
`assets/sprites/buildings/<id>.png` when still configured on that building type. It
skips empty or custom paths. Do not place custom art at that conventional path if
it should survive placeholder regeneration. Colors come from the current catalog;
unchanged input produces identical pixels (and identical PNG bytes with the same
Python/zlib version). Verified with Python 3.14 on Windows. There are no timestamps
or random seeds in the image data.

`roles/` still holds three role-colored placeholders from that earlier iteration.
Subject types reference them through `subject.roles[].sprite` overrides, so subject
rendering still uses them; only the role catalog stopped defining color or sprite.
The current generator does not recreate them, because role-global colors no longer
exist in any catalog. Their drawing algorithm remains available as the `role=True`
variant. They are retained as static art until replaced or removed.

The art has transparent corners/background, opaque geometric fills, and straight
alpha. Each image is one complete static frame with a top-left presentation pivot;
no atlas, frame sequence, animation timing, or gameplay collision is encoded.
Nearest-neighbor filtering is intentional for this pixel art. The renderer stretches
the image into the existing element rectangle without changing its gameplay bounds.
