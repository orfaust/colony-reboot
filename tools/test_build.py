import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys
import shutil
from unittest.mock import patch

import build
from generate_sprites import original_sprite, png_bytes


class SpriteBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'assets/config').mkdir(parents=True)
        self.png = self.root / 'assets/art.png'
        self.png.write_bytes(original_sprite((20, 100, 200)))
        self.source = self.root / 'assets/config/default/buildings.json'
        self.source.parent.mkdir(parents=True)
        self.write([{'id': 'example', 'sprite': 'assets/art.png'}])

    def write(self, data):
        self.source.write_text(json.dumps(data), encoding='utf-8')

    def test_existing_png_and_duplicate_cache(self):
        self.write([{'sprite': 'assets/art.png'}, {'sprite': 'assets/art.png'}])
        self.assertEqual(build.validate_assets(self.root), 1)
        self.assertEqual(build.validate_png(self.png), (32, 32))

    def test_absent_empty_are_color_fallback(self):
        self.write([{}, {'sprite': ''}])
        self.assertEqual(build.validate_assets(self.root), 0)

    def test_missing_path_reports_source_and_field(self):
        self.png.unlink()
        with self.assertRaisesRegex(ValueError, r'buildings.json:\$\[0\].sprite.*art.png'):
            build.validate_assets(self.root)

    def test_every_profile_is_checked(self):
        for folder in ['default', 'experiment']:
            path = self.root / f'assets/config/{folder}/additional.json'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{"nested":{"sprite":"assets/missing.png"}}', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'nested.sprite'):
                build.validate_assets(self.root)
            path.unlink()

    def test_invalid_paths_and_types(self):
        for value in [None, 4, '../art.png', 'assets/../art.png', 'assets//art.png', 'assets\\art.png', 'assets/art.jpg', ' assets/art.png', 'assets/./art.png', 'C:/art.png']:
            with self.subTest(value=value):
                self.write([{'sprite': value}])
                with self.assertRaises(ValueError):
                    build.validate_assets(self.root)

    def test_wrong_case_and_directory_rejected(self):
        for value in ['assets/ART.png', 'assets/folder.png']:
            (self.root / 'assets/folder.png').mkdir(exist_ok=True)
            self.write([{'sprite': value}])
            with self.assertRaises(ValueError):
                build.validate_assets(self.root)

    def test_corrupt_and_non_png_rejected(self):
        for data in [b'not PNG', self.png.read_bytes()[:30], self.png.read_bytes()[:-1], b'\x89PNG\r\n\x1a\n']:
            self.png.write_bytes(data)
            with self.assertRaises(ValueError):
                build.validate_assets(self.root)

    def test_bad_crc_rejected(self):
        data = bytearray(original_sprite((1, 2, 3)))
        data[20] ^= 1
        self.png.write_bytes(data)
        with self.assertRaisesRegex(ValueError, 'CRC'):
            build.validate_assets(self.root)

    def test_invalid_dimensions_rejected(self):
        self.png.write_bytes(png_bytes(0, 1, b''))
        with self.assertRaisesRegex(ValueError, 'dimensions'):
            build.validate_assets(self.root)

    def test_reproducible_original_art(self):
        self.assertEqual(original_sprite((20, 100, 200)), self.png.read_bytes())
        self.assertNotEqual(original_sprite((20, 100, 200), True), self.png.read_bytes())

    def test_invalid_json_fails(self):
        self.source.write_text('{', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'buildings.json'):
            build.validate_assets(self.root)

    def test_cli_build_fails_before_output_directory_on_missing_sprite(self):
        tools = self.root / 'tools'
        tools.mkdir()
        script = tools / 'build.py'
        shutil.copyfile(build.__file__, script)
        self.png.unlink()
        result = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('BUILD ERROR:', result.stderr)
        self.assertIn('buildings.json:$[0].sprite', result.stderr)
        self.assertFalse((self.root / 'build').exists())

    def test_cli_positive_asset_check(self):
        tools = self.root / 'tools'
        tools.mkdir()
        script = tools / 'build.py'
        shutil.copyfile(build.__file__, script)
        result = subprocess.run([sys.executable, str(script), '--check-assets'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Validated 1 unique PNG sprites.', result.stdout)

    def test_failed_validation_does_not_invoke_compiler(self):
        with patch.object(build, 'validate_assets', side_effect=ValueError('missing sprite')), patch.object(build.subprocess, 'run') as compiler:
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(build.main([]), 1)
            compiler.assert_not_called()

    def test_validation_precedes_compiler_and_propagates_failure(self):
        with patch.object(build, 'validate_assets', return_value=1) as validator, patch.object(build.subprocess, 'run') as compiler:
            def compile_now(*args, **kwargs):
                validator.assert_called_once()
                self.assertEqual(args[0][:3], ['odin', 'build', 'src/app'])
                return type('Result', (), {'returncode': 7})()
            compiler.side_effect = compile_now
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(build.main([]), 7)


if __name__ == '__main__':
    unittest.main()
