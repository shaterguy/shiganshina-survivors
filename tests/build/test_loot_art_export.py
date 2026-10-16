"""Exact loot-art staging and APK import-boundary tests; no engine invocation."""
import hashlib
import unittest
from test_android_tooling import ArchiveAndWrapperTests


class LootArtExportTests(unittest.TestCase):
    def setUp(self):
        self.base = ArchiveAndWrapperTests('test_archive_accepts_minimal_whitelist')
        self.base.setUp()
        self.addCleanup(self.base.doCleanups)
        self.mod = self.base.mod
        self.root = self.base.root
        self.entries = self.base.entries
        marker = self.root / 'game/ui/reward_feedback.gd'
        marker.parent.mkdir(parents=True)
        marker.write_text('extends Control\n')
        self.targets = {}
        for relative in self.mod.LOOT_ART_SOURCES:
            source = self.root / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(b'<svg xmlns="http://www.w3.org/2000/svg"/>')
            target = '.godot/imported/' + source.name + '-' + hashlib.md5(('res://' + relative).encode()).hexdigest() + '.ctex'
            self.targets[relative] = target
            self.entries['assets/' + relative] = source.read_bytes()
            self.entries['assets/' + relative + '.import'] = ('[remap]\npath="res://' + target + '"\n[deps]\ndest_files=["res://' + target + '"]\n').encode()
            self.entries['assets/' + target] = b'fixture-imported-texture'

    def test_exact_five_resources_and_legacy_fixture(self):
        result = self.base.check()
        self.assertEqual(result['loot_art_resources'], 5)
        self.assertEqual(result['loot_imported_payloads_compared'], 0)
        (self.root / 'game/ui/reward_feedback.gd').unlink()
        self.assertEqual(self.mod.loot_art_sources(self.root), ())

    def test_stage_exact_art_not_arbitrary_svg(self):
        for name in ('project.godot', 'addons/chapter_export/plugin.cfg', 'addons/chapter_export/plugin.gd',
                     'tools/build/export_readiness.gd', 'tools/build/production_export_filter.gd'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        (self.root / 'assets/icon.png').write_bytes(b'icon')
        extra = self.root / 'game/presentation/loot_art/unused.svg'
        extra.write_text('must not be staged')
        destination = self.root / 'staged'
        self.mod.stage_project(self.root, destination, self.base.manifest)
        for relative in self.mod.LOOT_ART_SOURCES:
            self.assertEqual((destination / relative).read_bytes(), (self.root / relative).read_bytes())
        self.assertFalse((destination / extra.relative_to(self.root)).exists())

    def test_partial_source_set_fails_closed(self):
        (self.root / self.mod.LOOT_ART_SOURCES[0]).unlink()
        with self.assertRaises(self.mod.BuildError):
            self.mod.loot_art_sources(self.root)

    def test_missing_import_metadata_rejected(self):
        del self.entries['assets/' + self.mod.LOOT_ART_SOURCES[0] + '.import']
        with self.assertRaisesRegex(self.mod.BuildError, 'loot imported resource missing'):
            self.base.check()

    def test_wrong_import_path_rejected(self):
        name = self.mod.LOOT_ART_SOURCES[0]
        self.entries['assets/' + name + '.import'] = b'[remap]\npath="res://.godot/imported/foreign.ctex"\n'
        self.entries['assets/.godot/imported/foreign.ctex'] = b'foreign'
        with self.assertRaisesRegex(self.mod.BuildError, 'unexpected imported resource'):
            self.base.check()

    def test_empty_imported_texture_rejected(self):
        self.entries['assets/' + next(iter(self.targets.values()))] = b''
        with self.assertRaisesRegex(self.mod.BuildError, 'loot imported bytes empty'):
            self.base.check()

    def test_changed_original_rejected(self):
        self.entries['assets/' + self.mod.LOOT_ART_SOURCES[0]] = b'changed'
        with self.assertRaisesRegex(self.mod.BuildError, 'loot original changed'):
            self.base.check()

    def test_fresh_import_bytes_compared_and_mismatch_rejected(self):
        for target in self.targets.values():
            path = self.root / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(self.entries['assets/' + target])
        self.assertEqual(self.base.check()['loot_imported_payloads_compared'], 5)
        (self.root / next(iter(self.targets.values()))).write_bytes(b'changed-import')
        with self.assertRaisesRegex(self.mod.BuildError, 'loot imported bytes changed'):
            self.base.check()


if __name__ == '__main__':
    unittest.main()
