"""Mechanical packing only. Does not draw, mask, trim silhouettes, or edit originals."""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / 'assets/art/effects/vfx_remaining_v1'
DOC = ROOT / 'docs/art/vfx/remaining-runtime-candidate.json'
SETTINGS = json.loads(Path(__file__).with_name('settings.json').read_text())
CONTRACT = json.loads((ROOT / 'docs/art/vfx/contract-snapshot.json').read_text())

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def magick(*args):
    subprocess.run(['magick', *map(str,args)], check=True, capture_output=True, text=True)

def pack(art_id, root=ROOT):
    art = root / ART.relative_to(ROOT)
    settings=SETTINGS[art_id]
    req=next(r for r in CONTRACT['art_requirements'] if r['art_id']==art_id)
    source=ART/'source'/f'{art_id}-generation-v1.png'
    source_image=Image.open(source).convert('RGBA')
    iw,ih=source_image.size
    xs=settings.get('x_cuts',[round(i*iw/4) for i in range(5)])
    ys=settings.get('y_cuts',[round(i*ih/2) for i in range(3)])
    cw,ch=req['cell_px']; anchor=req['pivot_px']; scale=settings['scale']
    frame_dir=art/f'{art_id}_frames'; frame_dir.mkdir(parents=True,exist_ok=True)
    audit={'source_sha256':digest(source),'source_dimensions':[iw,ih],'same_scale_all_frames':scale,
      'palette_sha256':digest(ROOT/'assets/art/palette.png'),'opaque_pixels_clipped':0,
      'geometry_mask_pixels_removed':0,'transparent_grid_boundaries_after_alpha_threshold':True,
      'operations':['lossless source archive','non-overlapping transparent-gap cell extraction','hard alpha threshold 50 percent','uniform-scale nearest-neighbor resize','explicit integer pivot registration','24-color nearest palette remap','row-major 4x2 atlas'],
      'resampling_note':'Nearest downsampling changes source pixel count; clipping zero is boundary retention, not one-to-one high-resolution pixel retention. Alpha below 128 is explicitly discarded and counted. No silhouettes are removed.', 'frames':[]}
    frames=[]
    with tempfile.TemporaryDirectory(prefix='remaining-vfx-pack-') as directory:
        work=Path(directory)
        for index in range(8):
            col,row=index%4,index//4
            left,right,top,bottom=xs[col],xs[col+1],ys[row],ys[row+1]
            crop=source_image.crop((left,top,right,bottom)); alpha_values=list(crop.getchannel('A').get_flattened_data())
            a=crop.getchannel('A'); edge=list(a.crop((0,0,a.width,1)).get_flattened_data())+list(a.crop((0,a.height-1,a.width,a.height)).get_flattened_data())+list(a.crop((0,0,1,a.height)).get_flattened_data())+list(a.crop((a.width-1,0,a.width,a.height)).get_flattened_data())
            if any(v>=128 for v in edge): raise ValueError(f'{art_id}/{index}: source cell boundary intersects opaque pixels')
            raw,alpha,mapped=work/'raw.png',work/'alpha.png',work/'mapped.png'
            magick(source,'-crop',f'{right-left}x{bottom-top}+{left}+{top}','+repage','-channel','A','-threshold','50%','+channel','-filter','point','-resize',f'{scale*100:.6f}%','-define','png:color-type=6','-define','png:exclude-chunks=date,time',raw)
            resized=Image.open(raw).convert('RGBA')
            pivot=settings['frame_pivots'][index]
            offset=[anchor[0]-round(pivot[0]*scale),anchor[1]-round(pivot[1]*scale)]
            pixels=[(x,y) for y in range(resized.height) for x in range(resized.width) if resized.getpixel((x,y))[3]==255]
            clipped=sum(not(0<=x+offset[0]<cw and 0<=y+offset[1]<ch) for x,y in pixels)
            if clipped: raise ValueError(f'{art_id}/{index}: canvas would clip {clipped} opaque pixels')
            magick(raw,'-alpha','extract',alpha)
            magick(raw,'-alpha','off','-dither','None','-remap',ROOT/'assets/art/palette.png',alpha,'-alpha','off','-compose','CopyOpacity','-composite','-define','png:color-type=6',mapped)
            frame=frame_dir/f'{index:02}.png'
            magick('-size',f'{cw}x{ch}','xc:none',mapped,'-geometry',f'{offset[0]:+d}{offset[1]:+d}','-compose','Over','-composite','-define','png:color-type=6','-define','png:exclude-chunks=date,time',frame)
            final=Image.open(frame).convert('RGBA'); count=sum(p[3]==255 for p in final.get_flattened_data())
            if not count: raise ValueError(f'{art_id}/{index}: blank packed frame')
            audit['frames'].append({'frame':index,'source_crop':[left,top,right,bottom], 'source_local_pivot':pivot,'source_grid_edge_max_alpha':max(edge),'source_grid_edge_subthreshold_count':sum(v>0 for v in edge),'integer_translation_px':offset,'opaque_pixels_clipped':clipped,'source_nonzero_alpha_pixels':sum(v>0 for v in alpha_values),'alpha_threshold_pixels_discarded':sum(0<v<128 for v in alpha_values),'source_hard_alpha_pixels':sum(v>=128 for v in alpha_values),'packed_opaque_pixel_count':count,'opaque_bbox_px':final.getchannel('A').getbbox(),'sha256':digest(frame)})
            frames.append(frame)
    target=art/f'{art_id}.png'
    magick('montage',*frames,'-tile','4x2','-geometry',f'{cw}x{ch}+0+0','-background','none','-define','png:color-type=6','-define','png:exclude-chunks=date,time',target)
    previews=art/'previews'; previews.mkdir(exist_ok=True)
    for factor in [1,4]:
        magick(target,'-background','#30343b','-alpha','remove','-filter','point','-resize',f'{factor*100}%','-define','png:exclude-chunks=date,time',previews/f'{art_id}-nearest-{factor}x.png')
    meta={'path':'res://'+str(target.relative_to(root)),'kind':'effect','source_status':'NEW','native_reviewed':False,'final_art_approved':False,'vfx_approved':False,
      'source_method':'Original built-in imagegen raster; only transparent cell extraction, binary alpha, uniform nearest resize, explicit integer pivot, palette24 remap and atlas packing. No vector, code-drawn art, silhouette masks, or third-party art.',
      'width':cw*4,'height':ch*2,'cell_w':cw,'cell_h':ch,'columns':4,'anchor_px':anchor,'vfx_bounds_px':req['contact_bounds_px'],'contact_frame':0,'forward_axis':'+X','animations':{'attack':{'frames':list(range(8)),'fps':24,'loop':False}},
      'sha256':digest(target),'source_path':str(source.relative_to(ROOT)),'source_sha256':digest(source),'preview_path':str((previews/f'{art_id}-nearest-4x.png').relative_to(root)), 'notes':req['notes'],'approval_status':'CANDIDATE_PENDING_ACTUAL_RENDER_REVIEW'}
    return meta,audit

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('ids',nargs='+',choices=list(SETTINGS)); parser.add_argument('--output-root',type=Path,default=ROOT); args=parser.parse_args()
    doc=args.output_root/DOC.relative_to(ROOT); doc.parent.mkdir(parents=True,exist_ok=True)
    descriptor=json.loads(doc.read_text()) if doc.exists() else {'schema_version':1,'candidate_group':'vfx_remaining_v1','source_status':'NEW','native_reviewed':False,'final_art_approved':False,'vfx_approved':False,'filter':'nearest','mipmaps':False,'frame_order':'row_major_zero_based','assets':{},'packing_audit':{}}
    for art_id in args.ids:
        meta,audit=pack(art_id,args.output_root); descriptor['assets'][art_id]=meta; descriptor['packing_audit'][art_id]=audit
        print(f"PACKED {art_id}: {meta['width']}x{meta['height']} {meta['sha256']}")
    doc.write_text(json.dumps(descriptor,indent=2)+'\n')
