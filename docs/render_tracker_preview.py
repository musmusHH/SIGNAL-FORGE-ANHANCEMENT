# Renders the STANDALONE PERFORMANCE TRACKER panel (top-right corner) using
# geometry parsed from the .mq4, and asserts no text/element overlaps.
# It is no longer a HUD tab: it has its own header, collapse button and
# TrackerWidthPx/TrackerHeightPx inputs.
import re,os,sys
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from sfcanvas import Canvas, RoundRect as SFRoundRect
from PIL import Image,ImageDraw,ImageFont
src=open("Signal Forge PRO XAUUSD M5 EA.mq4",encoding='utf-8').read()
def g(pat,d):
    m=re.search(pat,src); return int(m.group(1)) if m else d
H_=g(r'input int    TrackerHeightPx\s*=\s*(\d+);',660)
W_=g(r'input int    TrackerWidthPx\s*=\s*(\d+);',430)
DAYS=g(r'#define SF_TRACK_DAYS (\d+)',6)
kpiH=g(r'int kpiH = SC\((\d+)\);',52)
hdrH=g(r'int hdrH = SC\((\d+)\), rowH',20)
rowH=g(r'int hdrH = SC\(\d+\), rowH = SC\((\d+)\);',21)
flH =g(r'int flH = SC\((\d+)\);',46)
print(f"parsed: W={W_} H={H_} days={DAYS} kpi={kpiH} hdr={hdrH} row={rowH} final={flH}")
def SC(v):return v
TBg=(12,18,34);TBg2=(20,30,54);TPanel=(28,40,72);TPanelHi=(40,56,98)
TBorder=(86,116,190);TAccent=(0,245,255);TAccent2=(178,110,255)
TText=(240,248,255);TTextDim=(158,180,220);TBull=(0,255,170);TBear=(255,60,110)
TFlat=(255,215,70);TWarn=(255,160,50);TGridC=(58,80,132)
TLite=(110,146,225);TDark=(5,8,16);TBullDeep=(0,104,74);TBearDeep=(128,20,50)
DJ="/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
def F(sz,b=0):
    p=DJ%("-Bold" if b else "")
    return ImageFont.truetype(p,sz) if os.path.exists(p) else ImageFont.load_default()
W=W_;headerH=34;H=H_
cv=Canvas(W+40,H+40,(8,11,20));OX,OY=20,20
PANELS=[]
def RR(x,y,w,h,r,f,b=None):
    SFRoundRect(cv,OX+x,OY+y,w,h,r,f,b if b else f,b is not None)
    if b is not None and r>=3: PANELS.append((OX+x,OY+y,w,h,r))
def _line(a,b_,c_,d_,col): cv.Line(a,b_,c_,d_,col)
def Raised(x,y,w,h,r,f,e,sh=True,dep=2):
    if sh:
        for k in range(dep+1,0,-1):
            RR(x+k,y+k,w,h,r,(0,0,0))
    RR(x,y,w,h,r,f,e)
    cv.Line(OX+x+r,OY+y+1,OX+x+w-r-1,OY+y+1,TLite)
    cv.Line(OX+x+1,OY+y+r,OX+x+1,OY+y+h-r-1,TLite)
    cv.Line(OX+x+r,OY+y+h-2,OX+x+w-r-1,OY+y+h-2,TDark)
    cv.Line(OX+x+w-2,OY+y+r,OX+x+w-2,OY+y+h-r-1,TDark)
def Sunk(x,y,w,h,r,f):
    RR(x,y,w,h,r,f,TDark)
    cv.Line(OX+x+r,OY+y+h-2,OX+x+w-r-1,OY+y+h-2,TLite)
def Spine(x,y,h,c):cv.FillRectangle(OX+x,OY+y,OX+x+2,OY+y+h,c)
sp=[]
def T(x,y,s,c,sz=8,b=0,a="la",tag=None):
    d.text((OX+x,OY+y),s,fill=c,font=F(int(sz*1.45),b),anchor=a)
    if tag:sp.append((tag,d.textbbox((OX+x,OY+y),s,font=F(int(sz*1.45)),anchor=a)))
