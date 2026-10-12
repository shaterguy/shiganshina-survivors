"""Exercise real staging/APK validation with the approved font's exact source bytes."""
from pathlib import Path
import shutil
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/build'))
import android_common as common
import smoke_android_export as smoke
import test_android_tooling as tooling

FONT = 'assets/fonts/NotoSansKR-wght.ttf'
LICENSE = 'assets/fonts/NotoSansKR-OFL.txt'
THEME = 'game/ui/korean_ui_theme.tres'
IMPORTED = '.godot/imported/NotoSansKR-wght.ttf-03cd58358086673b0b569abab50ec7d1.fontdata'
BUNDLE = (FONT, FONT + '.import', LICENSE)
FONT_SHA256 = '194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252'
LICENSE_SHA256 = '1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9'


def copy_source_files(root, relatives):
    for relative in relatives:
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)


class BundledFontStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.root = self.work / 'source'
        self.manifest = common.read_manifest(ROOT, development_validation=True)
        # Real candidate input files, not replacement implementation/source snapshots.
        paths = {'project.godot', 'assets/manifest.json', 'addons/chapter_export/plugin.cfg',
                 'addons/chapter_export/plugin.gd', 'tools/build/export_readiness.gd',
                 'tools/build/production_export_filter.gd', THEME, *BUNDLE}
        paths.update(record['path'][6:] for record in self.manifest['assets'].values())
        copy_source_files(self.root, paths)

    def stage(self):
        destination = self.work / 'staged'
        common.stage_project(self.root, destination, self.manifest)
        return destination

    def test_stages_exact_font_import_and_license_without_unrelated_files(self):
        for relative in ('assets/fonts/Other.ttf', 'assets/fonts/Other-OFL.txt',
                         'assets/fonts/subfolder/NotoSansKR-wght.ttf'):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'unapproved')
        target = self.stage()
        copied = {p.relative_to(target).as_posix() for p in (target / 'assets/fonts').rglob('*') if p.is_file()}
        self.assertEqual(copied, set(BUNDLE))
        for relative in BUNDLE:
            self.assertEqual((target / relative).read_bytes(), (ROOT / relative).read_bytes())
        self.assertEqual(common.sha256(target / FONT), FONT_SHA256)
        self.assertEqual(common.sha256(target / LICENSE), LICENSE_SHA256)
        self.assertFalse((target / '.godot').exists(), 'staging must import fresh, not copy the editor cache')

    def test_missing_font_import_or_license_fails_closed(self):
        for relative in BUNDLE:
            with self.subTest(relative=relative):
                path = self.root / relative
                original = path.read_bytes()
                path.unlink()
                try:
                    with self.assertRaisesRegex(common.BuildError, 'missing'):
                        self.stage()
                finally:
                    path.write_bytes(original)

    def test_tampered_font_or_license_fails_closed(self):
        for relative in (FONT, LICENSE):
            with self.subTest(relative=relative):
                path = self.root / relative
                original = path.read_bytes()
                path.write_bytes(original + b'tampered')
                try:
                    with self.assertRaisesRegex(common.BuildError, 'SHA-256'):
                        self.stage()
                finally:
                    path.write_bytes(original)

    def test_import_must_link_the_exact_source_and_imported_font(self):
        path = self.root / (FONT + '.import')
        original = path.read_bytes()
        for old, new in ((FONT, 'assets/fonts/Other.ttf'), (IMPORTED, IMPORTED.replace('03cd', 'ffff'))):
            with self.subTest(old=old):
                path.write_bytes(original.replace(old.encode(), new.encode()))
                try:
                    with self.assertRaisesRegex(common.BuildError, 'font import'):
                        self.stage()
                finally:
                    path.write_bytes(original)

    def test_import_rejects_invalid_remap_key_importer_and_type(self):
        path = self.root / (FONT + '.import')
        original = path.read_bytes()
        for old, new in ((b'path=', b'wrong_key='), (b'font_data_dynamic', b'texture'), (b'FontFile', b'OtherResource')):
            with self.subTest(old=old):
                path.write_bytes(original.replace(old, new))
                try:
                    with self.assertRaisesRegex(common.BuildError, 'font import'):
                        self.stage()
                finally:
                    path.write_bytes(original)

    def test_font_bundle_rejects_symlink_files(self):
        for relative in BUNDLE:
            with self.subTest(relative=relative):
                path = self.root / relative
                original = path.read_bytes()
                outside = self.work / 'outside'
                outside.write_bytes(original)
                path.unlink()
                path.symlink_to(outside)
                try:
                    with self.assertRaisesRegex(common.BuildError, 'symlink'):
                        self.stage()
                finally:
                    path.unlink()
                    path.write_bytes(original)

    def test_font_bundle_rejects_symlink_directory(self):
        directory = self.root / 'assets/fonts'
        outside = self.work / 'outside-fonts'
        directory.rename(outside)
        directory.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(common.BuildError, 'symlink'):
            self.stage()

    def test_fonts_do_not_broaden_the_manifest_runtime_asset_predicate(self):
        for relative in BUNDLE:
            self.assertFalse(common.is_runtime_asset({'path': 'res://' + relative, 'kind': 'font'}))
        self.assertIs(self.manifest['art_revision_status']['final_export_allowed'], False)
        self.assertEqual(sorted(name for name, record in self.manifest['assets'].items()
                                if record.get('export_blocked')), common.DEV_IDS)


