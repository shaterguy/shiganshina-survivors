"""Run only on the authorized Galaxy Tab MANUAL executor. No synthesized notes.
Compose licensed recorded foley, retain composer-authored scores, and save a
candidate bank plus same-timing audition files. Does not modify source/.
"""
import argparse,hashlib,json,math,pathlib,subprocess,urllib.request,wave,zipfile
import numpy as np
P=argparse.ArgumentParser();P.add_argument('--workspace',required=True);A=P.parse_args()
W=pathlib.Path(A.workspace).resolve();S=W/'source';C=W/'audio-candidate';RAW=W/'audio-sources';OUT=C/'assets/audio';PROOF=W/'evidence/audio-preview'
for p in [RAW,OUT,PROOF]:p.mkdir(parents=True,exist_ok=True)
CATALOG=json.loads((W/'audio-source-catalog.json').read_text());CACHE={};RECORDS={};SR=22050
assert hashlib.sha256((S/'assets/manifest.json').read_bytes()).hexdigest()=='07186688491c15394fe6c111855d896fa7d6b28f9a98abdbd9313e56a56a1255','source_manifest_changed'
def emit(event,**fields):print(json.dumps({'event':event,**fields}),flush=True)
def run(args):
 p=subprocess.run(args,capture_output=True,timeout=180)
 if p.returncode:raise RuntimeError('audio_command_failed:'+p.stderr.decode(errors='replace')[-2000:])
 return p.stdout
for key,r in CATALOG.items():
 p=RAW/r['filename']
 if not p.exists():
  tmp=p.with_suffix(p.suffix+'.part')
  if tmp.exists():raise RuntimeError('partial_download_requires_inspection:'+str(tmp))
  with urllib.request.urlopen(r['url'],timeout=90) as src,tmp.open('xb') as dst:
   assert src.geturl().startswith('https://')
   while True:
    b=src.read(1024*1024)
    if not b:break
    dst.write(b)
  assert tmp.stat().st_size==r['size'] and hashlib.sha256(tmp.read_bytes()).hexdigest()==r['sha256'],key
  tmp.rename(p)
 assert p.stat().st_size==r['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256'],key
 emit('AUDIO_SOURCE_VERIFIED',id=key,sha256=r['sha256'],bytes=r['size'],license=r['license'])
def materialize(key,member=''):
 r=CATALOG[key];p=RAW/r['filename']
 if not member:return p
 target=RAW/key/member
 assert not pathlib.PurePosixPath(member).is_absolute() and '..' not in pathlib.PurePosixPath(member).parts
 target.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(p) as archive:data=archive.read(member)
 if not target.exists():target.write_bytes(data)
 else:assert target.read_bytes()==data
 return target
def decode(path,sr=SR,ch=1):
 raw=run(['ffmpeg','-v','error','-nostdin','-i',str(path),'-f','f32le','-acodec','pcm_f32le','-ar',str(sr),'-ac',str(ch),'pipe:1'])
 return np.frombuffer(raw,dtype='<f4').copy().reshape((-1,ch))