def TR(x,y,s,c,sz=8,b=0,tag=None):T(x,y,s,c,sz,b,"ra",tag)
d=ImageDraw.Draw(cv.img)
pad0=10
Raised(0,0,W,H,12,TBg,TBorder,False,0)
cv.FillRectangle(OX+3,OY+3,OX+W-4,OY+headerH-3,TPanelHi)
cv.Line(OX+10,OY+headerH-1,OX+W-10,OY+headerH-1,TAccent)
pad=10;innerW=W-pad*2
Spine(pad,9,headerH-18,TAccent2)
T(pad+10,7,"PERFORMANCE TRACKER",TText,9,1,"la","hdr")
TR(W-pad-30,9,"XAUUSDr",TTextDim,7,1,"sym")
Raised(W-pad-22,7,22,19,5,TPanel,TAccent,True,1)
T(W-pad-22+11,7+4,"-",TText,8,1,"ma")
y=headerH+8
kw=(innerW-12)//4
K=[("TRADES","18",TAccent),("WIN RATE","61.1%",TBull),("P/FACTOR","1.84",TBull),("MAX DD","7.3%",TBull)]
for k,(lb,v,c) in enumerate(K):
    kx=pad+k*(kw+4);Raised(kx,y,kw,kpiH,6,TPanel,TBorder);Spine(kx+3,y+6,kpiH-12,c)
    T(kx+11,y+7,lb,TTextDim,7,1,"la",f"kpi{k}l");T(kx+11,y+22,v,c,13,1,"la",f"kpi{k}v")
y+=kpiH+8
tblH=26+hdrH+DAYS*rowH+24
Raised(pad,y,innerW,tblH,8,TPanel,TBorder);Spine(pad+4,y+7,13,TAccent)
T(pad+13,y+6,"DAILY BREAKDOWN",TText,8,1,"la","ttl")
TR(pad+innerW-10,y+7,f"LAST {DAYS} DAYS",TTextDim,7,1,"sub")
tx=pad+6;tw=innerW-12
cW=[int(tw*.21),int(tw*.13),int(tw*.20),int(tw*.17),int(tw*.15)]
cW.append(tw-sum(cW))
cH=["DATE","LOTS","PROFIT","GAIN%","WIN%","COMM"]
hy=y+26;Sunk(tx,hy,tw,hdrH,3,TBg2);cx=tx
for c in range(6):
    if c==0:T(cx+6,hy+4,cH[c],TAccent,7,1,"la",f"h{c}")
    else:TR(cx+cW[c]-6,hy+4,cH[c],TAccent,7,1,f"h{c}")
    cx+=cW[c]
ry=hy+hdrH
DATA=[("09.19",0.04,2.31,1.14,75,0.28,1),("09.18",0.05,-1.62,-0.80,33,0.35,0),
      ("09.17",0.03,3.05,1.53,100,0.21,0),("09.16",0.02,-0.94,-0.47,0,0.14,0),
      ("09.15",0.04,1.72,0.87,66,0.28,0),("09.12",0.03,0.88,0.45,66,0.21,0)]
for r,(dt,lots,prof,gain,wrp,cm,today) in enumerate(DATA[:DAYS]):
    bg=TPanelHi if today else (TBg2 if r%2==0 else TPanel)
    RR(tx,ry,tw,rowH-1,2,bg,bg)
    if today:Spine(tx+1,ry+3,rowH-7,TAccent)
    pc=TBull if prof>0 else TBear
    cx=tx
    T(cx+6,ry+5,dt+("  *" if today else ""),TText if today else TTextDim,7,1,"la",f"r{r}c0");cx+=cW[0]
    TR(cx+cW[1]-6,ry+5,f"{lots:.2f}",TText,7,1,f"r{r}c1");cx+=cW[1]
    TR(cx+cW[2]-6,ry+4,f"{prof:+.2f}",pc,8,1,f"r{r}c2");cx+=cW[2]
    TR(cx+cW[3]-6,ry+5,f"{gain:+.2f}%",pc,7,1,f"r{r}c3");cx+=cW[3]
    TR(cx+cW[4]-6,ry+5,f"{wrp}%",TBull if wrp>=50 else TBear,7,1,f"r{r}c4");cx+=cW[4]
    TR(cx+cW[5]-6,ry+5,f"-{cm:.2f}",TWarn,7,1,f"r{r}c5")
    ry+=rowH
