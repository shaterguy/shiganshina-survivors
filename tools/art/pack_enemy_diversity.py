"""Normalize supplied original atlases; no drawing, anatomy edits or new frames."""
from pathlib import Path
import argparse,hashlib,json
from PIL import Image

def normalize(source, palette):
    """Preserve every alpha>=128 source pixel; nearest RGB palette, no dither."""
    mapped=[]
    cache={}
    for r,g,b,a in source.convert('RGBA').get_flattened_data():
        if a<128:
            mapped.append((0,0,0,0));continue
        rgb=(r,g,b)
        if rgb not in cache:
            cache[rgb]=min(palette,key=lambda p:sum((v-w)**2 for v,w in zip(rgb,p)))
        mapped.append((*cache[rgb],255))
    result=Image.new('RGBA',source.size);result.putdata(mapped)
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--art-root',type=Path,required=True)
    p.add_argument('--palette-manifest',type=Path,required=True)
    p.add_argument('--output-root',type=Path,required=True)
    args=p.parse_args()
    palette=[tuple(bytes.fromhex(c[1:])) for c in json.loads(args.palette_manifest.read_text())['palette']]
    fragment=json.loads((args.art_root/'proposed-manifest-fragment.json').read_text())
    audit=[]
    for aid,record in fragment['assets'].items():
        src=args.art_root/record['path'][6:]
        source_hash=hashlib.sha256(src.read_bytes()).hexdigest()
        assert source_hash==record['sha256'],f'changed input: {aid}'
        source=Image.open(src).convert('RGBA')
        selected_palette=[c for c in palette if c!=(32,37,44)] if aid=='titan_stone_thrower' else palette
        result=normalize(source,selected_palette)
        out=args.output_root/record['path'][6:];out.parent.mkdir(parents=True,exist_ok=True);result.save(out)
        record['sha256']=hashlib.sha256(out.read_bytes()).hexdigest()
        record['source_atlas_sha256']=source_hash
        record['packing_profile']='nearest_palette_alpha128_exclude_20252c' if aid=='titan_stone_thrower' else 'nearest_palette_alpha128'
        record['palette_excluded_hex']=['#20252c'] if aid=='titan_stone_thrower' else []
        record['source_method']+=' Deterministic alpha>=128 hard-mask and nearest shared-palette RGB mapping; no dithering or new poses. Thrower excludes only #20252c for dark-tile contrast.'
        record['review_status']='DEVELOPMENT_MECHANICAL_CANDIDATE_NATIVE_UNVERIFIED'
        record['reason']='native_gameplay_visual_review_unverified; final export remains blocked'
        record['export_blocked']=True
        record['enemy_art_development_ready']=False
        if aid=='enemy_stone_projectile':record['kind']='projectile'
        else:record['ordinary_two_frame']=True
        audit.append({'asset_id':aid,'input_path':str(src),'input_sha256':source_hash,'output_path':str(out),'output_sha256':record['sha256'],'size':list(result.size),'solid_pixels':sum(c[3]>=128 for c in source.get_flattened_data()),'output_opaque_pixels':sum(c[3]==255 for c in result.get_flattened_data()),'alpha_threshold':128,'nearest_distance':'squared_sRGB','dither':False,'palette_excluded_hex':record['palette_excluded_hex']})
    fragment['integration_status']='DEVELOPMENT_CANDIDATE_NATIVE_UNVERIFIED'
    (args.output_root/'normalized-manifest-fragment.json').write_text(json.dumps(fragment,indent=2)+'\n')
    (args.output_root/'packing-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
    print(json.dumps(audit,indent=2))
if __name__=='__main__':main()
