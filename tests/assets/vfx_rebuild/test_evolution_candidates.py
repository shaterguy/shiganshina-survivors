"""Original raster/pivot validation; this never approves a runtime asset."""
import hashlib
import json
import math
import unittest
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
IDS = ['vfx_hit_spark', 'vfx_wing_first_arc', 'vfx_wing_second_arc',
       'vfx_crossfire_ally_aim', 'vfx_crossfire_falling_shell', 'vfx_crossfire_contact_blast']

class EvolutionCandidates(unittest.TestCase):
    def test_exact_sources_palette_geometry_and_frames(self):
        doc = json.loads((ROOT / 'docs/art/vfx/evolution-runtime-candidate.json').read_text())
        palette = {tuple(bytes.fromhex(c[1:])) for c in json.loads((ROOT / 'assets/manifest.json').read_text())['palette']}
        for art_id in IDS:
            with self.subTest(art_id=art_id):
                record, audit = doc['assets'][art_id], doc['packing_audit'][art_id]
                self.assertIs(record['vfx_approved'], False)
                path = ROOT / record['path'].removeprefix('res://')
                source = ROOT / record['source_path']
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), record['sha256'])
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), record['source_sha256'])
                im, raw = Image.open(path).convert('RGBA'), Image.open(source).convert('RGBA')
                cw, ch = record['cell_w'], record['cell_h']
                self.assertEqual(im.size, (4*cw, 2*ch))
                self.assertEqual({p[3] for p in im.get_flattened_data()}, {0,255})
                self.assertTrue({p[:3] for p in im.get_flattened_data() if p[3]} <= palette)
                hashes = set()
                for index, frame_audit in enumerate(audit['frames']):
                    frame = im.crop((index%4*cw,index//4*ch,(index%4+1)*cw,(index//4+1)*ch))
                    hashes.add(hashlib.sha256(frame.tobytes()).hexdigest())
                    self.assertIsNotNone(frame.getchannel('A').getbbox())
                    for y in range(ch):
                        for x in range(cw):
                            if not frame.getpixel((x,y))[3]: continue
                            self.assertLessEqual(math.hypot(x-cw/2,y-ch/2),cw/2)
                            if 'wing_' in art_id:
                                self.assertLessEqual(abs(math.degrees(math.atan2(y-ch/2,x-cw/2))),55)
                    crop = raw.crop(tuple(frame_audit['source_crop']))
                    edge = list(crop.crop((0,0,crop.width,1)).get_flattened_data()) + list(crop.crop((0,crop.height-1,crop.width,crop.height)).get_flattened_data())
                    edge += list(crop.crop((0,0,1,crop.height)).get_flattened_data()) + list(crop.crop((crop.width-1,0,crop.width,crop.height)).get_flattened_data())
                    self.assertFalse(any(p[3]>=128 for p in edge), 'opaque source cannot cross an extraction boundary')
                self.assertEqual(len(hashes),8)
                self.assertEqual(audit['opaque_pixels_clipped'],0)
                self.assertEqual(audit['geometry_mask_pixels_removed'],0)

    def test_ultimate_curvatures_are_not_color_reskins(self):
        root = ROOT/'assets/art/effects/vfx_evolution_v1'
        a=Image.open(root/'vfx_wing_first_arc.png').convert('RGBA')
        b=Image.open(root/'vfx_wing_second_arc.png').convert('RGBA')
        self.assertNotEqual(a.getchannel('A').tobytes(), b.getchannel('A').tobytes())
        self.assertNotEqual(hashlib.sha256(a.tobytes()).hexdigest(),hashlib.sha256(b.tobytes()).hexdigest())

if __name__ == '__main__': unittest.main()
