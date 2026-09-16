"""Generate original geometric placeholder art (not derived from third-party assets)."""
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def png_bytes(width, height, pixels):
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)
    rows = b''.join(b'\0' + bytes(pixels[y * width * 4:(y + 1) * width * 4]) for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b''))


def original_sprite(color, role=False):
    size = 32
    pixels = bytearray(size * size * 4)
    base = (*color, 255)
    dark = tuple(c // 3 for c in color) + (255,)
    light = (220, 240, 255, 255)
    def rect(x, y, w, h, rgba):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                i = (yy * size + xx) * 4
                pixels[i:i + 4] = bytes(rgba)
    if role:
        rect(11, 2, 10, 9, light)
        rect(8, 12, 16, 12, base)
        rect(9, 24, 5, 7, dark)
        rect(18, 24, 5, 7, dark)
        rect(3, 13, 4, 10, base)
        rect(25, 13, 4, 10, base)
    else:
        rect(3, 9, 26, 21, dark)
        rect(5, 10, 22, 18, base)
        rect(9, 3, 14, 7, base)
        for x in (7, 14, 21):
            rect(x, 13, 4, 4, light)
        rect(13, 21, 6, 9, dark)
        rect(2, 30, 28, 2, light)
    return png_bytes(size, size, pixels)


def main():
    # Only the documented original placeholders may be overwritten, never arbitrary configured art.
    for source, folder, role in [('buildings.json', 'buildings', False), ('subject_roles.json', 'roles', True)]:
        for definition in json.loads((ROOT / 'assets/config' / source).read_text(encoding='utf-8')):
            identifier = definition['id']
            if not isinstance(identifier, str) or not identifier or any(c in identifier for c in '/\\\\:\x00') or identifier in ('.', '..'):
                raise ValueError('placeholder IDs must be single safe filename components')
            expected = f'assets/sprites/{folder}/{identifier}.png'
            if definition.get('sprite') != expected:
                continue
            path = ROOT / expected
            path.parent.mkdir(parents=True, exist_ok=True)
            color = definition['color']
            path.write_bytes(original_sprite((color['r'], color['g'], color['b']), role))
            print(expected)


if __name__ == '__main__':
    main()