class BundledFontArchiveTests(unittest.TestCase):
    def setUp(self):
        # Reuse the existing genuine binary-XML Android structure and pinned vendor fixture.
        tooling.ArchiveAndWrapperTests.setUp(self)
        copy_source_files(self.root, (*BUNDLE, THEME))
        self.entries['assets/' + LICENSE] = (ROOT / LICENSE).read_bytes()
        self.entries['assets/' + FONT + '.import'] = (
            '[remap]\n\nimporter="font_data_dynamic"\ntype="FontFile"\n'
            'uid="uid://b7mqve36h18dg"\npath="res://' + IMPORTED + '"\n\0').encode()
        # Opaque engine payload: no invented fontdata parser or raw-font duplication.
        self.entries['assets/' + IMPORTED] = b'opaque-Godot-imported-font-resource'

    def check(self):
        return tooling.ArchiveAndWrapperTests.check(self)

    def test_accepts_exact_import_remap_and_license_without_raw_font(self):
        self.assertNotIn('assets/' + FONT, self.entries)
        self.check()

    def test_accepts_exact_raw_font_and_license(self):
        del self.entries['assets/' + FONT + '.import']
        del self.entries['assets/' + IMPORTED]
        self.entries['assets/' + FONT] = (ROOT / FONT).read_bytes()
        self.check()

    def test_rejects_missing_bundled_font(self):
        del self.entries['assets/' + FONT + '.import']
        del self.entries['assets/' + IMPORTED]
        with self.assertRaisesRegex(common.BuildError, 'bundled font'):
            self.check()

    def test_rejects_missing_or_tampered_license(self):
        member = 'assets/' + LICENSE
        original = self.entries.pop(member)
        with self.assertRaisesRegex(common.BuildError, 'font license'):
            self.check()
        self.entries[member] = original + b'tampered'
        with self.assertRaisesRegex(common.BuildError, 'font license'):
            self.check()

    def test_checks_raw_font_hash_even_when_valid_import_is_present(self):
        self.entries['assets/' + FONT] = b'tampered-font'
        with self.assertRaisesRegex(common.BuildError, 'font.*SHA-256'):
            self.check()

    def test_rejects_missing_import_target_even_with_valid_raw_font(self):
        del self.entries['assets/' + IMPORTED]
        self.entries['assets/' + FONT] = (ROOT / FONT).read_bytes()
        with self.assertRaisesRegex(common.BuildError, 'font import'):
            self.check()

    def test_rejects_wrong_remap_hash_extension_and_extra_resource_reference(self):
        member = 'assets/' + FONT + '.import'
        original = self.entries[member]
        for remap in (IMPORTED.replace('03cd', 'ffff'), IMPORTED + '.ctex', 'assets/fonts/Other.ttf'):
            with self.subTest(remap=remap):
                self.entries[member] = original.replace(IMPORTED.encode(), remap.encode())
                with self.assertRaisesRegex(common.BuildError, 'font import'):
                    self.check()
        self.entries[member] = original.rstrip(b'\0') + b'extra="res://assets/fonts/Other.ttf"\n'
        with self.assertRaisesRegex(common.BuildError, 'font import'):
            self.check()

    def test_rejects_wrong_import_key_type_and_importer(self):
        member = 'assets/' + FONT + '.import'
        original = self.entries[member]
        for old, new in ((b'path=', b'wrong_key='), (b'FontFile', b'OtherResource'), (b'font_data_dynamic', b'texture')):
            with self.subTest(old=old):
                self.entries[member] = original.replace(old, new)
                with self.assertRaisesRegex(common.BuildError, 'font import'):
                    self.check()

    def test_rejects_orphan_imported_font_without_a_remap(self):
        del self.entries['assets/' + FONT + '.import']
        self.entries['assets/' + FONT] = (ROOT / FONT).read_bytes()
        with self.assertRaisesRegex(common.BuildError, 'not allowed'):
            self.check()

    def test_rejects_arbitrary_font_license_and_imported_resource(self):
        for relative in ('assets/fonts/Other.ttf', 'assets/fonts/Other-OFL.txt',
                         '.godot/imported/Other.ttf-03cd58358086673b0b569abab50ec7d1.fontdata'):
            with self.subTest(relative=relative):
                self.entries['assets/' + relative] = b'unapproved'
                try:
                    with self.assertRaisesRegex(common.BuildError, 'not allowed: assets/' + relative):
                        self.check()
                finally:
                    del self.entries['assets/' + relative]

    def test_validation_rechecks_pinned_source_font(self):
        (self.root / FONT).write_bytes(b'tampered-source-font')
        with self.assertRaisesRegex(common.BuildError, 'SHA-256'):
            self.check()


