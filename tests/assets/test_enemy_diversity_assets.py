"""Catch missing/misregistered two-frame art, unsafe approval and packing drift."""
from pathlib import Path
import configparser,hashlib,importlib.util,json,subprocess,sys,unittest
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
SPECS={
 'titan_quadruped':((720,96),(144,96),(64,88),'b6833aeb3ba0e51dc0b1a87f590a06e085ddc6b18e3d5cd8dbfd14fac347a384'),
 'titan_stone_thrower':((960,176),(192,176),(72,168),'09dae345f7ed744bb3409eb789e86fd4551736649f038a2435b8d37702478fe2'),
 'enemy_stone_projectile':((16,16),(16,16),(8,8),'35e352ef7bb5fde1039e3ceeeccd93ab3ef7e422e4c85a277638ac44851f0813'),
}
class EnemyDiversityAssets(unittest.TestCase):
 def test_packing_preserves_solid_mask_and_uses_nearest_palette_without_dither(self):
  script=ROOT/'tools/art/pack_enemy_diversity.py';self.assertTrue(script.is_file(),'mechanical normalizer must be reproducible')
  spec=importlib.util.spec_from_file_location('enemy_pack',script);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  source=Image.new('RGBA',(4,1));source.putdata([(33,38,45,127),(33,38,45,128),(244,200,118,252),(36,37,44,255)])
  before=source.tobytes();result=module.normalize(source,[(32,37,44),(245,203,118)])
  self.assertEqual(list(result.get_flattened_data()),[(0,0,0,0),(32,37,44,255),(245,203,118,255),(32,37,44,255)])
  self.assertEqual(source.tobytes(),before,'source pixels remain untouched')
 def test_authored_art_is_loadable_and_obeys_two_pose_dot_contract(self):
  m=json.loads((ROOT/'assets/manifest.json').read_text());palette={tuple(bytes.fromhex(c[1:])) for c in m['palette']}
  for aid,(size,cell,anchor,source_hash) in SPECS.items():
   with self.subTest(asset=aid):
    self.assertTrue(aid in m['assets'],'authored enemy must be registered rather than invisible/fallback: '+aid)
    if aid not in m['assets']:continue
    a=m['assets'][aid];p=ROOT/a['path'][6:];self.assertTrue(p.is_file());self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),a['sha256'])
    im=Image.open(p);self.assertEqual(im.mode,'RGBA');self.assertEqual(im.size,size)
    settings=configparser.ConfigParser();settings.read_string('[params]'+Path(str(p)+'.import').read_text().split('[params]',1)[1]);self.assertEqual(settings['params']['compress/mode'],'0');self.assertEqual(settings['params']['mipmaps/generate'],'false');self.assertEqual(settings['params']['process/fix_alpha_border'],'false')
    self.assertEqual((a['cell_w'],a['cell_h']),cell);self.assertEqual(tuple(a['anchor_px']),anchor)
    self.assertEqual(a['source_atlas_sha256'],source_hash);self.assertEqual(a['packing_profile'],'nearest_palette_alpha128_exclude_20252c' if aid=='titan_stone_thrower' else 'nearest_palette_alpha128');self.assertFalse(a['export_blocked'])
    px=list(im.get_flattened_data());self.assertTrue({c[3] for c in px}<={0,255});self.assertTrue({c[:3] for c in px if c[3]}<=palette)
    for index in range(size[0]//cell[0]):
     frame=im.crop((index*cell[0],0,(index+1)*cell[0],cell[1]));alpha=frame.getchannel('A');box=alpha.getbbox();self.assertIsNotNone(box)
     self.assertGreater(box[0],0);self.assertGreater(box[1],0);self.assertLess(box[2],cell[0]);self.assertLess(box[3],cell[1])
    if aid!='enemy_stone_projectile':
     self.assertEqual(a['animations']['move'],{'frames':[0,1],'fps':6,'loop':True})
     self.assertNotEqual(im.crop((0,0,cell[0],cell[1])).tobytes(),im.crop((cell[0],0,2*cell[0],cell[1])).tobytes())
     self.assertEqual(a['animations']['windup']['frames'],[2]);self.assertEqual(a['animations']['attack']['frames'],[3])
     for name in ['idle','recover','hit','death']:self.assertEqual(a['animations'][name]['frames'],[4])
 def test_final_export_and_existing_rejected_bodies_stay_blocked(self):
  m=json.loads((ROOT/'assets/manifest.json').read_text())
  self.assertFalse(m['art_revision_status']['final_export_allowed'])
  self.assertEqual({k for k,v in m['assets'].items() if v.get('export_blocked')},{'titan_runner','titan_sweeper','boss_charger','boss_leaper','boss_abnormal'})
 def test_official_asset_validator_accepts_the_real_registered_assets(self):
  r=subprocess.run([sys.executable,str(ROOT/'tools/art/validate_assets.py')],capture_output=True,text=True)
  self.assertEqual(r.returncode,0,r.stdout+r.stderr)
if __name__=='__main__':unittest.main()
