"""Raw licensed audio and exact engine imports must both survive packaging."""
import hashlib,json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
import android_common as common
import test_android_tooling as fixtures

class AudioRuntimePaths(unittest.TestCase):
 def test_flat_wav_and_ogg_only(self):
  for ext in ('wav','ogg'):
   self.assertTrue(common.is_runtime_asset({'kind':'audio','path':'res://assets/audio/combat_loop.'+ext}))
  for path in ('res://assets/audio/source/combat.ogg','res://assets/audio/../combat.ogg','res://assets/audio/combat.mp3','res://assets/audio/combat.ogg.exe'):
   self.assertFalse(common.is_runtime_asset({'kind':'audio','path':path}))

class AudioArchive(unittest.TestCase):
 def setUp(self):
  self.fixture=fixtures.ArchiveAndWrapperTests(methodName='test_archive_accepts_minimal_whitelist')
  self.fixture.setUp();self.addCleanup(self.fixture.doCleanups)
 def add_audio(self,extension,import_suffix):
  f=self.fixture;self.path='res://assets/audio/test.'+extension;self.member='assets/'+self.path[6:]
  payload=b'exact-licensed-audio-'+extension.encode();self.sha=hashlib.sha256(payload).hexdigest()
  f.manifest['assets']['test_audio']={'path':self.path,'kind':'audio','sha256':self.sha}
  raw=json.dumps(f.manifest).encode();(f.root/'assets/manifest.json').write_bytes(raw);f.entries['assets/assets/manifest.json']=raw
  self.imported='.godot/imported/test.'+extension+'-'+hashlib.md5(self.path.encode()).hexdigest()+import_suffix
  f.entries[self.member]=payload;f.entries[self.member+'.import']=('path="res://'+self.imported+'"').encode()
  f.entries['assets/'+self.imported]=b'engine-imported-audio'
 def test_wav_raw_is_required_even_with_sample_import(self):
  self.add_audio('wav','.sample');del self.fixture.entries[self.member]
  with self.assertRaisesRegex(common.BuildError,'audio original'):self.fixture.check()
 def test_wav_raw_sha_is_checked_with_sample_import(self):
  self.add_audio('wav','.sample');self.fixture.entries[self.member]=b'changed-recording'
  with self.assertRaisesRegex(common.BuildError,'audio original'):self.fixture.check()
 def test_wav_exact_raw_and_import_are_accepted(self):
  self.add_audio('wav','.sample');self.fixture.check()
 def test_ogg_exact_raw_and_observed_import_are_accepted(self):
  self.add_audio('ogg','.oggvorbisstr');self.fixture.check()
 def test_ogg_raw_is_required_even_with_import(self):
  self.add_audio('ogg','.oggvorbisstr');del self.fixture.entries[self.member]
  with self.assertRaisesRegex(common.BuildError,'audio original'):self.fixture.check()
 def test_ogg_raw_sha_is_checked_even_with_import(self):
  self.add_audio('ogg','.oggvorbisstr');self.fixture.entries[self.member]=b'changed-score'
  with self.assertRaisesRegex(common.BuildError,'audio original'):self.fixture.check()
 def test_audio_rejects_wrong_import_suffix(self):
  for ext,suffix in [('ogg','.sample'),('ogg','.ctex'),('ogg','.ogg'),('wav','.oggvorbisstr')]:
   with self.subTest(extension=ext,suffix=suffix):
    self.setUp();self.add_audio(ext,suffix)
    with self.assertRaisesRegex(common.BuildError,'unexpected imported'):self.fixture.check()


if __name__=='__main__':unittest.main()
