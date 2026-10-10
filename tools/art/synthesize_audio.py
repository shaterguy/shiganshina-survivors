"""Original deterministic 16-bit PCM game sounds and original short battle scores."""
import math, random, wave, struct, pathlib, json, hashlib
ROOT=pathlib.Path(__file__).resolve().parents[2];OUT=ROOT/'assets/audio';OUT.mkdir(exist_ok=True)
SR=22050;rng=random.Random(845);records={}
def save(name,samples,loop=False):
 peak=max(abs(x) for x in samples) or 1; gain=min(1,.82/peak); pcm=[int(max(-1,min(1,x*gain))*32767) for x in samples]
 p=OUT/(name+'.wav')
 with wave.open(str(p),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(struct.pack('<'+'h'*len(pcm),*pcm))
 records[name]={'path':'res://'+str(p.relative_to(ROOT)),'kind':'audio','source_method':'Original deterministic waveform synthesis and original note score in tools/art/synthesize_audio.py; no sampled game audio.','license_note':'Original composition and synthesized sound.','width':0,'height':0,'cell_w':0,'cell_h':0,'anchor_px':[0,0],'animations':{},'sample_rate':SR,'channels':1,'duration_seconds':len(samples)/SR,'loop':loop,'peak':max(abs(x) for x in pcm)/32767,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def freq(midi):return 440*2**((midi-69)/12)
def add_note(buf,start,dur,midi,amp=.1,kind='pluck'):
 n=int(dur*SR);off=int(start*SR);hz=freq(midi)
 for i in range(min(n,len(buf)-off)):
  t=i/SR;phase=2*math.pi*hz*t;attack=min(1,t/.008);rel=min(1,(dur-t)/.035)
  if kind=='bass':v=(math.sin(phase)+.23*math.sin(2*phase))*math.exp(-2.6*t/dur)
  elif kind=='bell':v=(math.sin(phase)+.32*math.sin(2.01*phase)+.13*math.sin(3.98*phase))*math.exp(-4*t/dur)
  else:v=(math.sin(phase)+.32*math.sin(2*phase)+.12*math.sin(3*phase))*math.exp(-3*t/dur)
  buf[off+i]+=amp*v*attack*rel
for name,dur,f0,f1,noise,amp in [('slash',.16,1500,180,.8,.3),('hit',.14,210,55,.75,.45),('hurt',.32,220,90,.25,.35),('cannon',.8,90,28,.65,.55),('gas',.36,1800,450,.92,.19),('step',.1,110,50,.7,.12)]:
 arr=[];phase=0;last=0
 for i in range(int(dur*SR)):
  t=i/SR;q=t/dur;f=f0*(f1/f0)**q;phase+=2*math.pi*f/SR;env=(1-q)**2*min(1,t/.003);last=.55*last+.45*rng.uniform(-1,1);arr.append(amp*env*((1-noise)*math.sin(phase)+noise*last))
 save(name,arr)
for name,notes,dt in [('xp',[86,93],.055),('select',[74,81],.06),('cancel',[67,60],.09),('level_up',[62,65,69,74,81],.10),('boss_spawn',[38,39,38,26],.22),('victory',[62,65,69,74,77,81,86],.16),('death',[65,62,58,50,38],.18)]:
 arr=[0.]*int((len(notes)*dt+.4)*SR)
 for i,n in enumerate(notes):add_note(arr,i*dt,.32,n,.18,'bell' if name in ['xp','level_up','victory'] else 'bass')
 save(name,arr)
# 16 bars, 4/4. Original D-minor ostinato and motif, no external melody or samples.
for name,bpm in [('combat_loop',112),('boss_loop',132)]:
 beat=60/bpm;duration=64*beat;buf=[0.]*round(duration*SR);roots=[38,34,36,33]*4
 motif=[74,77,81,79,76,77,74,None,72,74,76,79,77,76,74,None]
 for bar,root in enumerate(roots):
  for eighth in range(8):add_note(buf,(bar*4+eighth*.5)*beat,.42*beat,root+[0,12,7,12,0,12,7,10][eighth],.115,'bass')
  for j in range(4):
   note=motif[(bar*4+j)%len(motif)]
   if note:add_note(buf,(bar*4+j)*beat,.8*beat,note,.08 if name=='combat_loop' else .1,'pluck')
  if name=='boss_loop':
   for j in range(4):add_note(buf,(bar*4+j+.5)*beat,.3*beat,root+24,.045,'bell')
 for b in range(64):
  off=int(b*beat*SR)
  for i in range(min(int(.2*SR),len(buf)-off)):
   t=i/SR;env=math.exp(-28*t)
   if b%2==0:buf[off+i]+=.23*env*math.sin(2*math.pi*(60*t-16*t*t))
   else:buf[off+i]+=.11*env*rng.uniform(-1,1)
  for sub in [0,.5]:
   off2=int((b+sub)*beat*SR)
   for i in range(min(int(.055*SR),len(buf)-off2)):buf[off2+i]+=.024*math.exp(-80*i/SR)*rng.uniform(-1,1)
 save(name,buf,True)
m=json.loads((ROOT/'assets/manifest.json').read_text());m['assets'].update(records);(ROOT/'assets/manifest.json').write_text(json.dumps(m,indent=2)+'\n');print(f'{len(records)} original WAV files written, all peaks below 0.83.')
