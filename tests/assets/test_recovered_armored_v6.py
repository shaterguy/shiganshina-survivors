"""Byte identity and one-entry registration guards, not visual/run/charge approval.

A changed v6 PNG, lost v2 cell, altered animation meaning, or unrelated manifest
edit must fail these tests. Staged registration deliberately leaves runtime v2.
"""
import copy
import hashlib
import json
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PNG = ROOT / 'assets/art/characters/armored_titan_v6_elbow.png'
REGISTRATION = ROOT / 'docs/art/recovery-armored-v6-registration.json'
REVIEW = ROOT / 'docs/art/recovery-armored-v6-review.json'
EXPECTED_SHA = 'e3b3fe2008cb4db79e8df72bf670dc6c87e37c81c055c85a1546fc47dc7ea427'
BLOCKED = {'titan_runner', 'titan_sweeper', 'boss_charger', 'boss_leaper', 'boss_abnormal'}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()


def cell(image, index, columns):
    x, y = index % columns * 192, index // columns * 256
    return image.crop((x, y, x + 192, y + 256)).tobytes()


class RecoveredArmoredV6Tests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(PNG.is_file(), 'The exact v6 PNG must be staged before runtime registration.')
        self.assertTrue(REGISTRATION.is_file(), 'Reconstructed candidate metadata must exist.')
        self.assertTrue(REVIEW.is_file(), 'Review state must explicitly guard registration.')
        self.registration = json.loads(REGISTRATION.read_text())
        self.review = json.loads(REVIEW.read_text())
        self.entry = self.registration['candidate_entry']
        self.baseline = self.registration['baseline_armored_entry']
        self.manifest = json.loads((ROOT / 'assets/manifest.json').read_text())

    def test_exact_png_identity_and_geometry(self):
        self.assertEqual(hashlib.sha256(PNG.read_bytes()).hexdigest(), EXPECTED_SHA)
        self.assertEqual(PNG.stat().st_size, 894060)
        with Image.open(PNG) as image:
            self.assertEqual(image.mode, 'RGBA')
            self.assertEqual(image.size, (1536, 2560))
            self.assertEqual(hashlib.sha256(image.tobytes()).hexdigest(), 'a8adbc99f569e89c897408c3be8a62705bf18b76eafe747767e430ae9a143561')

    def test_all_twelve_original_cells_preserve_every_rgba_byte(self):
        old_path = ROOT / self.baseline['path'].removeprefix('res://')
        self.assertEqual(hashlib.sha256(old_path.read_bytes()).hexdigest(), self.baseline['sha256'])
        with Image.open(PNG) as new, Image.open(old_path) as old:
            for index in range(12):
                with self.subTest(index=index):
                    self.assertEqual(cell(new, index, 8), cell(old, index, 4))

    def test_sixty_four_corrected_moves_and_unreferenced_padding(self):
        with Image.open(PNG) as image:
            frames = [cell(image, index, 8) for index in range(12, 76)]
            self.assertEqual(len(set(frames)), 64)
            self.assertEqual([hashlib.sha256(frame).hexdigest() for frame in frames], self.registration['move_frame_rgba_sha256'])
            for index in range(76, 80):
                self.assertEqual(cell(image, index, 8), frames[-1])
        all_references = [frame for animation in self.entry['animations'].values() for frame in animation['frames']]
        self.assertTrue(all(0 <= frame < 76 for frame in all_references))

    def test_palette_and_binary_alpha(self):
        palette = {tuple(bytes.fromhex(color[1:])) for color in self.manifest['palette']}
        with Image.open(PNG) as image:
            pixels = set(image.get_flattened_data())
        self.assertEqual({p[3] for p in pixels}, {0, 255})
        self.assertTrue({p[:3] for p in pixels if p[3]} <= palette)

    def test_registration_matches_recovered_geometry_and_distance_contract(self):
        for field, value in {'path': 'res://assets/art/characters/armored_titan_v6_elbow.png', 'sha256': EXPECTED_SHA,
                             'width': 1536, 'height': 2560, 'cell_w': 192, 'cell_h': 256, 'columns': 8,
                             'anchor_px': [96, 256], 'defeatable': False}.items():
            self.assertEqual(self.entry[field], value, field)
        self.assertEqual(self.entry['animations']['move'], {'frames': list(range(12, 76)), 'fps': 64, 'loop': True})
        self.assertEqual(self.entry['gait']['cycle_distance_px'], 123.333333333333)
        self.assertEqual(self.entry['gait']['reference_fps'], 64)
        self.assertEqual(self.entry['gait']['frame_count'], 64)

    def test_nonmovement_animation_meanings_remain_unchanged(self):
        self.assertEqual(set(self.entry['animations']), set(self.baseline['animations']))
        for name, animation in self.baseline['animations'].items():
            if name != 'move':
                self.assertEqual(self.entry['animations'][name], animation, name)
        self.assertNotIn('death', self.entry['animations'])
        self.assertNotIn('run', self.entry['animations'])
        self.assertNotIn('charge', self.entry['animations'])

    def test_metadata_is_reconstructed_and_has_no_release_or_charge_claim(self):
        self.assertEqual(self.registration['metadata_identity'], 'new_reconstructed_registration_not_historical_manifest')
        self.assertFalse(self.registration['historical_manifest_recovered'])
        self.assertFalse(self.review['release_approval'])
        self.assertFalse(self.review['run_charge_art_complete'])
        self.assertFalse(self.review['run_charge_ai_complete'])
        self.assertEqual(self.registration['execution']['requested_reasoning_effort'], 'xhigh')
        self.assertEqual(self.registration['execution']['actual_model'], 'not_exposed_unverified')

    def test_only_armored_entry_can_change_in_proposed_and_live_manifests(self):
        protected = copy.deepcopy(self.manifest)
        protected['assets'].pop('armored_titan')
        # A later reviewed additive VFX batch must not invalidate the original
        # Armor-only baseline or authorize any unrelated asset edit.
        vfx = json.loads((ROOT / 'docs/art/vfx/primary-runtime-candidate.json').read_text())
        for asset_id, candidate in vfx['assets'].items():
            expected = copy.deepcopy(candidate)
            expected.update(vfx_approved=True, approval_status='DEVELOPMENT_RENDER_REVIEWED',
                            review_record='docs/validation/vfx/primary-five-native-review.md')
            self.assertEqual(protected['assets'].pop(asset_id), expected)
        # These ten originals are activated only for development rendering.
        # Exact descriptor equality plus explicit false review flags prevents
        # this additive exception from relaxing any native/final art boundary.
        development_vfx = {}
        for filename in ('evolution-runtime-candidate.json', 'fantasy-runtime-candidate.json'):
            source = json.loads((ROOT / 'docs/art/vfx' / filename).read_text())
            development_vfx.update(source['assets'])
        self.assertEqual(set(development_vfx), {'vfx_hit_spark', 'vfx_wing_first_arc', 'vfx_wing_second_arc', 'vfx_crossfire_ally_aim', 'vfx_crossfire_falling_shell', 'vfx_crossfire_contact_blast', 'vfx_chain_lightning', 'vfx_storm_chain', 'vfx_fire_zone', 'vfx_inferno_zone'})
        for asset_id, candidate in development_vfx.items():
            expected = copy.deepcopy(candidate)
            expected.update(development_render_enabled=True, native_reviewed=False,
                            final_art_approved=False, review_status='development_enabled_native_review_pending')
            self.assertIs(expected['vfx_approved'], False)
            self.assertEqual(protected['assets'].pop(asset_id), expected)
        # Exact reviewed enemy additions preserve every pre-existing Armor-only
        # baseline field; unknown additions still fail the original fingerprint.
        enemies = json.loads((ROOT / 'docs/art/enemies/development-runtime-candidate.json').read_text())
        self.assertEqual(set(enemies['assets']), {'titan_quadruped', 'titan_stone_thrower', 'enemy_stone_projectile'})
        for asset_id, candidate in enemies['assets'].items():
            self.assertEqual(protected['assets'].pop(asset_id), candidate)
        self.assertEqual(digest(protected), self.registration['protected_manifest_semantic_sha256'])
        proposed = copy.deepcopy(self.manifest)
        proposed['assets']['armored_titan'] = copy.deepcopy(self.entry)
        proposed['assets'].pop('armored_titan')
        for asset_id in vfx['assets']: proposed['assets'].pop(asset_id)
        for asset_id in development_vfx: proposed['assets'].pop(asset_id)
        for asset_id in enemies['assets']: proposed['assets'].pop(asset_id)
        self.assertEqual(proposed, protected)
        if self.review['runtime_integrated']:
            self.assertEqual(self.manifest['assets']['armored_titan'], self.entry)
        else:
            self.assertEqual(self.manifest['assets']['armored_titan'], self.baseline)

    def test_five_canon_blocks_and_final_export_gate_remain_closed(self):
        self.assertFalse(self.manifest['art_revision_status']['final_export_allowed'])
        self.assertEqual(set(self.manifest['art_revision_status']['blocked_character_ids']), BLOCKED)
        for asset_id in BLOCKED:
            self.assertTrue(self.manifest['assets'][asset_id]['export_blocked'], asset_id)
            self.assertEqual(self.manifest['assets'][asset_id]['review_status'], 'rejected_incorrect_clothing', asset_id)
            self.assertEqual(self.manifest['assets'][asset_id]['reason'], 'canon_revision_pending', asset_id)

    def test_runtime_registration_requires_actual_candidate_view_record(self):
        if self.review['runtime_integrated']:
            self.assertEqual(self.review['actual_candidate_view']['status'], 'reviewed_for_development_registration')
            self.assertEqual(self.review['actual_candidate_view']['asset_sha256'], EXPECTED_SHA)
            self.assertTrue(self.review['actual_candidate_view']['evidence'])
        else:
            self.assertEqual(self.review['actual_candidate_view']['status'], 'pending_parent_actual_view')
            self.assertFalse(self.review['actual_candidate_view']['evidence'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
