"""Focused source/packing/contract verification; no game runtime or product writes."""
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from PIL import Image, __version__ as pillow_version

ROOT=Path(__file__).resolve().parents[3]
DOC=ROOT/'docs/art/vfx/remaining-runtime-candidate.json'
ART=ROOT/'assets/art/effects/vfx_remaining_v1'

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    descriptor=json.loads(DOC.read_text()); contract=json.loads((ROOT/'docs/art/vfx/contract-snapshot.json').read_text()); assets=descriptor['assets']
    required={r['art_id']:r for r in contract['art_requirements']}
    assert set(assets)==set(required)
    palette=set(Image.open(ROOT/'assets/art/palette.png').convert('RGB').get_flattened_data())
    checks=[]
    with tempfile.TemporaryDirectory(prefix='reproduce-',dir=ROOT.parent) as tmp:
        result=subprocess.run([sys.executable,str(Path(__file__).with_name('pack_remaining.py')),*sorted(assets),'--output-root',tmp],check=True,capture_output=True,text=True)
        reproduction_root=Path(tmp)
        for key,meta in sorted(assets.items()):
            req=required[key]; path=ROOT/meta['path'].removeprefix('res://'); im=Image.open(path).convert('RGBA')
            assert im.size==(req['cell_px'][0]*4,req['cell_px'][1]*2)
            assert [meta['cell_w'],meta['cell_h']]==req['cell_px']
            assert meta['anchor_px']==req['pivot_px'] and meta['vfx_bounds_px']==req['contact_bounds_px']
            assert meta['contact_frame']==req['contact_frame'] and meta['forward_axis']==req['forward_axis']
            assert meta['columns']==4 and meta['animations']['attack']['frames']==list(range(8))
            for flag in ['native_reviewed','final_art_approved','vfx_approved']: assert meta[flag] is False and descriptor[flag] is False
            colors={p[:3] for p in im.get_flattened_data() if p[3]}; alphas={p[3] for p in im.get_flattened_data()}
            assert colors<=palette and alphas=={0,255}
            assert digest(path)==meta['sha256'] and digest(ROOT/meta['source_path'])==meta['source_sha256']
            regenerated=reproduction_root/path.relative_to(ROOT); assert regenerated.read_bytes()==path.read_bytes()
            audit=descriptor['packing_audit'][key]; assert audit['opaque_pixels_clipped']==0 and audit['geometry_mask_pixels_removed']==0
            frame_hashes=[]
            for frame in range(8):
                original=ART/f'{key}_frames/{frame:02}.png'; repacked=reproduction_root/original.relative_to(ROOT)
                assert original.read_bytes()==repacked.read_bytes(); assert digest(original)==audit['frames'][frame]['sha256']
                fim=Image.open(original).convert('RGBA'); assert fim.getchannel('A').getbbox()
                atlas_frame=im.crop(((frame%4)*meta['cell_w'],(frame//4)*meta['cell_h'],(frame%4+1)*meta['cell_w'],(frame//4+1)*meta['cell_h']))
                assert fim.tobytes()==atlas_frame.tobytes(); frame_hashes.append(digest(original))
            assert len(set(frame_hashes))==8
            checks.append({'art_id':key,'atlas_sha256':digest(path),'source_sha256':meta['source_sha256'],'visible_palette_colors':len(colors),'alpha_values':sorted(alphas),'nonblank_unique_frames':8,'bounds_and_pivot_contract':'PASS','source_sha':'PASS','atlas_and_all_frames_reproduce_byte_identically':'PASS','opaque_clipping_pixels':0,'geometry_mask_pixels_removed':0})
    report={'status':'PASS','scope':'Five isolated candidate rasters only; no runtime, native render or final-art approval','checks':checks,'python':sys.version.split()[0],'pillow':pillow_version,'imagemagick':subprocess.check_output(['magick','-version'],text=True).splitlines()[0],'packer_sha256':digest(Path(__file__).with_name('pack_remaining.py')),'settings_sha256':digest(Path(__file__).with_name('settings.json')),'contract_sha256':digest(ROOT/'docs/art/vfx/contract-snapshot.json')}
    (ROOT/'docs/art/vfx/focused-verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__': main()
