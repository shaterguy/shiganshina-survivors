"""Approved raster bytes must survive both packaging layers, not just .ctex."""
import hashlib,json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
import android_common as common
from test_android_tooling import ArchiveAndWrapperTests
class RegisteredPrimaryPackaging(unittest.TestCase):
 def test_current_development_manifest_stages_exact_approved_pngs(self):
  manifest=common.read_manifest(ROOT,development_validation=True)
  with tempfile.TemporaryDirectory() as tmp:
   target=Path(tmp)/'staged';common.stage_project(ROOT,target,manifest)
   common.verify_source_hashes(target,manifest)
   for key,record in manifest['assets'].items():
    if key.startswith('vfx_'):
     self.assertIs(record['vfx_approved'],True)
     self.assertEqual((target/record['path'][6:]).read_bytes(),(ROOT/record['path'][6:]).read_bytes())
   self.assertFalse(any('/source/' in p.as_posix() or '/previews/' in p.as_posix() for p in target.rglob('*')))
 def test_unreviewed_nested_effects_stay_out(self):
  self.assertTrue(hasattr(common,'is_runtime_asset'))
  good={'kind':'effect','vfx_approved':True,'path':'res://assets/art/effects/vfx_rebuild_v1/vfx_cannon_shell.png'}
  self.assertTrue(common.is_runtime_asset(good))
  for field,value in [('vfx_approved',False),('vfx_approved','true'),('vfx_approved',1),('kind','sprite'),('path','res://assets/art/effects/vfx_rebuild_v1/source/a.png'),('path','res://assets/art/effects/vfx_rebuild_v1/../vfx_a.png')]:
   record=dict(good);record[field]=value
   self.assertFalse(common.is_runtime_asset(record))
class RawPrimaryArchive(ArchiveAndWrapperTests):
 def setUp(self):
  super().setUp()
  self.vfx_path='res://assets/art/effects/vfx_rebuild_v1/vfx_cannon_shell.png'
  self.raw_member='assets/'+self.vfx_path[6:]
  self.manifest['assets']['vfx_cannon_shell']={'path':self.vfx_path,'kind':'effect','vfx_approved':True,'sha256':hashlib.sha256(b'exact-vfx-raster').hexdigest()}
  raw=json.dumps(self.manifest).encode();(self.root/'assets/manifest.json').write_bytes(raw);self.entries['assets/assets/manifest.json']=raw
  self.entries[self.raw_member]=b'exact-vfx-raster'
  imported='.godot/imported/vfx_cannon_shell.png-'+hashlib.md5(self.vfx_path.encode()).hexdigest()+'.ctex'
  self.entries[self.raw_member+'.import']=('path="res://'+imported+'"').encode()
  self.entries['assets/'+imported]=b'imported-texture-not-original-png'
 def test_approved_vfx_import_cannot_replace_required_raw_png(self):
  del self.entries[self.raw_member]
  with self.assertRaisesRegex(common.BuildError,'VFX original raster'): self.check()
 def test_approved_vfx_raw_bytes_checked_even_when_import_exists(self):
  self.entries[self.raw_member]=b'wrong-raster'
  with self.assertRaisesRegex(common.BuildError,'VFX original raster'): self.check()
