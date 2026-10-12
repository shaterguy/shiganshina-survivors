"""Mechanically packs original generated raster art. ImageMagick does crop/nearest/palette/alpha operations."""
import json, pathlib, subprocess, tempfile, hashlib, re, os, shutil
ROOT=pathlib.Path(__file__).resolve().parents[2]
PALETTE=ROOT/'assets/art/palette.png'
M=ROOT/'assets/manifest.json'
def run(*args):
    return subprocess.run(['magick',*map(str,args)],check=True,capture_output=True,text=True).stdout

def pack_character(asset_id, source, cell=(96,144), source_cols=4, source_rows=3):
    outdir=ROOT/'assets/art/characters'; (outdir/f'{asset_id}_frames').mkdir(parents=True,exist_ok=True)
    source=pathlib.Path(source)
    archived=ROOT/f'assets/art/source/{asset_id}-generation.png'
    if source.resolve()!=archived.resolve(): shutil.copyfile(source,archived)
    iw,ih=map(int,run('identify','-format','%w %h',source).split())
    cw,ch=cell
    with tempfile.TemporaryDirectory(prefix='survivor-art-') as work:
        w=pathlib.Path(work);os.environ['XDG_CACHE_HOME']=str(w/'cache')
        scale=None
        for index in range(source_cols*source_rows):
            sx0=round(index%source_cols*iw/source_cols);sx1=round((index%source_cols+1)*iw/source_cols)
            sy0=round(index//source_cols*ih/source_rows);sy1=round((index//source_cols+1)*ih/source_rows)
            raw=w/f'{index}-raw.png';alpha=w/f'{index}-alpha.png';clean=w/f'{index}-clean.png'
            run(source,'-crop',f'{sx1-sx0}x{sy1-sy0}+{sx0}+{sy0}','+repage','-channel','A','-threshold','55%','+channel',raw)
            run(raw,'-alpha','extract',alpha)
            records=run(alpha,'-define','connected-components:verbose=true','-connected-components','8','null:')
            match=re.search(r'^\s*(\d+):.*(?:gray\(255\)|srgb\(255,255,255\))',records,re.M)
            if not match: raise RuntimeError(f'{asset_id}/{index}: no opaque component')
            run(alpha,'-define','connected-components:mean-color=true','-define',f'connected-components:keep={match[1]}','-connected-components','8',clean)
            run(raw,'-alpha','off',clean,'-alpha','off','-compose','CopyOpacity','-composite','-trim','+repage',raw)
            if scale is None:
                bw,bh=map(int,run('identify','-format','%w %h',raw).split()); scale=min((cw-12)/bw,(ch-16)/bh)*100
            run(raw,'-filter','point','-resize',f'{scale:.4f}%','-resize',f'{cw-4}x{ch-4}>','-background','none','-gravity','south','-extent',f'{cw}x{ch}',raw)
            run(raw,'-alpha','extract',alpha)
            target=outdir/f'{asset_id}_frames/{index:02}.png'
            run(raw,'-alpha','off','-dither','None','-remap',PALETTE,alpha,'-alpha','off','-compose','CopyOpacity','-composite','-define','png:color-type=6',target)
    if asset_id in ['titan_basic','titan_runner']:
        shutil.copyfile(outdir/f'{asset_id}_frames/10.png',outdir/f'{asset_id}_frames/09.png')
    target=outdir/f'{asset_id}.png'
    run('montage',*sorted((outdir/f'{asset_id}_frames').glob('*.png')),'-tile',f'{source_cols}x{source_rows}','-geometry',f'{cw}x{ch}+0+0','-background','none','-define','png:color-type=6',target)
    animations={'idle':{'frames':[0],'fps':8,'loop':True},'move':{'frames':[1,2,3,4],'fps':8,'loop':True},'hit':{'frames':[5],'fps':8,'loop':False},'windup':{'frames':[6],'fps':8,'loop':False},'attack':{'frames':[7,8],'fps':10,'loop':False},'death':{'frames':[9,10,11],'fps':8,'loop':False}}
    extra={}
    if asset_id in ['titan_basic','titan_runner']:
        animations['death']['frames']=[10,11]
        extra['frame_notes']={'9':'Unused duplicate of inspected kneel pose; source falling pose rejected for cell-boundary artifact.'}
    if asset_id=='armored_titan':
        animations.pop('death',None);animations['entry']={'frames':[9,10],'fps':8,'loop':False};animations['retreat']={'frames':[10,11],'fps':8,'loop':True};extra['defeatable']=False
    register(asset_id,target,'sprite',cw,ch,source_cols,animations,anchor=[cw//2,ch],extra=extra)
    preview=ROOT/f'assets/art/previews/{asset_id}-preview-v0.1.0-dev1.png'
    run(target,'-background','#59645d','-alpha','remove','-filter','point','-resize','200%',preview)
    return str(target)

def register(asset_id,path,kind,cw,ch,columns,animations=None,anchor=None,extra=None):
    path=pathlib.Path(path);iw,ih=map(int,run('identify','-format','%w %h',path).split())
    rec={'path':'res://'+str(path.relative_to(ROOT)),'kind':kind,'source_method':'Original built-in image generation; hard-alpha nearest-neighbor atlas extraction and shared-palette mapping. No extracted third-party game assets.','license_note':'Original generated fan-game artwork; underlying setting belongs to its rights holders. Private fan prototype, no official affiliation.','width':iw,'height':ih,'cell_w':cw,'cell_h':ch,'columns':columns,'anchor_px':anchor or [cw//2,ch],'animations':animations or {'idle':{'frames':[0],'fps':8,'loop':True}},'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    if extra:rec.update(extra)
    m=json.loads(M.read_text());m['assets'][asset_id]=rec;M.write_text(json.dumps(m,indent=2)+'\n')
    return rec

if __name__=='__main__':
 import sys
 print(pack_character(sys.argv[1],sys.argv[2],(int(sys.argv[3]),int(sys.argv[4])) if len(sys.argv)>3 else (96,144)))

def pack_ui(source):
    source=pathlib.Path(source); shutil.copyfile(source,ROOT/'assets/art/source/ui_icons-generation.png')
    outdir=ROOT/'assets/art/ui';outdir.mkdir(exist_ok=True)
    iw,ih=map(int,run('identify','-format','%w %h',source).split())
    ids=['icon_twin_blades','icon_spin_slash','icon_omni_dash','icon_reentry_combo','icon_wall_cannon','icon_ally_cover','icon_damage','icon_cooldown','icon_movement','icon_health','icon_regeneration','icon_pickup','icon_range','icon_armor','xp_pickup','danger_marker','escape_marker','gamepad_a','gamepad_b','pause_icon']
    with tempfile.TemporaryDirectory(prefix='survivor-ui-') as work:
        w=pathlib.Path(work)
        for i,asset_id in enumerate(ids):
            x0=round(i%5*iw/5);x1=round((i%5+1)*iw/5);y0=round(i//5*ih/4);y1=round((i//5+1)*ih/4)
            raw=w/f'{i}.png';alpha=w/f'{i}-alpha.png';target=outdir/f'{asset_id}.png'
            run(source,'-crop',f'{x1-x0}x{y1-y0}+{x0}+{y0}','+repage','-channel','A','-threshold','55%','+channel','-trim','+repage','-filter','point','-resize','28x28','-background','none','-gravity','center','-extent','32x32',raw)
            run(raw,'-alpha','extract',alpha)
            run(raw,'-alpha','off','-dither','None','-remap',PALETTE,alpha,'-alpha','off','-compose','CopyOpacity','-composite','-define','png:color-type=6',target)
            register(asset_id,target,'ui_icon',32,32,1,anchor=[16,16])
    # Remove a small prior-row source sliver from the heart icon and use the actual garrison design for allies.
    health=outdir/'icon_health.png'
    with tempfile.TemporaryDirectory() as work:
        w=pathlib.Path(work);a=w/'alpha.png';c=w/'clean.png';run(health,'-alpha','extract',a)
        report=run(a,'-define','connected-components:verbose=true','-connected-components','8','null:');match=re.search(r'^\s*(\d+):.*(?:gray\(255\)|srgb\(255,255,255\))',report,re.M)
        run(a,'-define','connected-components:mean-color=true','-define','connected-components:keep='+match[1],'-connected-components','8',c)
        run(health,'-alpha','off',c,'-alpha','off','-compose','CopyOpacity','-composite','-define','png:color-type=6',health)
    register('icon_health',health,'ui_icon',32,32,1,anchor=[16,16])
    ally=outdir/'icon_ally_cover.png';soldier=ROOT/'assets/art/characters/garrison_frames/00.png'
    run('-size','32x32','xc:none','(',soldier,'-trim','+repage','-filter','point','-resize','14x25',')','-geometry','+2+4','-composite','(',soldier,'-trim','+repage','-filter','point','-resize','14x25',')','-geometry','+16+4','-composite','-define','png:color-type=6',ally)
    register('icon_ally_cover',ally,'ui_icon',32,32,1,anchor=[16,16],extra={'source_method':'Original garrison sprite composition, nearest-neighbor resized; no external artwork.'})
    target=outdir/'ui_icons.png';run('montage',*[outdir/f'{a}.png' for a in ids],'-tile','5x4','-geometry','32x32+0+0','-background','none','-define','png:color-type=6',target)
    run(target,'-background','#293136','-alpha','remove','-filter','point','-resize','400%',ROOT/'assets/art/previews/ui-icons-preview-v0.1.0-dev1.png')
