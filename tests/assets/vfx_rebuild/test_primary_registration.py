"""Development registration of exactly five reviewed primary effects."""
import copy, hashlib, json, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
IDS={'vfx_blade_crescent','vfx_spin_double_ring','vfx_cannon_shell','vfx_cannon_contact_blast','vfx_cannon_dust_ring'}
class Registration(unittest.TestCase):
 def test_exact_five_new_entries_and_no_other_changes(self):
  base=json.loads((ROOT/'docs/art/vfx/pre-primary-registration-manifest.json').read_text())
  actual=json.loads((ROOT/'assets/manifest.json').read_text())
  self.assertEqual(set(actual['assets'])-set(base['assets']),IDS)
  stripped=copy.deepcopy(actual)
  for key in IDS: stripped['assets'].pop(key,None)
  self.assertEqual(stripped,base)
 def test_approved_entries_equal_frozen_candidates_except_review_fields(self):
  actual=json.loads((ROOT/'assets/manifest.json').read_text())
  candidate=json.loads((ROOT/'docs/art/vfx/primary-runtime-candidate.json').read_text())
  for key in IDS:
   with self.subTest(key=key):
    self.assertIn(key,actual['assets'])
    record=copy.deepcopy(actual['assets'][key])
    self.assertIs(record['vfx_approved'],True)
    self.assertEqual(record['approval_status'],'DEVELOPMENT_RENDER_REVIEWED')
    self.assertEqual(record.pop('review_record'),'docs/validation/vfx/primary-five-native-review.md')
    record['vfx_approved']=False
    record['approval_status']='CANDIDATE_PENDING_ACTUAL_RENDER_REVIEW'
    self.assertEqual(record,candidate['assets'][key])
    self.assertEqual(hashlib.sha256((ROOT/record['path'].removeprefix('res://')).read_bytes()).hexdigest(),record['sha256'])
 def test_previous_manifest_is_exact_registration_baseline(self):
  self.assertEqual(hashlib.sha256((ROOT/'docs/art/vfx/pre-primary-registration-manifest.json').read_bytes()).hexdigest(),'ed61d573f0dabb32688818f36d3107f594ba17af5b08899328d00205dd9b7581')
if __name__=='__main__': unittest.main()
