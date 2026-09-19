"""Renders the CORE + FILTERS pages using the EA's OWN drawing primitives
(docs/sfcanvas.py), with all geometry parsed out of the .mq4 source.
Asserts: no text overlaps, and no border pixels inside panel interiors."""
import re, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sfcanvas import Canvas, RoundRect
from PIL import ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "Signal Forge PRO XAUUSD M5 EA.mq4"), encoding="utf-8").read()
def grab(pat, d):
    m = re.search(pat, src); return int(m.group(1)) if m else d

W       = grab(r'int W = SC\((\d+)\);', 430)
headerH = grab(r'int headerH = SC\((\d+)\);', 54)
Hc      = grab(r'int pageH = SC\((\d+)\);\s*// CORE', 652)
Hf      = grab(r'if\(gHudPage == 1\) pageH = SC\((\d+)\);', 500)
gaugeH  = grab(r'int gaugeH = SC\((\d+)\);', 126)
frowH   = grab(r'int rowH = SC\((\d+)\);\s*\n\s*for\(int i = 0; i < SF_FILTERS', 27)
biasW   = grab(r'int bW = SC\((\d+)\), bH', 62)
biasH   = grab(r'int bW = SC\(\d+\), bH = SC\((\d+)\);', 17)
biasX   = grab(r'int bX = pad \+ SC\((\d+)\)', 142)
costH   = grab(r'int costH = SC\((\d+)\);', 92)
riskH   = grab(r'int riskH = SC\((\d+)\);', 112)
tkH     = grab(r'int tkH = SC\((\d+)\);', 74)
print(f"from source: W={W} core={Hc} filters={Hf} frowH={frowH} bias={biasW}x{biasH}@{biasX}")

TBg=(12,18,34);TBg2=(20,30,54);TPanel=(28,40,72);TPanelHi=(40,56,98)
TBorder=(86,116,190);TAccent=(0,245,255);TAccent2=(178,110,255)
TText=(240,248,255);TTextDim=(158,180,220);TBull=(0,255,170);TBear=(255,60,110)
TFlat=(255,215,70);TWarn=(255,160,50);TGridC=(58,80,132)
TLite=(110,146,225);TDark=(5,8,16);TBullDeep=(0,104,74);TBearDeep=(128,20,50);TGreyDeep=(86,92,104)
def SC(v): return v
DJ="/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
def F(sz,b=0):
    p=DJ%("-Bold" if b else "")
    return ImageFont.truetype(p,sz) if os.path.exists(p) else ImageFont.load_default()