def take(key,member='',start=0.,seconds=None,rate=1.,reverse=False):
 k=(key,member)
 if k not in CACHE:
  x=decode(materialize(key,member))[:,0]
  if key not in ['combat_music','boss_music','menu_music']:
   peak=float(np.max(np.abs(x))) if len(x) else 0.
   assert peak>0.00001,(key,member)
   live=np.flatnonzero(np.abs(x)>max(.0002,peak*.006))
   if len(live):x=x[max(0,int(live[0]) - 64):min(len(x),int(live[-1])+256)]
   x=x/(max(float(np.max(np.abs(x))),.0001))*.8
  CACHE[k]=x
 x=CACHE[k][round(start*SR):].copy()
 if seconds is not None:x=x[:round(seconds*SR)]
 if reverse:x=x[::-1].copy()
 if rate!=1.:x=np.interp(np.arange(0,len(x),rate),np.arange(len(x)),x).astype('float32')
 fade=min(len(x)//2,round(.009*SR))
 if fade:x[:fade]*=np.linspace(0,1,fade);x[-fade:]*=np.linspace(1,0,fade)
 return x
def layer(key,member='',offset=0.,gain=1.,**kw):return (take(key,member,**kw),offset,gain,key,member,kw)
def author(name,layers,tail=.10,peak=.76):
 n=max(round(at*SR)+len(x) for x,at,_,_,_,_ in layers)+round(tail*SR);x=np.zeros(n,dtype=np.float32)
 provenance=[]
 for a,at,gain,key,member,settings in layers:
  i=round(at*SR);x[i:i+len(a)]+=a*gain
  provenance.append({'source_id':key,'member':member,'source_sha256':CATALOG[key]['sha256'],'offset_seconds':at,'gain':gain,**settings})
 x-=np.mean(x)
 fade=min(round(.018*SR),len(x)//2);x[:fade]*=np.linspace(0,1,fade);x[-fade:]*=np.linspace(1,0,fade)
 x*=min(1.,peak/max(float(np.max(np.abs(x))),.00001))
 pcm=np.rint(x*32767).astype('<i2');p=OUT/(name+'.wav')
 with wave.open(str(p),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(pcm.tobytes())
 record(name,p,SR,1,len(x)/SR,False,float(np.max(np.abs(pcm.astype(np.int32))))/32767,provenance)
def record(name,path,sr,ch,duration,loop,peak,provenance):
 RECORDS[name]={'path':'res://assets/audio/'+path.name,'kind':'audio','codec':'vorbis' if path.suffix=='.ogg' else 'pcm_s16le','source_method':'Licensed foley layers / independently composed orchestral score; processed by tools/art/author_foley_audio.py. No old oscillator bank or note-score synthesis.','license_note':'Source works are CC0 1.0. Credits, source URLs, source SHA-256 and exact modifications are preserved in audio_sources and source_layers.','source_layers':provenance,'width':0,'height':0,'cell_w':0,'cell_h':0,'anchor_px':[0,0],'animations':{},'sample_rate':sr,'channels':ch,'duration_seconds':duration,'loop':loop,'peak':peak,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'audio_revision':'recorded_foley_orchestral_v1'}
def K(name,**kw):return layer('impact','Audio/'+name+'.ogg',**kw)
def R(name,**kw):return layer('rpg','Audio/'+name+'.ogg',**kw)
def V(name,**kw):return layer('weapons','sfx/'+name+'.wav',**kw)
def SW(i,**kw):return layer('swishes','swishes/swish-'+str(i)+'.wav',**kw)
def GAS(i,**kw):return layer('steam','steam hisses - Marker #'+str(i)+'.wav',**kw)
def BOOM(**kw):return layer('boom',**kw)
def FIRE(**kw):return layer('fire',**kw)
# Independent recorded takes supply variation, rather than a pitch-only switch.
for n in range(3):
 suffix='' if n==0 else '_v'+str(n+1)
 author('slash'+suffix,[SW(5+n,gain=.9),V('sword-knife-clash-%02d'%(7+n*4),offset=.065,gain=.28,seconds=.32)])
 author('hit'+suffix,[K('impactPunch_heavy_%03d'%n,gain=.9),R('chop',offset=.012,gain=.32,seconds=.22)])
 author('hurt'+suffix,[K('impactPunch_medium_%03d'%n,gain=.82),R('cloth'+str(n+1),offset=.015,gain=.37)])
 author('step'+suffix,[K('footstep_concrete_%03d'%n,gain=.65),V('boots-leather-step-%02d'%(n+1),gain=.32)],peak=.56)
 author('titan_step'+suffix,[BOOM(seconds=.64,rate=.84,gain=.62),K('impactWood_heavy_%03d'%n,gain=.34),K('footstep_concrete_%03d'%(n+2),offset=.048,gain=.29)],tail=.16)
 author('gas'+suffix,[GAS(n+1,seconds=.65,gain=.8),R('cloth'+str(n+1),offset=.012,gain=.28)],peak=.65)
 author('wire_launch'+suffix,[V('sword-thermos-scrape-%02d'%(n+1),seconds=.22,gain=.58),R('metalLatch',gain=.38),SW(n+1,offset=.03,gain=.62)])
 author('armor_block'+suffix,[V('sword-knife-clash-%02d'%(24+n*2),gain=.82),K('impactMetal_medium_%03d'%n,offset=.025,gain=.36)])
author('cannon',[BOOM(seconds=1.8,gain=1.),K('impactPlate_heavy_001',gain=.25),K('impactWood_heavy_003',offset=.04,gain=.40)],tail=.2)
author('select',[R('metalClick',gain=.63),R('cloth1',offset=.025,seconds=.16,gain=.20)],peak=.55)
author('cancel',[R('metalLatch',seconds=.14,gain=.49),R('bookClose',offset=.035,seconds=.16,gain=.35)],peak=.48)
author('xp',[R('handleCoins2',seconds=.13,gain=.65)],peak=.40)
author('level_up',[K('impactBell_heavy_001',gain=.45),SW(4,reverse=True,gain=.40),K('impactBell_heavy_003',offset=.17,gain=.33)],tail=.5,peak=.62)
author('boss_spawn',[BOOM(seconds=2.5,gain=.85),K('impactMetal_heavy_004',offset=.10,gain=.5),GAS(5,offset=.18,seconds=.65,gain=.25)],tail=.3)
author('heal',[R('cloth3',gain=.68),R('clothBelt',offset=.16,gain=.48),R('beltHandle1',offset=.3,gain=.22)],peak=.50)
author('wire_release',[R('metalLatch',gain=.38),V('sheath-unbuckle-02',offset=.025,gain=.6)])
author('land',[V('boots-leather-jump-02',gain=.8),K('impactSoft_heavy_001',offset=.018,gain=.42)])
author('structure_break',[K('impactWood_heavy_002',gain=.65),BOOM(offset=.035,seconds=.65,gain=.55),K('impactMining_001',offset=.11,gain=.5),K('impactWood_medium_003',offset=.2,gain=.35)])
author('spin_slash',[SW(10,gain=.85),SW(12,offset=.12,gain=.7),V('sword-knife-clash-16',offset=.19,gain=.28)])
author('reentry_combo',[SW(5,gain=.8),SW(8,offset=.095,gain=.7),V('sword-knife-clash-21',offset=.17,gain=.55)])
author('ally_cover',[GAS(4,seconds=.6,gain=.55),SW(11,offset=.07,gain=.67),V('sword-knife-clash-19',offset=.20,gain=.30)])
author('chain_lightning',[FIRE(start=.22,seconds=.20,gain=.8),V('sword-knife-clash-39',offset=.025,seconds=.23,gain=.55),BOOM(offset=.07,seconds=.40,gain=.38)])
author('fire_zone',[GAS(5,seconds=.65,gain=.45),FIRE(start=.4,seconds=.85,gain=.7)],peak=.64)
# Evolved techniques are authored as distinct multi-take compositions. Each
# executed stage selects its own rendered file; no real-time transposition.
for n in range(3):
 suffix='' if n==0 else '_v'+str(n+1)
 author('evo_wing_cut'+suffix,[SW(9+n,gain=.9),V('sword-knife-clash-%02d'%(10+n),offset=.07,gain=.55),SW(5+n,offset=.13,gain=.62)])
 author('evo_crossfire'+suffix,[BOOM(seconds=1.0,gain=.72),K('impactPlate_heavy_%03d'%n,gain=.32),BOOM(offset=.15+n*.025,seconds=.85,gain=.58),K('impactWood_heavy_%03d'%(n+1),offset=.2,gain=.30)],tail=.2)
 author('evo_storm_chain'+suffix,[FIRE(start=n*.23,seconds=.22,gain=.75),V('sword-knife-clash-%02d'%(35+n),offset=.018,gain=.5),FIRE(start=.4+n*.18,seconds=.20,offset=.14,gain=.62),BOOM(offset=.1,seconds=.6,gain=.43)])
 author('evo_inferno_zone'+suffix,[GAS(n+2,seconds=.6,gain=.62),FIRE(start=n*.24,seconds=.85,gain=.72),BOOM(offset=.18,seconds=.65,gain=.4)],tail=.2)
 author('evo_whirlwind'+suffix,[SW(5+n,gain=.75),SW(9+n,offset=.08,gain=.72),SW(11-n,offset=.19,gain=.7),V('sword-knife-clash-%02d'%(18+n),offset=.15,gain=.42)])
 author('evo_sky_lance'+suffix,[V('sword-thermos-scrape-%02d'%(n+1),seconds=.25,gain=.5),GAS(n+1,seconds=.65,gain=.78),K('impactMetal_heavy_%03d'%n,offset=.1,gain=.48),BOOM(offset=.06,seconds=.5,gain=.5)])
 author('evo_echo_assault'+suffix,[SW(n+5,gain=.8),V('sword-knife-clash-%02d'%(n+11),offset=.075,gain=.55),SW(n+8,offset=.17,gain=.65),V('sword-knife-clash-%02d'%(n+27),offset=.25,gain=.50)])
 author('evo_wing_squad'+suffix,[GAS(n+2,seconds=.45,gain=.52),SW(9+n,offset=.035,gain=.66),V('sword-knife-clash-%02d'%(n+22),offset=.11,gain=.40),SW(5+n,offset=.23,gain=.55),K('impactPunch_heavy_%03d'%n,offset=.3,gain=.38)])
# Musical outcome cues are score excerpts, not synthetic note arpeggios.
author('victory',[layer('menu_music',start=27.,seconds=3.6,gain=.9),K('impactBell_heavy_002',offset=.02,gain=.12)],tail=.2,peak=.7)
author('death',[layer('combat_music',start=92.,seconds=2.6,gain=.6),BOOM(seconds=2.2,gain=.55),R('dropLeather',offset=.18,gain=.2)],tail=.25,peak=.67)
CACHE.clear()
for aid,key,seam in [('combat_loop','combat_music',1.2),('boss_loop','boss_music',0.),('menu_loop','menu_music',1.2)]:
 x=decode(materialize(key),44100,2);assert len(x)>44100*20
 if seam:
  n=round(seam*44100);theta=np.linspace(0,math.pi/2,n)[:,None]
  join=x[-n:]*np.cos(theta)+x[:n]*np.sin(theta)
  x=np.concatenate([join,x[n:-n]])
 # Integrated source texture remains intact; only gain and seam treatment.
 rms=math.sqrt(float(np.mean(x*x)));x*=min(10**(-19/20)/max(rms,1e-6),.78/max(float(np.max(np.abs(x))),1e-6))
 p=OUT/(aid+'.ogg');temp=RAW/(aid+'-render.wav')
 with wave.open(str(temp),'wb') as f:f.setnchannels(2);f.setsampwidth(2);f.setframerate(44100);f.writeframes(np.rint(x*32767).astype('<i2').tobytes())
 run(['ffmpeg','-v','error','-nostdin','-y','-i',str(temp),'-c:a','libvorbis','-q:a','5','-ar','44100','-ac','2','-metadata','artist='+CATALOG[key]['creator'],'-metadata','title='+CATALOG[key]['title'],'-metadata','copyright=CC0 1.0',str(p)])
 actual=decode(p,44100,2);peak=float(np.max(np.abs(actual)));assert peak<.92
 record(aid,p,44100,2,len(actual)/44100,True,peak,[{'source_id':key,'source_sha256':CATALOG[key]['sha256'],'modifications':'Vorbis q5 stereo, gain-only master, '+('equal-power %.1f second wrap seam'%seam if seam else 'composer-authored original seamless loop')}])
 emit('AUDIO_SCORE_RENDERED',id=aid,seconds=len(actual)/44100,bytes=p.stat().st_size,peak=peak)
 del x,actual
manifest=json.loads((S/'assets/manifest.json').read_text());old={k:v for k,v in manifest['assets'].items() if v.get('kind')=='audio'}
assert set(old).issubset(set(RECORDS)),'replacement_coverage_gap'
manifest['assets'].update(RECORDS);manifest['audio_sources']=CATALOG;manifest['audio_revision']={'id':'recorded_foley_orchestral_v1','replaced_ids':sorted(old),'voice_cap':8,'music_stream_cap':1,'source_policy':'CC0 sources verified at publisher/uploader pages and pinned to exact bytes; no anime/game soundtrack copies.'}
(C/'assets/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
# Same-timing audition renders with matched BGM RMS. These are actual new bank audio,
# deliberately labelled editorial mixes, never misreported as gameplay captures.
def audition(new,menu):
 n=SR*12;x=np.zeros(n,dtype=np.float32)
 if new or not menu:
  p=OUT/(('menu_loop' if menu else 'combat_loop')+'.ogg') if new else S/'assets/audio/combat_loop.wav'
  a=decode(p)[:n,0];rms=math.sqrt(float(np.mean(a*a)));a*=.085/max(rms,1e-6);x[:len(a)]+=a
 events=[(.7,'select'),(2.4,'cancel'),(4.2,'select'),(7.4,'level_up')] if menu else [(.6,'gas'),(.7,'wire_launch'),(1.5,'slash'),(1.9,'hit'),(2.7,'titan_step'),(3.2,'slash_v2'),(4.1,'cannon'),(5.2,'hurt'),(6.1,'evo_whirlwind'),(7.4,'gas_v2'),(8.2,'evo_storm_chain'),(9.3,'armor_block'),(10.3,'land')]
 for at,aid in events:
  old_alias={'wire_launch':'gas','titan_step':'step','evo_whirlwind':'slash','evo_storm_chain':'hit','armor_block':'hit','land':'step'}
  base=aid.split('_v')[0];name=aid if new else old_alias.get(base,base)
  p=OUT/(name+'.wav') if new else S/'assets/audio'/(name+'.wav')
  a=decode(p)[:,0];i=round(at*SR);a=a[:n-i];x[i:i+len(a)]+=a*.45
 peak=float(np.max(np.abs(x)));x*=min(1.,.89/max(peak,1e-6))
 p=PROOF/(('menu' if menu else 'combat')+('_after.wav' if new else '_before.wav'))
 with wave.open(str(p),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(np.rint(x*32767).astype('<i2').tobytes())
 return {'filename':p.name,'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size,'seconds':12,'peak':float(np.max(np.abs(x))),'rms_dbfs':20*math.log10(max(float(np.sqrt(np.mean(x*x))),1e-10)),'capture_kind':'same-timing editorial audition with BGM RMS matched; not equal-loudness full mixes or live gameplay capture'}
previews=[audition(a,b) for b in [False,True] for a in [False,True]]
report={'schema':1,'candidate':str(C),'source_manifest_sha256':hashlib.sha256((S/'assets/manifest.json').read_bytes()).hexdigest(),'manifest_sha256':hashlib.sha256((C/'assets/manifest.json').read_bytes()).hexdigest(),'audio_count':len(RECORDS),'audio_bytes':sum((OUT/pathlib.Path(r['path']).name).stat().st_size for r in RECORDS.values()),'resident_sfx_pcm_bytes':sum((OUT/pathlib.Path(r['path']).name).stat().st_size for r in RECORDS.values() if r['codec']=='pcm_s16le'),'previews':previews,'records':RECORDS}
(PROOF/'audio-authoring-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
emit('AUDIO_CANDIDATE_READY',**{k:v for k,v in report.items() if k!='records'})
