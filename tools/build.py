"""Validated build entry point. Python standard library only; no graphics context."""
import argparse
import json
from pathlib import Path, PurePosixPath
import struct
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'


def validate_png(path):
    """Accept static 8-bit RGB/RGBA PNGs, <=4096 per axis and <=64 MiB decoded."""
    if path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError('PNG exceeds 64 MiB file limit')
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError('not a PNG file')
    offset, header, ended, compressed = 8, None, False, bytearray()
    idat_closed = False
    seen_idat = False
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError('truncated PNG chunk')
        length = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError('truncated PNG payload')
        payload = data[offset + 8:end - 4]
        crc = struct.unpack_from('>I', data, end - 4)[0]
        if zlib.crc32(kind + payload) & 0xffffffff != crc:
            raise ValueError('PNG CRC mismatch')
        if header is None and kind != b'IHDR':
            raise ValueError('PNG must start with IHDR')
        if kind == b'IHDR':
            if header is not None or length != 13:
                raise ValueError('invalid PNG IHDR')
            header = struct.unpack('>IIBBBBB', payload)
            w, h, depth, color, compression, filtering, interlace = header
            if not (0 < w <= 4096 and 0 < h <= 4096):
                raise ValueError('PNG dimensions must be 1..4096')
            if depth != 8 or color not in (2, 6) or compression or filtering or interlace:
                raise ValueError('sprite must be non-interlaced 8-bit RGB/RGBA PNG')
        elif kind == b'acTL':
            raise ValueError('animated PNG requires an animation contract; static sprites only')
        elif kind == b'IDAT':
            if idat_closed:
                raise ValueError('nonconsecutive PNG IDAT chunks')
            seen_idat = True
            compressed.extend(payload)
        elif kind == b'IEND':
            if length or not seen_idat or end != len(data):
                raise ValueError('invalid PNG IEND')
            ended = True
            break
        else:
            if seen_idat:
                idat_closed = True
            if kind[:1].isupper() and kind != b'PLTE':
                raise ValueError('unsupported critical PNG chunk')
        offset = end
    if not header or not ended:
        raise ValueError('incomplete PNG')
    w, h, _, color, *_ = header
    stride = w * (4 if color == 6 else 3) + 1
    expected = h * stride
    if expected > 64 * 1024 * 1024:
        raise ValueError('PNG exceeds 64 MiB decoded limit')
    decoder = zlib.decompressobj()
    decoded = decoder.decompress(compressed, expected + 1)
    if len(decoded) != expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
        raise ValueError('invalid PNG pixel data size or compressed stream')
    if any(decoded[y * stride] > 4 for y in range(h)):
        raise ValueError('invalid PNG row filter')
    return w, h


def sprite_fields(value, location='$'):
    if isinstance(value, dict):
        for key, child in value.items():
            where = f'{location}.{key}'
            if key == 'sprite':
                yield where, child
            else:
                yield from sprite_fields(child, where)
    elif isinstance(value, list):
        for i, child in enumerate(value):
            yield from sprite_fields(child, f'{location}[{i}]')


def validate_assets(root=ROOT):
    root = Path(root).resolve()
    checked = set()
    sources = sorted((root / 'assets/config').rglob('*.json')) + sorted((root / 'assets/levels').rglob('*.json'))
    if not sources:
        raise ValueError('no asset configuration JSON found under assets/config or assets/levels')
    for source in sources:
        try:
            document = json.loads(source.read_text(encoding='utf-8'))
        except (OSError, ValueError) as exc:
            raise ValueError(f'{source.relative_to(root)}: {exc}') from exc
        for location, sprite in sprite_fields(document):
            context = f'{source.relative_to(root)}:{location}'
            if not isinstance(sprite, str):
                raise ValueError(f'{context}: sprite must be a string (empty disables it)')
            if not sprite:
                continue
            parts = sprite.split('/')
            if (not sprite.startswith('assets/') or not sprite.endswith('.png') or
                sprite.strip() != sprite or any(p in ('', '.', '..') for p in parts) or
                any(c in sprite for c in ('\\', ':', '\x00'))):
                raise ValueError(f'{context}: invalid repository-relative PNG path {sprite!r}')
            path = root.joinpath(*PurePosixPath(sprite).parts)
            try:
                if not path.resolve().is_relative_to(root / 'assets'):
                    raise ValueError('sprite resolves outside assets')
                # Enforce exact casing even on case-insensitive Windows filesystems.
                parent = root
                for part in parts:
                    if part not in {p.name for p in parent.iterdir()}:
                        raise ValueError('file missing or path case mismatch')
                    parent = parent / part
                if not path.is_file():
                    raise ValueError('sprite is not a file')
                if sprite not in checked:
                    validate_png(path)
                    checked.add(sprite)
            except (OSError, ValueError, zlib.error) as exc:
                raise ValueError(f'{context}: {sprite!r}: {exc}') from exc
    return len(checked)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-assets', action='store_true', help='validate only, do not invoke Odin')
    args = parser.parse_args(argv)
    try:
        count = validate_assets()
    except (OSError, ValueError) as exc:
        print(f'BUILD ERROR: {exc}', file=sys.stderr)
        return 1
    print(f'Validated {count} unique PNG sprites.', flush=True)
    if args.check_assets:
        return 0
    (ROOT / 'build').mkdir(exist_ok=True)
    output = 'build/colony-reboot.exe' if sys.platform == 'win32' else 'build/colony-reboot'
    try:
        return subprocess.run(['odin', 'build', 'src/app', f'-out:{output}'], cwd=ROOT).returncode
    except OSError as exc:
        print(f'BUILD ERROR: cannot run Odin: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
