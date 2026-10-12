"""Exact five remaining rasters preserve the existing fail-closed export boundary."""
import copy,json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
import android_common as common
IDS={'vfx_dash_compressed_gas','vfx_dash_cross_tip','vfx_reentry_triple','vfx_ally_gas_swoop','vfx_ally_arrival_cut'}
class RemainingPackaging(unittest.TestCase):
 def test_exact_five_registered_originals_stage_without_source_art(self):
  live=json.loads((ROOT/'assets/manifest.json').read_text())
  self.assertTrue(IDS <= live['assets'].keys(),'five remaining VFX not registered')
  for aid in IDS:
   record=live['assets'][aid];self.assertTrue(common.is_runtime_asset(record),aid)
   for field in ['vfx_approved','native_reviewed','final_art_approved']:self.assertIs(record[field],False)
   for field,value in [('development_render_enabled',False),('development_render_enabled','true'),('native_reviewed',True),('vfx_approved','true'),('final_art_approved',True),('path','res://assets/art/effects/vfx_remaining_v1/vfx_unrequested.png'),('path',record['path'].replace('/vfx_remaining_v1/','/vfx_remaining_v1/source/'))]:
    changed=copy.deepcopy(record);changed[field]=value;self.assertFalse(common.is_runtime_asset(changed),(aid,field,value))
  manifest=common.read_manifest(ROOT,development_validation=True)
  with tempfile.TemporaryDirectory() as tmp:
   dest=Path(tmp)/'stage';common.stage_project(ROOT,dest,manifest);common.verify_source_hashes(dest,manifest)
   actual={p.name for p in (dest/'assets/art/effects/vfx_remaining_v1').rglob('*') if p.is_file()}
   self.assertEqual(actual,{aid+'.png' for aid in IDS})
   for aid in IDS:self.assertEqual((dest/live['assets'][aid]['path'][6:]).read_bytes(),(ROOT/live['assets'][aid]['path'][6:]).read_bytes())
 def test_final_export_remains_denied(self):
  with self.assertRaisesRegex(common.BuildError,'art_review_pending'):common.read_manifest(ROOT)
if __name__=='__main__':unittest.main()