class Page:
    def __init__(self,H):
        self.H=H; self.cv=Canvas(W+40,H+40); self.OX=20; self.OY=20
        self.spans=[]; self.panels=[]
    def rr(self,x,y,w,h,r,f,b=None,db=True):
        RoundRect(self.cv,x+self.OX,y+self.OY,w,h,r,f,b if b else f,db)
    def raised(self,x,y,w,h,r,f,e,sh=True,dep=2):
        if sh:
            for d in range(dep+1,0,-1):
                RoundRect(self.cv,x+self.OX+d,y+self.OY+d,w,h,r,(0,0,0,70//d),(0,0,0,70//d),False)
        self.rr(x,y,w,h,r,f,e)
        cv,OX,OY=self.cv,self.OX,self.OY
        cv.Line(x+OX+r,y+OY+1,x+OX+w-r-1,y+OY+1,TLite)
        cv.Line(x+OX+1,y+OY+r,x+OX+1,y+OY+h-r-1,TLite)
        cv.Line(x+OX+r,y+OY+h-2,x+OX+w-r-1,y+OY+h-2,TDark)
        cv.Line(x+OX+w-2,y+OY+r,x+OX+w-2,y+OY+h-r-1,TDark)
        self.panels.append((x+OX,y+OY,w,h,r))
    def sunk(self,x,y,w,h,r,f):
        self.rr(x,y,w,h,r,f,TDark)
        self.cv.Line(x+self.OX+r,y+self.OY+h-2,x+self.OX+w-r-1,y+self.OY+h-2,TLite)
    def spine(self,x,y,h,c):
        self.cv.FillRectangle(x+self.OX,y+self.OY,x+self.OX+2,y+self.OY+h,c)
    def dot(self,x,y,r,on,onC,offC):
        self.cv.FillCircle(x+self.OX,y+self.OY,r,onC if on else offC)
        self.cv.Circle(x+self.OX,y+self.OY,r+1,onC if on else TGridC)
    def meter_graded(self,x,y,w,h,v,strong):
        def mix(a,b,t):
            t=max(0.0,min(1.0,t)); return tuple(int(a[k]+(b[k]-a[k])*t) for k in range(3))
        c = mix(TWarn,TAccent,v/0.5) if v<0.5 else mix(TAccent,strong,(v-0.5)/0.5)
        self.meter(x,y,w,h,v,c)
    def meter(self,x,y,w,h,v,fc):
        self.sunk(x,y,w,h,h//2,TBg)
        fw=int(max(0.0,min(1.0,v))*(w-2))
        if fw>2: self.rr(x+1,y+1,fw,h-2,(h-2)//2,fc,fc,False)
    def finish(self):
        self.d=ImageDraw.Draw(self.cv.img)
    def T(self,x,y,s,c,sz=8,b=0,anchor="la",tag=None):
        f=F(int(sz*1.45),b); self.d.text((x+self.OX,y+self.OY),s,fill=c,font=f,anchor=anchor)
        if tag: self.spans.append((tag,self.d.textbbox((x+self.OX,y+self.OY),s,font=f,anchor=anchor)))
    def TR(self,x,y,s,c,sz=8,b=0,tag=None): self.T(x,y,s,c,sz,b,"ra",tag)
    def TVC(self,x,y,h,s,c,sz=8,b=0,tag=None):
        f=F(int(sz*1.45),b); bb=self.d.textbbox((0,0),s,font=f)
        self.T(x,y+(h-(bb[3]-bb[1]))//2-bb[1],s,c,sz,b,"la",tag)
    def TCVC(self,cx,y,h,s,c,sz=8,b=0,tag=None):
        f=F(int(sz*1.45),b); bb=self.d.textbbox((0,0),s,font=f)
        self.T(cx,y+(h-(bb[3]-bb[1]))//2-bb[1],s,c,sz,b,"ma",tag)
    def TC(self,x,y,s,c,sz=8,b=0,tag=None): self.T(x,y,s,c,sz,b,"ma",tag)
    def check(self,label):
        def ov(a,b): return not(a[2]<=b[0] or b[2]<=a[0] or a[3]<=b[1] or b[3]<=a[1])
        bad=[(self.spans[i][0],self.spans[j][0])
             for i in range(len(self.spans)) for j in range(i+1,len(self.spans))
             if ov(self.spans[i][1],self.spans[j][1])]
        print(f"  {label}: text overlaps ->", bad if bad else "NONE")
        assert not bad, f"{label} OVERLAP {bad}"

def header(p, tabs, active):
    p.raised(0,0,W,p.H,SC(12),TBg,TBorder,False,0)
    p.cv.FillRectangle(3+p.OX,3+p.OY,W-4+p.OX,headerH-3+p.OY,TPanelHi)
    p.cv.Line(SC(10)+p.OX,headerH-1+p.OY,W-SC(10)+p.OX,headerH-1+p.OY,TAccent)
    hx,hy=SC(14),SC(10)
    p.cv.FillCircle(hx+SC(10)+p.OX,hy+SC(14)+p.OY,SC(11),TAccent2)
    p.cv.FillCircle(hx+SC(10)+p.OX,hy+SC(14)+p.OY,SC(7),TBg)
    p.cv.FillCircle(hx+SC(10)+p.OX,hy+SC(14)+p.OY,SC(3),TAccent)
    pillW,pillH=SC(92),SC(22); pillX=W-pillW-SC(12)
    colW=SC(24); colX=pillX-colW-SC(7)
    p.raised(pillX,hy+SC(3),pillW,pillH,SC(10),TPanelHi,TBull,True,1)
    p.raised(colX,hy+SC(3),colW,pillH,SC(5),TPanel,TAccent,True,1)
    p.finish_hdr=(hx,hy,pillX,pillW,colX,colW)

def draw_header_text(p):
    hx,hy,pillX,pillW,colX,colW=p.finish_hdr
    txtX=hx+SC(28); mark="SIGNAL FORGE"
    f=F(int(11*1.45),1); markW=p.d.textlength(mark,font=f)
    p.T(txtX,hy,mark,TText,11,1,"la","mark")
    badgeW,badgeH=SC(32),SC(14); badgeX=int(txtX+markW+SC(7))
    if badgeX+badgeW < colX-SC(6):
        p.rr(badgeX,hy+SC(2),badgeW,badgeH,SC(3),TAccent,TAccent)
        p.TC(badgeX+badgeW//2,hy+SC(2),"PRO",(6,10,18),7,1,"pro")
    p.T(txtX,hy+SC(18),"XAUUSDr  ·  M5  ·  RAW  ·  v2.01",TTextDim,7,0,"la","sub")
    p.dot(pillX+SC(12),hy+SC(14),SC(4),True,TBull,TGridC)
    p.TC(pillX+SC(13)+(pillW-SC(13))//2,hy+SC(6),"ARMED",TBull,7,1,"state")
    p.TC(colX+colW//2,hy+SC(6),"-",TAccent,8,1,"col")

def tabs_row(p,y,active):
    pad=SC(12); innerW=W-pad*2; tabW=(innerW-SC(16))//3
    for i,l in enumerate(["CORE","FILTERS","TRACKER"]):
        bx=pad+(tabW+SC(8))*i; a=(i==active)
        p.raised(bx,y,tabW,SC(24),SC(5),TAccent if a else TPanel,TAccent if a else TBorder,True,1)
    return pad,innerW,tabW

CHIPS=[]
def chip(p,x,y,w,h,lab,val,vc,ac,tag):
    p.raised(x,y,w,h,SC(6),TPanel,TBorder); p.spine(x+SC(3),y+SC(5),h-SC(10),ac)
    CHIPS.append((p,x,y,lab,val,vc,tag))
def chip_text():
    for (pg,x,y,lab,val,vc,tag) in CHIPS:
        pg.T(x+SC(12),y+SC(5),lab,TTextDim,7,1,"la",tag+"l")
        pg.T(x+SC(12),y+SC(16),val,vc,10,1,"la",tag+"v")

# ---------------- CORE ----------------
p=Page(Hc); header(p,3,0)
pad,innerW,tabW=tabs_row(p,headerH+SC(6),0)
y=headerH+SC(6)+SC(32)
p.raised(pad,y,innerW,SC(gaugeH),SC(10),TPanel,TBorder); p.spine(pad+SC(4),y+SC(7),SC(13),TAccent)
gy=y; y+=SC(gaugeH)+SC(8)
p.raised(pad,y,innerW,SC(costH),SC(10),TPanel,TBorder); p.spine(pad+SC(4),y+SC(7),SC(13),TAccent2)
cy_=y; p.meter(pad+SC(12),y+SC(72),innerW-SC(24),SC(8),0.20,TBull); y+=SC(costH)+SC(8)
chw=(innerW-SC(8))//2
chip(p,pad,y,chw,SC(40),"BALANCE","$157.79",TText,TAccent,"c0")
chip(p,pad+chw+SC(8),y,chw,SC(40),"EQUITY","$157.79",TAccent,TAccent2,"c1")
y+=SC(46)
chip(p,pad,y,chw,SC(40),"FLOATING P/L","+0.00",TTextDim,TBull,"c2")
chip(p,pad+chw+SC(8),y,chw,SC(40),"DAY P/L","+0.00%",TTextDim,TFlat,"c3")
y+=SC(46)
p.raised(pad,y,innerW,SC(riskH),SC(10),TPanel,TBorder); p.spine(pad+SC(4),y+SC(7),SC(13),TFlat)
ry=y
p.meter(pad+SC(12),y+SC(39),innerW-SC(24),SC(7),0.0,TFlat)
p.meter(pad+SC(12),y+SC(67),innerW-SC(24),SC(7),0.0,TBull)
p.meter(pad+SC(12),y+SC(95),innerW-SC(24),SC(7),0.33,TAccent2)
y+=SC(riskH)+SC(8)
p.raised(pad,y,innerW,SC(tkH),SC(10),TPanel,TBorder)
ty=y; p.rr(pad+SC(10),y+SC(8),SC(54),SC(18),SC(4),TBull,TBull); y+=SC(tkH)+SC(8)
by=Hc-SC(34); bw=(innerW-SC(16))//3
for i,(l,c) in enumerate([("PAUSE",TFlat),("CLOSE ALL",TBear),("OVERLAY",TAccent2)]):
    p.raised(pad+(bw+SC(8))*i,by,bw,SC(26),SC(5),TPanel,c,True,1)
p.finish(); draw_header_text(p); chip_text()
for i,l in enumerate(["CORE","FILTERS","TRACKER"]):
    bx=pad+(tabW+SC(8))*i
    p.TC(bx+tabW//2,headerH+SC(6)+SC(5),l,(6,10,18) if i==0 else TText,8,1,f"tab{i}")
p.T(pad+SC(13),gy+SC(6),"CONFLUENCE CONVICTION",TText,8,1,"la","g1")
p.TR(pad+innerW-SC(12),gy+SC(7),"HTF FLAT",TTextDim,7,1,"g2")
p.T(pad+SC(13),gy+SC(20),"ARM ±62",TAccent,7,0,"la","g3")
p.TC(pad+innerW//2,gy+SC(52),"+0",TFlat,19,1,"g4")
p.TC(pad+innerW//2,gy+SC(84),"NEUTRAL",TFlat,8,1,"g5")
p.T(pad+SC(14),gy+SC(104),"-100",TTextDim,7,0,"la","g6")
p.TR(pad+innerW-SC(14),gy+SC(104),"+100",TTextDim,7,0,"g7")
p.T(pad+SC(13),cy_+SC(6),"COST INTELLIGENCE  ·  RAW SPREAD",TText,8,1,"la","k1")
col=innerW//3
for i,(l,v,c) in enumerate([("SPREAD","90 pts",TText),("COMMISSION","70 pts",TText),("ROUND TURN","160 pts",TFlat)]):
    p.T(pad+SC(12)+i*col,cy_+SC(26),l,TTextDim,7,0,"la",f"k{i}a")
    p.T(pad+SC(12)+i*col,cy_+SC(37),v,c,10,1,"la",f"k{i}b")
p.T(pad+SC(12),cy_+SC(57),"COST / ATR(14)",TTextDim,7,0,"la","k9")
p.TR(pad+innerW-SC(12),cy_+SC(57),"20.0% of ATR",TFlat,7,1,"k10")
p.T(pad+SC(13),ry+SC(6),"RISK CONSOLE",TText,8,1,"la","r1")
for i,(l,v) in enumerate([("DAILY LOSS BUDGET","0%"),("DAILY TARGET","0%")]):
    p.T(pad+SC(12),ry+SC(26)+i*SC(28),l,TTextDim,7,0,"la",f"r{i}a")
    p.TR(pad+innerW-SC(12),ry+SC(26)+i*SC(28),v,TTextDim,7,1,f"r{i}b")
p.T(pad+SC(12),ry+SC(82),"TRADES TODAY  2 / 6",TTextDim,7,0,"la","r5")
p.TR(pad+innerW-SC(12),ry+SC(82),"STREAK 0L",TTextDim,7,1,"r6")
p.TC(pad+SC(10)+SC(27),ty+SC(11),"FLAT",(6,10,18),7,1,"t1")
p.T(pad+SC(72),ty+SC(10),"no position",TTextDim,8,0,"la","t2")
for i,l in enumerate(["PAUSE","CLOSE ALL","OVERLAY"]):
    p.TC(pad+(bw+SC(8))*i+bw//2,by+SC(6),l,TText,8,1,f"b{i}")
p.check("CORE")
p.cv.save(os.path.join(ROOT,"docs/hud_core_preview.png"))

# ---------------- FILTERS ----------------
q=Page(Hf); header(q,3,1)
pad,innerW,tabW=tabs_row(q,headerH+SC(6),1)
y=headerH+SC(6)+SC(32)
q.sunk(pad,y,innerW,SC(26),SC(6),TBg2); hdry=y; y+=SC(30)
NAMES=["RSI","MACD","SUPERTREND","EMA CROSS","ADX / DI","HTF BIAS","STRUCTURE","VWAP"]
WTS=[1.5,1.5,3.0,2.0,2.0,2.5,2.0,1.5]
BIAS=["BULLISH","FLAT","BULLISH","BEARISH","FLAT","BULLISH","BEARISH","FLAT"]
rowH=SC(frowH); rows=[]
for i,n in enumerate(NAMES):
    if y+rowH > Hf-SC(46): break
    bg=TPanel if i%2==0 else TBg2
    q.rr(pad,y,innerW,rowH-SC(3),SC(4),bg,bg,False)
    q.spine(pad+1,y+SC(3),rowH-SC(9),{"FLAT":TFlat,"BULLISH":TBull,"BEARISH":TBear}[BIAS[i]])
    q.dot(pad+SC(12),y+SC(11),SC(3),True,TAccent,TGridC)
    cellH=rowH-SC(3)
    bH=SC(biasH); bY=y+(cellH-bH)//2
    st=BIAS[i]
    bg={"FLAT":TGreyDeep,"BULLISH":TBullDeep,"BEARISH":TBearDeep}[st]
    ed={"FLAT":TLite,"BULLISH":TBull,"BEARISH":TBear}[st]
    q.raised(pad+SC(biasX),bY,SC(biasW),bH,SC(3),bg,ed,True,1)
    share=WTS[i]/sum(WTS); norm=min(1.0,share*2.5)
    strong={"FLAT":TFlat,"BULLISH":TBull,"BEARISH":TBear}[st]
    q.meter_graded(pad+SC(248),y+(cellH-SC(7))//2,innerW-SC(260),SC(7),norm,strong)
    rows.append((y,n,WTS[i],st,bY,bH)); y+=rowH
fy=Hf-SC(40); bw2=(innerW-SC(8))//2
q.raised(pad,fy,bw2,SC(26),SC(5),TPanel,TAccent,True,1)
q.raised(pad+bw2+SC(8),fy,bw2,SC(26),SC(5),TPanel,TFlat,True,1)
q.finish(); draw_header_text(q)
for i,l in enumerate(["CORE","FILTERS","TRACKER"]):
    bx=pad+(tabW+SC(8))*i
    q.TC(bx+tabW//2,headerH+SC(6)+SC(5),l,(6,10,18) if i==1 else TText,8,1,f"tab{i}")
q.T(pad+SC(10),hdry+SC(8),"FILTER",TAccent,7,1,"la","h0")
q.T(pad+SC(biasX),hdry+SC(8),"BIAS",TAccent,7,1,"la","h1")
q.T(pad+SC(212),hdry+SC(8),"WGT",TAccent,7,1,"la","h2")
q.TR(pad+innerW-SC(10),hdry+SC(9),"CONTRIBUTION",TAccent,7,1,"h3")
for i,(ry2,n,w,st,bY,bH) in enumerate(rows):
    cellH=rowH-SC(3)
    q.TVC(pad+SC(22),ry2,cellH,n,TText,7,1,f"n{i}")
    q.TCVC(pad+SC(biasX)+SC(biasW)//2,bY,bH,st,(255,255,255),7,1,f"bi{i}")
    q.TVC(pad+SC(216),ry2,cellH,f"{w:.1f}",TText,7,1,f"w{i}")
q.TC(pad+bw2//2,fy+SC(6),"ACTIVE ONLY",TText,8,1,"f1")
q.TC(pad+bw2+SC(8)+bw2//2,fy+SC(6),"PAUSE",TText,8,1,"f2")
q.check("FILTERS")
q.cv.save(os.path.join(ROOT,"docs/hud_filters_preview.png"))

# Structural assertion: each rounded corner must be a QUARTER arc, not a ring.
# For corner centre (cx,cy) with radius r, arc pixels may only occupy the
# outward quadrant. A pixel on the ring in any other quadrant is the "bubble".
def bubble_scan(page,name):
    bad=0
    for (px,py,pw,ph,pr) in page.panels:
        if pr<3: continue
        corners=[(px+pr,py+pr,-1,-1),(px+pw-pr-1,py+pr,1,-1),
                 (px+pr,py+ph-pr-1,-1,1),(px+pw-pr-1,py+ph-pr-1,1,1)]
        for (cx,cy,sx,sy) in corners:
            for yy in range(cy-pr-1,cy+pr+2):
                for xx in range(cx-pr-1,cx+pr+2):
                    if not (0<=xx<page.cv.w and 0<=yy<page.cv.h): continue
                    dx,dy=xx-cx,yy-cy
                    d2=dx*dx+dy*dy
                    if abs(d2-pr*pr) > pr:      # not on the ring
                        continue
                    # ignore the straight edges: only STRICTLY interior pixels
                    # can be part of a spurious ring
                    if not (px < xx < px+pw-1 and py < yy < py+ph-1):
                        continue
                    wrong = (dx*sx < 0) or (dy*sy < 0)   # opposite quadrant
                    if wrong and page.cv.px[xx,yy]==TBorder:
                        bad+=1
    print(f"  {name}: wrong-quadrant corner pixels ->",bad)
    return bad
tot=bubble_scan(p,"CORE")+bubble_scan(q,"FILTERS")
assert tot==0,"corner bubbles present"
print("saved core + filters")
