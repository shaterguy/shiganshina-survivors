from pathlib import Path
import subprocess,json,os,hashlib
r=Path(__file__).resolve().parents[2];out=r/'assets/art/previews';f=r/'assets/art/characters/armored_titan_v3c_frames';os.environ['XDG_CACHE_HOME']='/tmp/shiganshina-art-cache'
# Hand-inspected native-pixel landmark annotations, not rig data used to alter art.
points=[
 {'RA':[[72,76],[43,116],[21,160]],'LA':[[134,85],[145,126],[174,158]],'RL':[[92,149],[132,183],[156,241]],'LL':[[96,158],[44,216],[28,239]]},
 {'RA':[[73,78],[42,117],[23,163]],'LA':[[136,84],[148,133],[177,163]],'RL':[[94,151],[135,174],[130,242]],'LL':[[99,162],[57,210],[41,232]]},
 {'RA':[[72,61],[52,102],[34,133]],'LA':[[132,71],[142,109],[159,139]],'RL':[[94,139],[123,174],[119,242]],'LL':[[101,148],[85,191],[80,218]]},
 {'RA':[[81,65],[84,110],[119,131]],'LA':[[74,84],[49,109],[44,137]],'RL':[[86,156],[94,185],[64,244]],'LL':[[111,157],[151,175],[154,213]]},
 {'RA':[[75,71],[75,117],[121,151]],'LA':[[68,93],[38,127],[20,160]],'RL':[[91,155],[65,199],[28,242]],'LL':[[105,163],[135,208],[158,243]]},
 {'RA':[[72,76],[79,117],[123,151]],'LA':[[69,90],[47,126],[26,158]],'RL':[[95,159],[88,190],[39,243]],'LL':[[107,162],[143,183],[159,244]]},
 {'RA':[[69,62],[40,94],[16,133]],'LA':[[137,71],[154,105],[176,137]],'RL':[[91,136],[139,151],[139,217]],'LL':[[93,153],[85,196],[93,243]]},
 {'RA':[[76,61],[45,106],[21,158]],'LA':[[138,78],[150,122],[176,152]],'RL':[[98,133],[143,157],[150,222]],'LL':[[92,149],[61,206],[41,241]]},
]
labels=['R heel / L arm front','R support / L arm front','R support / arms reverse next','L swing / R arm front','L heel / R arm front','L support / R arm front','R swing / L arm front','R reach / L arm front']
colors={'RA':'#66e5ff','LA':'#809dff','RL':'#fff07b','LL':'#ff8e91'}
args=['magick','-size','1664x1232','xc:#293136']
for i in range(8):
 x=(i%4)*416+16;y=(i//4)*600+58
 args += ['(',str(f/f'{12+i:02}.png'),'-filter','point','-resize','200%',')','-geometry',f'+{x}+{y}','-composite']
 for key,chain in points[i].items():
  pairs=[(x+2*a,y+2*b) for a,b in chain];args+=['-stroke',colors[key],'-strokewidth','2','-fill','none','-draw','polyline '+' '.join(f'{a},{b}' for a,b in pairs)]
  a,b=pairs[-1];args+=['-fill',colors[key],'-stroke','none','-draw',f'circle {a},{b} {a+4},{b}','-font','DejaVu-Sans','-pointsize','14','-annotate',f'+{max(x,a-12)}+{b-8}',key]
 args+=['-stroke','none','-fill','#efe2bd','-font','DejaVu-Sans','-pointsize','17','-annotate',f'+{x}+{y-20}',f'{i+1}: {labels[i]}']
args+=['-fill','#efe2bd','-pointsize','17','-annotate','+16+1200','RA/LA = anatomical right/left arm. RL/LL = right/left leg. Right is nearer/brighter in every frame.',str(out/'Shiganshina-armored-v3c-limb-audit.png')]
subprocess.run(args,check=True)
(r/'docs/art/armored-v3c-limb-landmarks.json').write_text(json.dumps({'coordinate_space':'192x256 cell, x right, y down','near_side':'anatomical right, brighter','far_side':'anatomical left, darker','annotation_only':True,'atlas_sha256':hashlib.sha256((r/'assets/art/characters/armored_titan_v3c.png').read_bytes()).hexdigest(),'review_note':'Manually inspected approximate image landmarks; occluded joints are estimates, not rig measurements.','frames':points},indent=2)+'\n')
