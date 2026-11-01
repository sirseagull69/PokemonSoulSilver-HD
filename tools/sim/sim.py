import numpy as np
from PIL import Image
S=3; W,H=256*S,192*S
# Kamera schräg von oben wie in HGSS
cam=np.array([0.,9.,11.]); tgt=np.array([0.,0.,0.])
f=tgt-cam; f/=np.linalg.norm(f); r=np.cross(f,[0,1,0]); r/=np.linalg.norm(r); u=np.cross(r,f)
fov=np.tan(np.radians(26))
xs=(np.arange(W)+.5)/W*2-1; ys=1-(np.arange(H)+.5)/H*2
X,Y=np.meshgrid(xs*fov*W/H,ys*fov)
D=f[None,None]+X[...,None]*r+Y[...,None]*u; D/=np.linalg.norm(D,axis=2,keepdims=True)
t=np.full((H,W),np.inf); col=np.zeros((H,W,3)); nrm=np.zeros((H,W,3))
# Boden
tg=-cam[1]/D[...,1]; m=(tg>0)
t[m]=tg[m]; P=cam+D*tg[...,None]
grass=np.array([120,190,110])/255; path=np.array([215,200,160])/255
onpath=(np.abs(P[...,0])<1.2)|(np.abs(P[...,2]-1.5)<1.0)
col[m]=np.where(onpath[m][:,None],path,grass); nrm[m]=[0,1,0]
def box(lo,hi,c):
    lo=np.array(lo,float); hi=np.array(hi,float)
    with np.errstate(divide='ignore',invalid='ignore'):
        t1=(lo-cam)/D; t2=(hi-cam)/D
    tn=np.minimum(t1,t2).max(2); tf=np.maximum(t1,t2).min(2)
    hit=(tn<tf)&(tn>0)&(tn<t)
    ax=np.argmax(np.minimum(t1,t2),axis=2)
    n=np.zeros((H,W,3)); idx=np.indices((H,W))
    n[idx[0],idx[1],ax]=-np.sign(D[idx[0],idx[1],ax])
    t[hit]=tn[hit]; nrm[hit]=n[hit]; col[hit]=np.array(c)/255
houses=[((-5,0,-4),(-2,2.2,-1.5),(235,225,205)),((-5,2.2,-4.2),(-2,2.8,-1.3),(200,70,60)),
        ((2.2,0,-4.5),(5.5,2.6,-2),(230,220,200)),((2.2,2.6,-4.7),(5.5,3.2,-1.8),(70,110,190)),
        ((-4.5,0,3.5),(-2,1.8,5.5),(225,215,195)),((-4.6,1.8,3.4),(-1.9,2.3,5.6),(190,120,60)),
        ((3,0,3.2),(3.6,1.4,3.8),(90,150,80)),((4.2,0,3.6),(4.8,1.2,4.2),(90,150,80)),
        ((-1.6,0,-0.4),(-1.3,.5,3.4),(160,120,80)),((1.3,0,-0.4),(1.6,.5,3.4),(160,120,80)),
        ((-.25,0,.9),(.25,1.0,1.3),(240,90,70))]  # Figur
for lo,hi,c in houses: box(lo,hi,c)
bg=t==np.inf
L=np.array([.4,.8,.45]); L/=np.linalg.norm(L)
shade=.55+.45*np.clip((nrm*L).sum(2),0,1)
img=np.clip(col*shade[...,None],0,1); img[bg]=[.55,.75,.95]
near,far=4.,30.
vw=t*(D@f)  # Sichttiefe w
import sys
mode=sys.argv[1] if len(sys.argv)>1 else 'w'
if mode=='w': dd=(vw-near)/(far-near)
else: dd=(far*(vw-near))/(vw*(far-near))  # z/w wie Z-Buffer
depth=np.where(bg,1.0,np.clip(dd,0,.999))
np.save('/root/sim/depth.npy',depth); np.save('/root/sim/img.npy',img)
