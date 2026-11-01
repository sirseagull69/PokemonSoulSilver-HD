import numpy as np
from PIL import Image, ImageDraw, ImageFont
d=np.load('/root/sim/depth.npy'); img=np.load('/root/sim/img.npy')
H,W=d.shape; scale=max(W/256,1); strength=0.6; far=1.0
dirs=[(1,0),(.5,.866),(-.5,.866),(-1,0),(-.5,-.866),(.5,-.866),(.866,.5),(0,1),(-.866,.5),(-.866,-.5),(0,-1),(.866,-.5)]
yy,xx=np.indices((H,W))
minD=0.0004+d*0.0006; maxD=0.02+d*0.04
def ss(e0,e1,x):
    t=np.clip((x-e0)/(e1-e0),0,1); return t*t*(3-2*t)
occ=np.zeros_like(d); wt=np.zeros_like(d)
pairs=[(0,3),(1,4),(2,5),(6,9),(7,10),(8,11)]
def samp(i,rad):
    dx,dy=dirs[i]
    ox=xx+int(round(dx*rad)); oy=yy-int(round(dy*rad))
    inb=(ox>=0)&(ox<W)&(oy>=0)&(oy<H)
    return d[np.clip(oy,0,H-1),np.clip(ox,0,W-1)], inb
for k,(i,j) in enumerate(pairs):
    rad=(3 if k<3 else 7)*scale; w=1 if k<3 else .6
    s1,b1=samp(i,rad); s2,b2=samp(j,rad)
    a1=np.abs(d-s1); a2=np.abs(d-s2)
    lo=np.minimum(a1,a2); hi=np.maximum(a1,a2)
    valid=b1&b2&(s1<far-1e-6)&(s2<far-1e-6)&(hi<6.0*lo+2e-5)
    wt+=w
    delta=d-0.5*(s1+s2)
    r=delta/(0.5*np.abs(s1-s2)+np.abs(delta)+1e-7)   # skalenfrei: Ebene 0, Innenecke ->1
    occ+=np.where(valid,w*ss(0.15,0.6,r),0)
ao=np.where(wt>0,np.clip(occ/np.maximum(wt,1e-9),0,1),0); ao=ao*ao*(3-2*ao)
a=ao*.8*strength; a[d>=.9999]=0
out=img*(1-a[...,None])
def to(x): return Image.fromarray((np.clip(x,0,1)*255).astype(np.uint8))
A,B=to(img),to(out); g=12
canvas=Image.new('RGB',(W,H*2+g*3+60),(24,24,28))
canvas.paste(A,(0,30)); canvas.paste(B,(0,H+g*2+60))
dr=ImageDraw.Draw(canvas)
try: fnt=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',22)
except: fnt=None
dr.text((10,4),'Ohne Licht & Schatten',fill=(235,235,235),font=fnt)
dr.text((10,H+g*2+34),'Mit Licht & Schatten (Stärke 60)',fill=(235,235,235),font=fnt)
import sys
canvas.save(sys.argv[1] if len(sys.argv)>1 else '/root/sim/vergleich.png')
to(np.dstack([1-a/ max(a.max(),1e-6)]*3)).save('/root/sim/ao_maske.png')
print(a.max(), (a>0.02).mean())
