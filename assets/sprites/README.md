# Original placeholder sprites

These 14 static 32×32 RGBA PNGs were created for this project with
`tools/generate_sprites.py` during the sprite-rendering implementation. They are
original geometric pixel art (buildings and role-colored people), not copied,
traced, downloaded, or derived from third-party assets. No image-generation
service or external image library was used.

Asset license: **CC0-1.0** (public-domain dedication),
https://creativecommons.org/publicdomain/zero/1.0/ . This dedication applies to
the PNGs in `buildings/` and `roles/`. No attribution is required.

The editable source is the drawing algorithm in `tools/generate_sprites.py` plus
the RGB colors in the building/role catalogs. These small generated PNGs are
checked in as runtime assets, separate from the generator and ignored build output.
Regenerate from the repository root using Python 3.10+ and its standard library:

```sh
python tools/generate_sprites.py
python tools/build.py --check-assets
```

The generator only writes the documented conventional placeholder paths
`assets/sprites/buildings/<id>.png` and `assets/sprites/roles/<id>.png` when still
configured on that element. It skips empty or custom paths. Do not place custom
art at those conventional paths if it should survive placeholder regeneration.
Colors come from the current catalog; unchanged input produces identical pixels
(and identical PNG bytes with the same Python/zlib version). Verified with Python
3.14 on Windows. There are no timestamps or random seeds in the image data.

The art has transparent corners/background, opaque geometric fills, and straight
alpha. Each image is one complete static frame with a top-left presentation pivot;
no atlas, frame sequence, animation timing, or gameplay collision is encoded.
Nearest-neighbor filtering is intentional for this pixel art. The renderer stretches
the image into the existing element rectangle without changing its gameplay bounds.