class BundledFontSmokeFixtureTests(unittest.TestCase):
    def test_real_smoke_fixture_copies_and_stages_only_exact_font_bundle(self):
        def inspect_fixture_instead_of_launching(command):
            root = Path(command[command.index('--project') + 1])
            actual = {p.relative_to(root).as_posix() for p in (root / 'assets').rglob('*') if p.is_file()}
            self.assertEqual(actual, {*BUNDLE, 'assets/manifest.json', 'assets/art/ui/game_icon.png'})
            manifest = common.read_manifest(root)
            destination = root.parent / 'staged'
            common.stage_project(root, destination, manifest)
            common.verify_source_hashes(destination, manifest)
            for relative in BUNDLE:
                self.assertEqual((root / relative).read_bytes(), (ROOT / relative).read_bytes())
                self.assertEqual((destination / relative).read_bytes(), (ROOT / relative).read_bytes())
            self.assertEqual({p.relative_to(destination).as_posix()
                              for p in (destination / 'assets/fonts').rglob('*') if p.is_file()}, set(BUNDLE))
            self.assertFalse((destination / '.godot').exists())
            # Stop at the subprocess boundary; never invent an APK/report or launch Godot.
            return SimpleNamespace(returncode=73)

        with patch.object(sys, 'argv', ['smoke_android_export.py', '--template', '/unused-template.apk']), \
                patch.object(smoke.subprocess, 'run', side_effect=inspect_fixture_instead_of_launching) as launch:
            self.assertEqual(smoke.main(), 73)
            self.assertEqual(launch.call_count, 1)


if __name__ == '__main__':
    unittest.main()
