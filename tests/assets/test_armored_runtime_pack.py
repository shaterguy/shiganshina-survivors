"""Lossless source derivatives, not raster/GPU visual acceptance."""
import hashlib
import importlib.util
import json
import os
import shutil
from pathlib import Path
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = Path(os.environ.get('ARMORED_SOURCE_ROOT', str(ROOT.parents[2]))).resolve()
FROZEN_ROOT = Path(os.environ.get('ARMORED_FROZEN_ROOT', str(SOURCE_ROOT))).resolve()
PROTECTED_INPUTS = ROOT.parent / 'evidence/protected-inputs-before.json'
PACK = ROOT / 'tools/art/pack_armored_runtime.py'
OUTPUT = ROOT / 'assets/art/rig/armored_runtime_v1'


class RuntimePackTest(unittest.TestCase):
    def module(self):
        self.assertTrue(PACK.is_file(), 'runtime packer must exist')
        spec = importlib.util.spec_from_file_location('pack_armored_runtime', PACK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_alpha_one_pixel_is_not_trimmed(self):
        module = self.module()
        source = Image.new('RGBA', (8, 7))
        source.putpixel((1, 2), (25, 80, 120, 1))
        source.putpixel((5, 4), (240, 65, 9, 255))
        packed, meta = module.trim_rgba(source, [6, 5])
        self.assertEqual(meta['trim_origin'], [1, 2])
        self.assertEqual(meta['packed_size'], [7, 5])
        self.assertEqual(meta['source_offset'], [0, 1])
        self.assertEqual(meta['pivot_packed'], [6, 4])
        self.assertEqual(module.reconstruct_rgba(packed, meta).tobytes(), source.tobytes())
        packed.putpixel((1, 1), (25, 80, 120, 0))
        self.assertFalse(module.verify_correspondence(source, packed, meta))

    def test_offset_corruption_is_detected(self):
        module = self.module()
        source = Image.new('RGBA', (8, 7))
        source.putpixel((2, 3), (1, 2, 3, 1))
        packed, meta = module.trim_rgba(source, [3, 4])
        self.assertTrue(module.verify_correspondence(source, packed, meta))
        meta['trim_origin'][0] += 1
        self.assertFalse(module.verify_correspondence(source, packed, meta))

    def test_actual_sources_round_trip_and_clear_border(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as tmp:
            registration = module.pack(SOURCE_ROOT, Path(tmp), frozen_root=FROZEN_ROOT)
            self.assertEqual(len(registration['parts']), 17)
            self.assertEqual(registration['source_count'], 16)
            self.assertLessEqual(registration['packed_rgba_bytes'], 10 * 1024 * 1024)
            for name, meta in registration['parts'].items():
                source = module.load_source(SOURCE_ROOT, meta)
                packed = Image.open(Path(tmp) / 'parts' / (name + '.png')).convert('RGBA')
                self.assertTrue(module.verify_correspondence(source, packed, meta), name)
                alpha = packed.getchannel('A')
                self.assertIsNone(alpha.crop((0, 0, packed.width, 1)).getbbox(), name)
                self.assertIsNone(alpha.crop((0, packed.height - 1, packed.width, packed.height)).getbbox(), name)
                self.assertIsNone(alpha.crop((0, 0, 1, packed.height)).getbbox(), name)
                self.assertIsNone(alpha.crop((packed.width - 1, 0, packed.width, packed.height)).getbbox(), name)
                self.assertEqual(meta['source_sha256'], hashlib.sha256((SOURCE_ROOT / meta['source_path']).read_bytes()).hexdigest())

    def test_posterior_region_is_explicit_and_deterministic(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            a = module.pack(SOURCE_ROOT, Path(first), frozen_root=FROZEN_ROOT)
            b = module.pack(SOURCE_ROOT, Path(second), frozen_root=FROZEN_ROOT)
            self.assertEqual(a, b)
            self.assertEqual(a['parts']['posterior_underlap']['source_region'], [545, 515, 110, 40])
            self.assertEqual(a['source_scale'], 0.085)
            self.assertEqual(a['torso_pivot_source'], [210, 1175])
            self.assertEqual(a['anchor_px'], [144, 280])
            self.assertEqual(a['anatomical_ground_y'], 278)
            self.assertEqual(a['quality_holds']['face_source_corner_reach']['status'], 'HOLD')
            hold = a['quality_holds']['face_source_corner_reach']
            self.assertIn('measurement_path', hold, 'strict inherited hold needs its frozen measurement source')
            measurement = json.loads((SOURCE_ROOT / hold['measurement_path']).read_text())
            self.assertEqual(hold['reach'], measurement['maximum_conservative_face_source_corner_world'])
            self.assertFalse(measurement['strict_all_frame_source_corner_gate_pass'])
            for path in Path(first).rglob('*'):
                if path.is_file():
                    self.assertEqual(path.read_bytes(), (Path(second) / path.relative_to(first)).read_bytes())

    def test_committed_pack_is_current_and_dependencies_unchanged(self):
        module = self.module()
        with tempfile.TemporaryDirectory() as tmp:
            module.pack(SOURCE_ROOT, Path(tmp), frozen_root=FROZEN_ROOT)
            for path in Path(tmp).rglob('*'):
                if path.is_file():
                    self.assertEqual(path.read_bytes(), (OUTPUT / path.relative_to(tmp)).read_bytes())
        before = json.loads(PROTECTED_INPUTS.read_text())
        self.assertEqual([], [x['path'] for x in before if hashlib.sha256((SOURCE_ROOT / x['path']).read_bytes()).hexdigest() != x['sha256']])


    def test_explicit_relocated_source_root_is_exact_and_confined(self):
        module = self.module()
        protected = json.loads(PROTECTED_INPUTS.read_text())
        with tempfile.TemporaryDirectory() as tmp:
            relocated, output = Path(tmp) / 'source', Path(tmp) / 'output'
            for record in protected:
                destination = relocated / record['path']
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(SOURCE_ROOT / record['path'], destination)
            module.pack(relocated, output, frozen_root=FROZEN_ROOT)
            for path in output.rglob('*'):
                if path.is_file():
                    self.assertEqual(path.read_bytes(), (OUTPUT / path.relative_to(output)).read_bytes())
            changed = relocated / 'recovery/armored-ferocious-drive/sources/limbs/left_foot.png'
            changed.write_bytes(changed.read_bytes() + b'changed')
            with self.assertRaisesRegex(ValueError, 'frozen source digest mismatch'):
                module.pack(relocated, Path(tmp) / 'reject', frozen_root=FROZEN_ROOT)
            changed.unlink()
            changed.symlink_to(SOURCE_ROOT / 'recovery/armored-ferocious-drive/sources/limbs/left_foot.png')
            with self.assertRaises(ValueError):
                module.pack(relocated, Path(tmp) / 'reject_symlink', frozen_root=FROZEN_ROOT)
            changed.unlink()
            shutil.copyfile(SOURCE_ROOT / 'recovery/armored-ferocious-drive/sources/limbs/left_foot.png', changed)
            for relative in [module.INPUT, module.SOURCE_HASHES, module.HELD_MEASUREMENT]:
                consumed = relocated / relative
                consumed.unlink()
                consumed.symlink_to(SOURCE_ROOT / relative)
                with self.assertRaises(ValueError):
                    module.pack(relocated, Path(tmp) / 'reject_json_symlink', frozen_root=FROZEN_ROOT)
                consumed.unlink()
                shutil.copyfile(SOURCE_ROOT / relative, consumed)
            (relocated / module.INPUT).unlink()
            with self.assertRaises(FileNotFoundError):
                module.pack(relocated, Path(tmp) / 'reject_missing', frozen_root=FROZEN_ROOT)
            shutil.copyfile(SOURCE_ROOT / module.INPUT, relocated / module.INPUT)
            with self.assertRaises(ValueError):
                module.pack(relocated, Path(tmp) / 'reject_wrong_root', frozen_root=FROZEN_ROOT / 'not-the-recorded-root')

if __name__ == '__main__':
    unittest.main()
