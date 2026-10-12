"""Dedicated enemy PNGs enter development staging without opening nested sources."""
import copy,json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
import android_common as common
class EnemyArtPackaging(unittest.TestCase):
 def setUp(self):self.manifest=json.loads((ROOT/'assets/manifest.json').read_text())
 def test_exact_three_enemy_rasters_enter_runtime_packaging(self):
  for aid in ['titan_quadruped','titan_stone_thrower','enemy_stone_projectile']:
   self.assertTrue(common.is_runtime_asset(self.manifest['assets'][aid]),aid)
  staged=common.read_manifest(ROOT,development_validation=True)
  common.verify_source_hashes(ROOT,staged)
  self.assertFalse(staged['art_revision_status']['final_export_allowed'])
 def test_unreviewed_nested_variants_sources_and_wrong_kinds_stay_out(self):
  a=self.manifest['assets']['titan_quadruped']
  for field,value in [('enemy_art_development_ready',False),('enemy_art_development_ready',1),('export_blocked',True),('kind','effect'),('path','res://assets/art/characters/enemy_diversity_v1/titan_quadruped_00.png'),('path','res://assets/art/characters/enemy_diversity_v1/source/titan_quadruped.png'),('packing_profile','unreviewed')]:
   with self.subTest(field=field,value=value):
    record=copy.deepcopy(a);record[field]=value
    self.assertFalse(common.is_runtime_asset(record))
 def test_default_final_export_stays_denied(self):
  with self.assertRaisesRegex(common.BuildError,'art_review_pending'):common.read_manifest(ROOT)
if __name__=='__main__':unittest.main()
