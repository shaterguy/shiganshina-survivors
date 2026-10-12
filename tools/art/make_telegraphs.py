"""Original deterministic raster diagrams of the exact collision geometry.
These functional masks are authored as pixels; no SVG or pre-existing image is used.
The renderer must preserve a circle's aspect ratio and use 3-slice stretching for line caps.
"""
import pathlib, math, struct, zlib, json, hashlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/art/effects'
OUT.mkdir(exist_ok=True)
def png(path,w,h,pixels):
 def chunk(k,d):return struct.pack('>I',len(d))+k+d+struct.pack('>I',zlib.crc32(k+d)&0xffffffff)
 raw=b''.join(b'\0'+bytes(pixels[y*w*4:(y+1)*w*4]) for y in range(h))
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))
def circle(x,y):return (x-32)**2+(y-32)**2<=32**2
def line(x,y):return (x-min(112,max(16,x)))**2+(y-16)**2<=16**2
def sector(x,y):return x>=0 and x*x+(y-128)**2<=128**2 and abs(y-128)<=x
specs=[('danger_circle',64,64,[32,32],circle,{'shape':'circle','radius_px':32}),('danger_line',128,32,[16,16],line,{'shape':'line','length_px':96,'width_px':32,'stretch_mode':'three_slice_caps','cap_px':16,'direction':[1,0]}),('danger_sector',128,256,[0,128],sector,{'shape':'sector','radius_px':128,'arc_degrees':90,'direction':[1,0]})]
m=json.loads((ROOT/'assets/manifest.json').read_text())
for aid,w,h,anchor,inside,geo in specs:
 pixels=[]
 for y in range(h):
  for x in range(w):
   px=x+.5;py=y+.5
   if not inside(px,py):c=(0,0,0,0)
   elif any(not inside(px+dx,py+dy) for dx,dy in [(-2,0),(2,0),(0,-2),(0,2)]):c=(245,203,118,235)
   elif (x+y)%12<3:c=(237,155,73,112)
   else:c=(220,117,82,54)
   pixels.extend(c)
 p=OUT/(aid+'.png');png(p,w,h,pixels)
 m['assets'][aid]={'path':'res://'+str(p.relative_to(ROOT)),'kind':'telegraph','source_method':'Original deterministic per-pixel collision-geometry raster with high-contrast border and diagonal warning hatch. No SVG or third-party asset.','license_note':'Original authored raster graphic.','width':w,'height':h,'cell_w':w,'cell_h':h,'columns':1,'anchor_px':anchor,'animations':{'idle':{'frames':[0],'fps':8,'loop':True}},'geometry':geo,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
(ROOT/'assets/manifest.json').write_text(json.dumps(m,indent=2)+'\n')
print('Three exact-geometry telegraph PNGs written.')
