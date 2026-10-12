"""Exact armored runtime closure, never recovery/QA provenance expansion."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/build'))
import android_common as common
from test_android_tooling import binary_manifest

BUNDLE = 'assets/art/rig/armored_runtime_v1'
REG = BUNDLE + '/registration.json'
PARTS = ('girdle', 'head', 'head_seam_underlap', 'left_foot', 'left_forearm',
         'left_shin', 'left_thigh', 'left_upper_arm', 'neck', 'plate',
         'posterior_underlap', 'right_foot', 'right_forearm', 'right_shin',
         'right_thigh', 'right_upper_arm', 'torso')
SOURCES = {REG} | {BUNDLE + '/parts/' + name + suffix
                    for name in PARTS for suffix in ('.png', '.png.import')}

class ArmoredRuntimePackaging(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.root = self.work / 'source'
        self.manifest = common.read_manifest(ROOT, development_validation=True)
        # A real source subset, with the exact registered bytes and import settings.
        required = SOURCES | {'project.godot', 'assets/manifest.json',
            'addons/chapter_export/plugin.cfg', 'addons/chapter_export/plugin.gd',
            'tools/build/export_readiness.gd', 'tools/build/production_export_filter.gd',
            'game/presentation/armored/armored_raster.gd'}
        for asset in self.manifest['assets'].values():
            required.add(asset['path'][6:])
        for relative in required:
            dest = self.root / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, dest)
        self.registration = json.loads((self.root / REG).read_bytes())

    def stage(self):
        return common.stage_project(self.root, self.work / 'stage', self.manifest)

    def save_registration(self):
        (self.root / REG).write_text(json.dumps(self.registration))

    def test_staging_preserves_exact_runtime_bytes_and_only_runtime_closure(self):
        for relative in (BUNDLE + '/old.png', BUNDLE + '/parts/unregistered.png',
                         'recovery/private.png', 'tools/qa/private.png'):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'not-runtime')
        self.stage()
        stage = self.work / 'stage'
        actual = {p.relative_to(stage).as_posix() for p in (stage / BUNDLE).rglob('*') if p.is_file()}
        self.assertEqual(actual, SOURCES)
        for relative in SOURCES:
            self.assertEqual((stage / relative).read_bytes(), (ROOT / relative).read_bytes())
        self.assertFalse((stage / 'recovery').exists())
        self.assertFalse((stage / 'tools/qa').exists())
        staged_reg = json.loads((stage / REG).read_bytes())
        self.assertIs(staged_reg['final_export_allowed'], False)
        self.assertIs(staged_reg['native_gpu_verified'], False)
        self.assertEqual(staged_reg['dependencies'], self.registration['dependencies'])

    def test_missing_bundle_is_not_silent_fallback(self):
        (self.root / REG).unlink()
        with self.assertRaisesRegex(common.BuildError, 'missing|armored'):
            self.stage()

    def test_missing_and_corrupt_sources_fail(self):
        path = self.root / (BUNDLE + '/parts/head.png')
        path.write_bytes(b'corrupted')
        with self.assertRaisesRegex(common.BuildError, 'SHA-256|armored'):
            self.stage()
        path.unlink()
        with self.assertRaisesRegex(common.BuildError, 'missing|armored'):
            self.stage()

    def test_registration_requires_exact_part_ids(self):
        del self.registration['parts']['head']
        self.save_registration()
        with self.assertRaisesRegex(common.BuildError, 'armored'):
            self.stage()

    def test_invalid_json_and_extra_part_fail_closed(self):
        self.registration['parts']['unregistered'] = self.registration['parts']['head']
        self.save_registration()
        with self.assertRaisesRegex(common.BuildError, 'armored'):
            self.stage()
        for raw in (b'{invalid', b'[]', b'null'):
            (self.root / REG).write_bytes(raw)
            with self.subTest(raw=raw), self.assertRaisesRegex(common.BuildError, 'armored'):
                self.stage()

    def test_registration_rejects_traversal_absolute_alias_and_unregistered_paths(self):
        for path in ('res://' + BUNDLE + '/parts/../head.png',
                     '/tmp/head.png', 'res://' + BUNDLE + '/parts//head.png',
                     'res://' + BUNDLE + '/parts/left_foot.png',
                     'res://' + BUNDLE + '/parts/source/head.png',
                     'res://' + BUNDLE + '/parts\\head.png'):
            with self.subTest(path=path):
                self.registration['parts']['head']['texture_path'] = path
                self.save_registration()
                with self.assertRaisesRegex(common.BuildError, 'armored'):
                    self.stage()

    def test_source_and_directory_symlinks_are_rejected(self):
        for relative in (REG, BUNDLE + '/parts/head.png', BUNDLE + '/parts/head.png.import', BUNDLE + '/parts'):
            with self.subTest(relative=relative):
                target = self.work / 'moved'
                path = self.root / relative
                path.rename(target)
                path.symlink_to(target, target_is_directory=target.is_dir())
                try:
                    with self.assertRaisesRegex(common.BuildError, 'symlink'):
                        self.stage()
                finally:
                    path.unlink()
                    target.rename(path)

    def test_import_is_required_lossless_and_bound_to_exact_part(self):
        path = self.root / (BUNDLE + '/parts/head.png.import')
        original = path.read_bytes()
        for old, new in ((b'compress/mode=0', b'compress/mode=2'),
                         (b'mipmaps/generate=false', b'mipmaps/generate=true'),
                         (b'process/premult_alpha=false', b'process/premult_alpha=true'),
                         (b'process/fix_alpha_border=false', b'process/fix_alpha_border=true'),
                         (b'head.png-', b'wrong.png-')):
            with self.subTest(new=new):
                path.write_bytes(original.replace(old, new))
                with self.assertRaisesRegex(common.BuildError, 'armored|import'):
                    self.stage()
        path.unlink()
        with self.assertRaisesRegex(common.BuildError, 'missing|armored'):
            self.stage()

    def test_pending_registration_blocks_final_even_with_other_art_approved(self):
        final = copy.deepcopy(self.manifest)
        final.pop('development_validation')
        with self.assertRaisesRegex(common.BuildError, 'armored.*review|review.*armored'):
            common.stage_project(self.root, self.work / 'final', final)

    def archive_entries(self):
        entries = {'AndroidManifest.xml': binary_manifest(common.PIN['android']['package'],
            common.PIN['android']['version_name'], common.PIN['android']['version_code']),
            'classes.dex': b'engine', 'lib/arm64-v8a/libgodot_android.so': b'library',
            'assets/project.binary': b'project',
            'assets/assets/manifest.json': common.manifest_bytes(self.root, self.manifest),
            'assets/' + REG: (self.root / REG).read_bytes()}
        for asset in self.manifest['assets'].values():
            entries['assets/' + asset['path'][6:]] = (self.root / asset['path'][6:]).read_bytes()
        for name in PARTS:
            relative = BUNDLE + '/parts/' + name + '.png'
            imported = '.godot/imported/' + name + '.png-' + hashlib.md5(('res://' + relative).encode()).hexdigest() + '.ctex'
            entries['assets/' + relative + '.import'] = ('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\npath="res://' + imported + '"\n').encode()
            data = b'exact-imported-' + name.encode()
            path = self.root / imported
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            entries['assets/' + imported] = data
        return entries

    def check_archive(self, entries):
        apk, template = self.work / 'apk.zip', self.work / 'template.zip'
        with zipfile.ZipFile(template, 'w') as z:
            for name in ('AndroidManifest.xml', 'classes.dex', 'lib/arm64-v8a/libgodot_android.so'):
                z.writestr(name, entries[name])
        with zipfile.ZipFile(apk, 'w') as z:
            for name, data in entries.items():
                z.writestr(name, data)
        with zipfile.ZipFile(apk) as z, zipfile.ZipFile(template) as t:
            return common.validate_archive(z, t, self.root, self.manifest)

    def test_archive_accepts_exact_imported_bundle_without_raw_png(self):
        report = self.check_archive(self.archive_entries())
        self.assertEqual(report['version_code'], 3)
        self.assertEqual(report['armored_imported_payloads_compared'], 17)

    def test_source_only_archive_check_does_not_claim_imported_byte_comparison(self):
        entries = self.archive_entries()
        shutil.rmtree(self.root / '.godot')
        report = self.check_archive(entries)
        self.assertEqual(report['armored_imported_payloads_compared'], 0)

    def test_archive_rejects_missing_or_changed_registration_import_and_texture(self):
        original = self.archive_entries()
        for name in ('assets/' + REG, 'assets/' + BUNDLE + '/parts/head.png.import',
                     next(p for p in original if p.startswith('assets/.godot/imported/head.png-'))):
            for value in (None, b'corrupted'):
                with self.subTest(name=name, value=value):
                    entries = dict(original)
                    if value is None: del entries[name]
                    else: entries[name] = value
                    with self.assertRaisesRegex(common.BuildError, 'armored'):
                        self.check_archive(entries)

    def test_archive_rejects_raw_only_and_wrong_optional_raw_bytes(self):
        entries = self.archive_entries()
        relative = BUNDLE + '/parts/head.png'
        entries['assets/' + relative] = (self.root / relative).read_bytes()
        self.check_archive(entries)
        entries['assets/' + relative] = b'corrupted'
        with self.assertRaisesRegex(common.BuildError, 'armored'):
            self.check_archive(entries)
        entries['assets/' + relative] = (self.root / relative).read_bytes()
        del entries['assets/' + relative + '.import']
        with self.assertRaisesRegex(common.BuildError, 'armored'):
            self.check_archive(entries)

    def test_archive_does_not_allow_extra_bundle_or_provenance_payload(self):
        for name in ('assets/' + BUNDLE + '/parts/unregistered.png',
                     'assets/' + BUNDLE + '/qa.png', 'assets/recovery/source.png',
                     'assets/.godot/imported/head.png-unknown.ctex'):
            entries = self.archive_entries()
            entries[name] = b'excluded'
            with self.subTest(name=name), self.assertRaisesRegex(common.BuildError, 'not allowed'):
                self.check_archive(entries)

if __name__ == '__main__':
    unittest.main()