Sunk(tx,ry+2,tw,19,3,TBg);cx=tx
T(cx+6,ry+6,"TOTAL",TAccent,7,1,"la","tot0");cx+=cW[0]
TR(cx+cW[1]-6,ry+6,"0.21",TText,7,1,"tot1");cx+=cW[1]
TR(cx+cW[2]-6,ry+5,"+5.40",TBull,8,1,"tot2");cx+=cW[2]
TR(cx+cW[3]-6,ry+6,"+2.70%",TBull,7,1,"tot3");cx+=cW[3]
TR(cx+cW[4]-6,ry+6,"61%",TBull,7,1,"tot4");cx+=cW[4]
TR(cx+cW[5]-6,ry+6,"-1.47",TWarn,7,1,"tot5")
y+=tblH+8
Raised(pad,y,innerW,flH,8,TBullDeep,TBull);Spine(pad+4,y+8,flH-16,TBull)
T(pad+13,y+6,"FINAL P/L  (NET OF COMMISSION)",TText,7,1,"la","fl1")
T(pad+13,y+20,"+5.40  USD",TBull,15,1,"la","fl2")
TR(pad+innerW-12,y+8,"GROSS +6.87",TTextDim,7,1,"fl3")
TR(pad+innerW-12,y+20,"FEES -1.47",TWarn,8,1,"fl4")
TR(pad+innerW-12,y+32,"BAL 205.40",TText,7,1,"fl5")
y+=flH+8
sparkH=H-y-40
if sparkH>=54:
    Raised(pad,y,innerW,sparkH,8,TPanel,TBorder);Spine(pad+4,y+7,12,TAccent2)
    T(pad+13,y+6,"EQUITY CURVE",TText,7,1,"la","eq")
    TR(pad+innerW-10,y+6,"TODAY +2.31   WK +5.40   MO +5.40",TTextDim,7,1,"eqv")
    Sunk(pad+8,y+21,innerW-16,sparkH-29,4,TBg)
    import math
    pts=[0,1.2,0.4,2.1,1.5,3.4,2.8,4.6,3.9,5.4]
    px0,py0=None,None
    for i,v in enumerate(pts):
        X=pad+12+int(i/(len(pts)-1)*(innerW-24));Y=y+25+int((1-v/5.4)*(sparkH-37))
        if px0 is not None:
            cv.Line(OX+px0,OY+py0,OX+X,OY+Y,TBull);cv.Line(OX+px0,OY+py0+1,OX+X,OY+Y+1,TBull)
        px0,py0=X,Y
    y+=sparkH+6
Raised(pad,H-34,innerW,26,5,TPanel,TFlat,True,1);T(pad+innerW//2,H-34+5,"PAUSE TRADING",TText,8,1,"ma")
def ov(a,b):return not(a[2]<=b[0] or b[2]<=a[0] or a[3]<=b[1] or b[3]<=a[1])
bad=[(sp[i][0],sp[j][0]) for i in range(len(sp)) for j in range(i+1,len(sp)) if ov(sp[i][1],sp[j][1])]
print("overlaps:",bad if bad else "NONE")
print(f"used {H-34+26}/{H}")
assert not bad,"OVERLAP"
# corner-ring regression: no wrong-quadrant border pixels inside a panel
bub=0
for (px,py,pw,ph,pr) in PANELS:
    for (cx,cy,sx,sy) in [(px+pr,py+pr,-1,-1),(px+pw-pr-1,py+pr,1,-1),
                          (px+pr,py+ph-pr-1,-1,1),(px+pw-pr-1,py+ph-pr-1,1,1)]:
        for yy in range(cy-pr-1,cy+pr+2):
            for xx in range(cx-pr-1,cx+pr+2):
                if not(0<=xx<cv.w and 0<=yy<cv.h):continue
                dx,dy=xx-cx,yy-cy
                if abs(dx*dx+dy*dy-pr*pr)>pr:continue
                if not(px<xx<px+pw-1 and py<yy<py+ph-1):continue
                if((dx*sx<0)or(dy*sy<0)) and cv.px[xx,yy]==TBorder: bub+=1
print("wrong-quadrant corner pixels:",bub)
assert bub==0,"corner bubbles"
cv.save("docs/hud_tracker_preview.png");print("saved")
