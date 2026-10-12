"""Validate original fantasy rasters without granting visual approval."""
import hashlib
import importlib.util
import json
import math
import shutil
import tempfile
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
DOC = ROOT / 'docs/art/vfx/fantasy-runtime-candidate.json'

class FantasyCandidates(unittest.TestCase):
    def test_exact_pixels_sources_and_geometry(self):
        doc = json.loads(DOC.read_text())
        palette = {tuple(bytes.fromhex(c[1:])) for c in json.loads((ROOT/'assets/manifest.json').read_text())['palette']}
        for ident, record in doc['assets'].items():
            with self.subTest(ident=ident):
                self.assertIs(record['vfx_approved'], False)
                path = ROOT/record['path'].removeprefix('res://')
                source = ROOT/record['source_path']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),record['sha256'])
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(),record['source_sha256'])
                im = Image.open(path).convert('RGBA'); raw = Image.open(source).convert('RGBA')
                cw,ch = record['cell_w'],record['cell_h']; bx,by,bw,bh = record['vfx_bounds_px']
                self.assertEqual(im.size,(cw*4,ch*2))
                self.assertEqual(set(im.getchannel('A').getdata()),{0,255})
                self.assertTrue({p[:3] for p in im.getdata() if p[3]} <= palette)
                hashes=set()
                for n, audit in enumerate(doc['packing_audit'][ident]['frames']):
                    f=im.crop((n%4*cw,n//4*ch,(n%4+1)*cw,(n//4+1)*ch)); hashes.add(hashlib.sha256(f.tobytes()).hexdigest())
                    for y in range(ch):
                        for x in range(cw):
                            if not f.getpixel((x,y))[3]: continue
                            self.assertTrue(bx<=x<bx+bw and by<=y<by+bh)
                            if 'zone' in ident: self.assertLessEqual(math.hypot(x-64,y-64),64)
                    crop=raw.crop(audit['source_crop']); a=crop.getchannel('A')
                    edges=[a.crop((0,0,a.width,1)),a.crop((0,a.height-1,a.width,a.height)),a.crop((0,0,1,a.height)),a.crop((a.width-1,0,a.width,a.height))]
                    self.assertFalse(any(max(e.getdata())>=128 for e in edges),'source extraction must not cut visible art')
                self.assertEqual(len(hashes),8)
                self.assertEqual(doc['packing_audit'][ident]['opaque_pixels_clipped'],0)
                self.assertEqual(doc['packing_audit'][ident]['geometry_mask_pixels_removed'],0)

    def test_ultimate_changes_silhouette(self):
        doc=json.loads(DOC.read_text())
        for a,b in [('vfx_chain_lightning','vfx_storm_chain'),('vfx_fire_zone','vfx_inferno_zone')]:
            ia=Image.open(ROOT/doc['assets'][a]['path'].removeprefix('res://')).convert('RGBA')
            ib=Image.open(ROOT/doc['assets'][b]['path'].removeprefix('res://')).convert('RGBA')
            self.assertNotEqual(ia.getchannel('A').tobytes(),ib.getchannel('A').tobytes())

    def test_repacking_matches_exact_pixels(self):
        spec=importlib.util.spec_from_file_location('pack_fantasy',ROOT/'tools/art/vfx_evolution/pack_fantasy.py')
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory(prefix='fantasy-pixel-replay-') as tmp:
            target=Path(tmp);art=target/'assets/art/effects/vfx_fantasy_v1'
            shutil.copytree(ROOT/'assets/art/effects/vfx_fantasy_v1/source',art/'source')
            (art/'previews').mkdir();shutil.copyfile(ROOT/'assets/art/palette.png',target/'assets/art/palette.png')
            module.ROOT=target; module.ART=art
            for ident in module.SETTINGS:
                record,audit=module.pack(ident)
                actual=Image.open(target/record['path'].removeprefix('res://')).convert('RGBA')
                original=Image.open(ROOT/record['path'].removeprefix('res://')).convert('RGBA')
                self.assertEqual(actual.tobytes(),original.tobytes(),ident)
                self.assertEqual(audit['opaque_pixels_clipped'],0)

if __name__=='__main__': unittest.main()
