"""Read-only validation of runtime raster/audio assets and licensed OGG scores."""
from pathlib import Path
from PIL import Image
import hashlib,json,math,wave,struct,subprocess,array,sys
ROOT=Path(__file__).resolve().parents[2]
m=json.loads((ROOT/'assets/manifest.json').read_text());palette={tuple(bytes.fromhex(c[1:])) for c in m['palette']};checks=0
for aid,a in m['assets'].items():
 p=ROOT/a['path'][6:];assert p.is_file(),aid;assert hashlib.sha256(p.read_bytes()).hexdigest()==a['sha256'],aid;checks+=2
 if a['kind']=='audio':
  if p.suffix=='.ogg':
   probe=subprocess.run(['ffprobe','-v','error','-select_streams','a:0','-show_entries','stream=codec_name,sample_rate,channels,duration','-of','json',str(p)],capture_output=True,text=True,timeout=30)
   assert probe.returncode==0,(aid,'OGG probe failed')
   streams=json.loads(probe.stdout)['streams'];assert len(streams)==1,aid;info=streams[0]
   assert info['codec_name']=='vorbis' and int(info['sample_rate'])==a['sample_rate']==44100 and int(info['channels'])==a['channels']==2,aid
   decoded=subprocess.run(['ffmpeg','-v','error','-nostdin','-i',str(p),'-f','s16le','-acodec','pcm_s16le','-ac','2','-ar','44100','pipe:1'],capture_output=True,timeout=120)
   assert decoded.returncode==0 and not decoded.stderr,(aid,'OGG full decode failed')
   samples=array.array('h');samples.frombytes(decoded.stdout)
   if sys.byteorder!='little':samples.byteswap()
   peak=max(map(abs,samples));assert 0<peak<32767 and abs(len(samples)/88200-a['duration_seconds'])<.01,aid
   assert a['loop'] is True and a['duration_seconds']>20 and 0<a['peak']<1 and a.get('source_layers'),aid
   boundary_step=max(abs(samples[-2]-samples[0]),abs(samples[-1]-samples[1]))/32768.0
   print('OGG_DECODE '+json.dumps({'id':aid,'decoded_seconds':len(samples)/88200,'peak':peak/32768.0,'end_to_start_adjacent_step':boundary_step,'note':'PCM boundary statistic, not subjective loop-quality approval'}))
   checks+=5;continue
  with wave.open(str(p)) as f:
   assert f.getnchannels()==1 and f.getsampwidth()==2 and f.getframerate()==22050,aid
   data=struct.unpack('<'+'h'*f.getnframes(),f.readframes(f.getnframes()));assert 0<max(abs(x) for x in data)<32767,aid
  checks+=2;continue
 im=Image.open(p);assert im.mode=='RGBA' and im.size==(a['width'],a['height']),aid;pixels=list(im.get_flattened_data());opaque=[c for c in pixels if c[3]];assert opaque,aid;assert {c[:3] for c in opaque}<=palette,aid;checks+=3
 if a['kind']!='telegraph':assert {c[3] for c in pixels}<={0,255},aid;checks+=1
 for animation in a['animations'].values():
  for f in animation['frames']:
   x=f%a['columns']*a['cell_w'];y=f//a['columns']*a['cell_h'];assert im.crop((x,y,x+a['cell_w'],y+a['cell_h'])).getchannel('A').getbbox(),(aid,f);checks+=1
 if a['kind']=='sprite':
  frames=a['animations']['move']['frames'];unique=set()
  for f in frames:
   x=f%a['columns']*a['cell_w'];y=f//a['columns']*a['cell_h'];unique.add(im.crop((x,y,x+a['cell_w'],y+a['cell_h'])).tobytes())
  if a.get('ordinary_two_frame',False):
   assert aid in {'titan_quadruped','titan_stone_thrower'} and frames==[0,1] and len(unique)==2,aid
  else: assert len(unique)>=4,aid
  checks+=1
 if a['kind']=='telegraph':
  for y in range(im.height):
   for x in range(im.width):
    px=x+.5;py=y+.5
    if aid=='danger_circle':inside=(px-32)**2+(py-32)**2<=32**2
    elif aid=='danger_line':inside=(px-min(112,max(16,px)))**2+(py-16)**2<=16**2
    else:inside=px>=0 and px*px+(py-128)**2<=128**2 and abs(py-128)<=px
    assert (im.getpixel((x,y))[3]>0)==inside,(aid,x,y)
  checks+=im.width*im.height
assert 'death' not in m['assets']['armored_titan']['animations'];checks+=1
print(f'PASS: {len(m["assets"])} manifest records; {checks} raster/audio/geometry checks; RGBA/palette/alpha/frame/SHA/WAV/OGG and exact warning-mask geometry checks passed.')
