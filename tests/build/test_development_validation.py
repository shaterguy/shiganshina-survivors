"""Explicit development validation is a temporary package, never art approval."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/build'))
import android_common as common

REPLACEMENTS = {'titan_runner', 'titan_sweeper', 'boss_charger', 'boss_leaper', 'boss_abnormal'}


class DevelopmentValidationTests(unittest.TestCase):
    def setUp(self):
        self.original_bytes = (ROOT/'assets/manifest.json').read_bytes()
        self.original = json.loads(self.original_bytes)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)

    def dev(self):
        self.assertTrue(hasattr(common, 'development_manifest'), 'missing explicit development-validation staging')
        return common.development_manifest(self.original, hashlib.sha256(self.original_bytes).hexdigest())

    def test_default_final_gate_still_rejects_source(self):
        with self.assertRaisesRegex(common.BuildError, 'art_review_pending'):
            common.read_manifest(ROOT)

    def test_exact_five_replaced_without_mutating_original(self):
        before = copy.deepcopy(self.original)
        dev = self.dev()
        self.assertEqual(self.original, before)
        self.assertEqual((ROOT/'assets/manifest.json').read_bytes(), self.original_bytes)
        changed = {key for key in self.original['assets'] if self.original['assets'][key] != dev['assets'][key]}
        self.assertEqual(changed, REPLACEMENTS)
        basic = dev['assets']['titan_basic']
        for key in REPLACEMENTS:
            record = dev['assets'][key]
            for field in ('path', 'sha256', 'width', 'height', 'columns', 'cell_w', 'cell_h', 'anchor_px', 'animations'):
                self.assertEqual(record[field], basic[field])
            self.assertIs(record['development_only'], True)
            self.assertIs(record['export_blocked'], True)
            self.assertEqual(record['review_status'], 'development_placeholder_not_final_approval')
            self.assertEqual(record['development_placeholder']['original_sha256'], self.original['assets'][key]['sha256'])
            self.assertEqual(record['development_placeholder']['original_path'], self.original['assets'][key]['path'])
        self.assertEqual(dev['art_revision_status'], self.original['art_revision_status'])
        self.assertIs(dev['art_revision_status']['final_export_allowed'], False)
        self.assertIn('INCOMPLETE', dev['development_validation']['notice'])
        self.assertIn('5 titan_basic', dev['development_validation']['notice'])

    def test_staged_manifest_requires_explicit_mode_to_pass(self):
        dev = self.dev()
        with self.assertRaisesRegex(common.BuildError, 'art_review_pending'):
            common.check_readiness(dev)
        common.check_readiness(dev, development_validation=True)

    def test_explicit_mode_does_not_accept_untransformed_blocked_manifest(self):
        self.assertTrue(hasattr(common, 'development_manifest'), 'missing explicit development-validation staging')
        with self.assertRaisesRegex(common.BuildError, 'development'):
            common.check_readiness(self.original, development_validation=True)

    def test_bad_fallback_hash_path_or_approval_is_rejected(self):
        self.assertTrue(hasattr(common, 'development_manifest'), 'missing explicit development-validation staging')
        for field, value in [('sha256', 'f'*64), ('path', self.original['assets']['titan_runner']['path']),
                             ('export_blocked', True), ('review_status', 'unreviewed')]:
            with self.subTest(field=field):
                manifest = copy.deepcopy(self.original)
                manifest['assets']['titan_basic'][field] = value
                with self.assertRaisesRegex(common.BuildError, 'fallback'):
                    common.development_manifest(manifest, hashlib.sha256(self.original_bytes).hexdigest())

    def test_extra_or_missing_blocked_id_is_rejected(self):
        self.assertTrue(hasattr(common, 'development_manifest'), 'missing explicit development-validation staging')
        for name, value in [('garrison_01', True), ('titan_runner', False)]:
            with self.subTest(name=name):
                manifest = copy.deepcopy(self.original); manifest['assets'][name]['export_blocked'] = value
                with self.assertRaisesRegex(common.BuildError, 'exactly'):
                    common.development_manifest(manifest, hashlib.sha256(self.original_bytes).hexdigest())

    def test_tampered_dev_provenance_final_gate_or_placeholder_is_rejected(self):
        for mutation in ('final', 'missing_id', 'approval', 'path', 'hash', 'frames', 'provenance', 'notice', 'metadata'):
            with self.subTest(mutation=mutation):
                dev = self.dev()
                if mutation == 'final': dev['art_revision_status']['final_export_allowed'] = True
                if mutation == 'missing_id': dev['development_validation']['replacement_ids'].pop()
                if mutation == 'approval': dev['assets']['titan_runner']['export_blocked'] = False
                if mutation == 'path': dev['assets']['titan_runner']['path'] = self.original['assets']['titan_runner']['path']
                if mutation == 'hash': dev['assets']['titan_runner']['sha256'] = self.original['assets']['titan_runner']['sha256']
                if mutation == 'frames': dev['assets']['titan_runner']['columns'] = 99
                if mutation == 'provenance': del dev['assets']['titan_runner']['development_placeholder']
                if mutation == 'notice': dev['development_validation']['notice'] = ''
                if mutation == 'metadata': del dev['development_validation']
                with self.assertRaises(common.BuildError):
                    common.check_readiness(dev, development_validation=True)

    def test_candidate_source_and_rejected_paths_cannot_become_runtime_assets(self):
        for path in ('res://assets/art/source/foo.png', 'res://assets/art/candidates/foo.png',
                     'res://assets/art/characters/rejected/foo.png', 'res://assets/art/previews/foo.png'):
            with self.subTest(path=path):
                dev = self.dev(); dev['assets']['game_icon']['path'] = path
                with self.assertRaisesRegex(common.BuildError, 'runtime'):
                    common.check_readiness(dev, development_validation=True)

    def test_staging_contains_no_blocked_pngs_or_source_candidates(self):
        dev = self.dev(); destination = self.work/'staged'
        common.stage_project(ROOT, destination, dev)
        staged = common.read_manifest(destination, development_validation=True)
        self.assertEqual(staged, dev)
        common.verify_source_hashes(destination, staged)
        staged_files = [p for p in destination.rglob('*') if p.is_file()]
        paths = {p.relative_to(destination).as_posix() for p in staged_files}
        hashes = {common.sha256(p) for p in staged_files}
        for key in REPLACEMENTS:
            self.assertNotIn(self.original['assets'][key]['path'][6:], paths)
            self.assertNotIn(self.original['assets'][key]['sha256'], hashes)
        self.assertFalse(any('/source/' in p or '/candidates/' in p or '/previews/' in p or '/rejected/' in p for p in paths))
        self.assertEqual((ROOT/'assets/manifest.json').read_bytes(), self.original_bytes)

    def test_archive_rejects_old_png_bytes_disguised_as_allowed_import(self):
        # Regression target: validate_archive must inspect payloads, not just path allowlists.
        from test_android_tooling import binary_manifest
        dev = self.dev()
        source = self.work/'staged'
        common.stage_project(ROOT, source, dev)
        vendor = {'AndroidManifest.xml': b'original', 'classes.dex': b'pinned-code',
                  'lib/arm64-v8a/libgodot_android.so': b'pinned-library'}
        template = self.work/'template.zip'
        with zipfile.ZipFile(template, 'w') as archive:
            for key, value in vendor.items(): archive.writestr(key, value)
        entries = dict(vendor)
        entries.update({'AndroidManifest.xml': binary_manifest('com.shaterguy.shiganshina.dev', '0.1.0-dev3', 3),
                        'assets/project.binary': b'project',
                        'assets/assets/manifest.json': (source/'assets/manifest.json').read_bytes()})
        for folder in ('data', 'chapters'):
            for path in (source/folder).rglob('*.json'):
                entries['assets/'+path.relative_to(source).as_posix()] = path.read_bytes()
        for record in dev['assets'].values():
            relative = record['path'][6:]
            entries['assets/'+relative] = (source/relative).read_bytes()
        basic = dev['assets']['titan_basic']
        relative = basic['path'][6:]
        imported = '.godot/imported/' + Path(relative).name + '-' + hashlib.md5(basic['path'].encode()).hexdigest() + '.ctex'
        entries['assets/'+relative+'.import'] = ('path="res://'+imported+'"').encode()
        entries['assets/'+imported] = (ROOT/self.original['assets']['titan_runner']['path'][6:]).read_bytes()
        apk = self.work/'malicious.apk'
        with zipfile.ZipFile(apk, 'w') as archive:
            for key, value in entries.items(): archive.writestr(key, value)
        with zipfile.ZipFile(apk) as archive, zipfile.ZipFile(template) as pinned:
            with self.assertRaisesRegex(common.BuildError, 'rejected PNG bytes'):
                common.validate_archive(archive, pinned, source, dev)

    def test_dev_build_preflight_is_distinct_from_final_ready(self):
        process = subprocess.run([sys.executable, str(ROOT/'tools/build/build_android.py'), '--project', str(ROOT),
                                  '--development-validation', '--check-ready'], capture_output=True, text=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        self.assertIn('DEVELOPMENT_VALIDATION_READY', process.stdout)
        self.assertIn('final_export_allowed=false', process.stdout)
        self.assertNotIn('EXPORT_READY:', process.stdout)

    def test_sign_and_verify_offer_explicit_dev_mode_without_changing_default(self):
        for script in ('sign_android.py', 'verify_android.py'):
            with self.subTest(script=script):
                process = subprocess.run([sys.executable, str(ROOT/'tools/build'/script), '--help'], capture_output=True, text=True)
                self.assertIn('--development-validation', process.stdout)


if __name__ == '__main__': unittest.main()
