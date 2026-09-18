# Extract the SC() geometry constants straight from the .mq4 so the preview
# can never drift from the shipped source.
import re,math,os
from PIL import Image,ImageDraw,ImageFont
src=open("Signal Forge PRO XAUUSD M5 EA.mq4",encoding='utf-8').read()
def grab(pat,default):
    m=re.search(pat,src)
    return int(m.group(1)) if m else default
Hc   = grab(r'int H = gHudCollapsed \? headerH \+ SC\(8\) : SC\((\d+)\);',640)
gaugeH=grab(r'int gaugeH = SC\((\d+)\);',112)
costH =grab(r'int costH = SC\((\d+)\);',88)
riskH =grab(r'int riskH = SC\((\d+)\);',96)
tkH   =grab(r'int tkH = SC\((\d+)\);',74)
proX  =grab(r'int badgeX = hx \+ SC\((\d+)\)',146)
print(f"from source: H={Hc} gauge={gaugeH} cost={costH} risk={riskH} ticket={tkH} proX={proX}")

SCALE=100
def SC(v): return round(v*SCALE/100)
TBg=(9,13,24);TPanel=(17,24,43);TPanelHi=(25,35,60);TBorder=(52,72,120)
TAccent=(0,229,255);TAccent2=(150,100,255);TText=(226,236,252);TTextDim=(126,146,182)
TBull=(0,240,176);TBear=(255,72,104);TFlat=(255,206,84);TGridC=(38,52,86)
DJ="/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
def font(sz,b=0):
    p=DJ%("-Bold" if b else "")
    return ImageFont.truetype(p,sz) if os.path.exists(p) else ImageFont.load_default()
W=SC(430);headerH=SC(54);H=SC(Hc)
img=Image.new("RGB",(W+40,H+40),(8,11,20));d=ImageDraw.Draw(img);OX,OY=20,20
def R(x,y,w,h,r,f,b=None): d.rounded_rectangle([OX+x,OY+y,OX+x+w-1,OY+y+h-1],radius=r,fill=f,outline=b)
def T(x,y,s,c,sz=8,b=0,a="la"): d.text((OX+x,OY+y),s,fill=c,font=font(int(sz*1.45),b),anchor=a)
def TC(x,y,s,c,sz=8,b=0): T(x,y,s,c,sz,b,"ma")
def TR(x,y,s,c,sz=8,b=0): T(x,y,s,c,sz,b,"ra")
def M(x,y,w,h,p,f,t):
    p=max(0,min(1,p));R(x,y,w,h,h//2,t)
    if p>0:R(x,y,max(h,int(w*p)),h,h//2,f)
def bbox(x,y,s,sz,anchor="la"):
    return d.textbbox((OX+x,OY+y),s,font=font(int(sz*1.45)),anchor=anchor)
spans=[]
def track(tag,x,y,s,sz,anchor="la"): spans.append((tag,bbox(x,y,s,sz,anchor)))

R(0,0,W,H,SC(12),TBg,TBorder); d.rectangle([OX+2,OY+2,OX+W-3,OY+headerH-3],fill=TPanel)
hx,hy=SC(14),SC(10)
d.ellipse([OX+hx-1,OY+hy+3,OX+hx+21,OY+hy+25],fill=TAccent2)
d.ellipse([OX+hx+3,OY+hy+7,OX+hx+17,OY+hy+21],fill=TBg)
d.ellipse([OX+hx+7,OY+hy+11,OX+hx+13,OY+hy+17],fill=TAccent)
T(hx+SC(28),hy,"SIGNAL FORGE",TText,11,1); track("wordmark",hx+SC(28),hy,"SIGNAL FORGE",11)
bX=hx+SC(proX);bW=SC(34);bH=SC(15)
R(bX,hy+SC(2),bW,bH,SC(3),TAccent,TAccent)
T(bX+bW//2,hy+SC(3),"PRO",(6,10,18),7,1,"ma")
spans.append(("PRObadge",(OX+bX,OY+hy+SC(2),OX+bX+bW,OY+hy+SC(2)+bH)))
T(hx+SC(28),hy+SC(18),"XAUUSD  ·  M5  ·  EXNESS RAW  ·  v2.00",TTextDim,7)
pillW=SC(96); R(W-pillW-SC(14),hy+SC(2),pillW,SC(24),SC(11),TPanelHi,TBull)
d.ellipse([OX+W-pillW-SC(14)+SC(9),OY+hy+SC(10),OX+W-pillW-SC(14)+SC(17),OY+hy+SC(18)],fill=TBull)
TC(W-pillW//2-SC(8),hy+SC(7),"ARMED",TBull,7,1)
R(W-pillW-SC(46),hy+SC(2),SC(26),SC(24),SC(5),TPanel,TBorder);TC(W-pillW-SC(46)+SC(13),hy+SC(8),"–",TText,8,1)
y=headerH+SC(6);pad=SC(12);innerW=W-pad*2;tabW=(innerW-SC(16))//3
for i,(l,a) in enumerate([("CORE",1),("FILTERS",0),("JOURNAL",0)]):
    bx=pad+(tabW+SC(8))*i;R(bx,y,tabW,SC(24),SC(5),TAccent if a else TPanel,TAccent if a else TBorder)
    TC(bx+tabW//2,y+SC(24)//2-SC(7),l,(6,10,18) if a else TText,8,1)
y+=SC(32)
R(pad,y,innerW,SC(gaugeH),SC(10),TPanel,TBorder)
T(pad+SC(12),y+SC(8),"CONFLUENCE CONVICTION",TTextDim,7,1)
cx=pad+innerW//2;cy=y+SC(gaugeH)-SC(18);radius=SC(58);score=74.0;col=TBull
for deg in range(180,361):
    rad=math.radians(deg);val=-100+(deg-180)/180*200
    lit=(0<=val<=score);c=col if lit else TGridC
    for t in range(SC(7)):
        d.point((OX+cx+round(math.cos(rad)*(radius-t)),OY+cy+round(math.sin(rad)*(radius-t))),fill=c)
d.line([OX+cx,OY+cy-radius,OX+cx,OY+cy-radius+SC(9)],fill=TTextDim)
nrad=math.radians(180+(score+100)/200*180)
d.line([OX+cx,OY+cy,OX+cx+round(math.cos(nrad)*(radius-SC(11))),OY+cy+round(math.sin(nrad)*(radius-SC(11)))],fill=col,width=2)
d.ellipse([OX+cx-SC(4),OY+cy-SC(4),OX+cx+SC(4),OY+cy+SC(4)],fill=col)
T(cx,cy-SC(48),"+74",col,19,1,"ma"); track("score",cx,cy-SC(48),"+74",19,"ma")
T(cx,cy-SC(19),"LONG",col,8,1,"ma"); track("dir",cx,cy-SC(19),"LONG",8,"ma")
T(pad+SC(14),cy-SC(6),"-100",TTextDim,7);TR(pad+innerW-SC(14),cy-SC(6),"+100",TTextDim,7)
T(pad+SC(12),y+SC(22),"ARM ±62",TAccent,7);TR(pad+innerW-SC(12),y+SC(22),"HTF UP",TBull,7,1)
y+=SC(gaugeH)+SC(8)
R(pad,y,innerW,SC(costH),SC(10),TPanel,TBorder)
T(pad+SC(12),y+SC(8),"COST INTELLIGENCE  ·  RAW SPREAD MODEL",TTextDim,7,1)
c3=innerW//3
for i,(l,v,c) in enumerate([("SPREAD","24 pts",TText),("COMMISSION","70 pts",TText),("ROUND TURN","94 pts",TBull)]):
    T(pad+SC(12)+c3*i,y+SC(26),l,TTextDim,7);T(pad+SC(12)+c3*i,y+SC(37),v,c,10,1)
T(pad+SC(12),y+SC(57),"COST / ATR(14)",TTextDim,7); track("costlbl",pad+SC(12),y+SC(57),"COST / ATR(14)",7)
TR(pad+innerW-SC(12),y+SC(57),"8.4% of ATR",TBull,7,1)
M(pad+SC(12),y+SC(72),innerW-SC(24),SC(8),0.336,TBull,TGridC); spans.append(("costmeter",(OX+pad+SC(12),OY+y+SC(72),OX+pad+SC(12)+innerW-SC(24),OY+y+SC(72)+SC(8))))
y+=SC(costH)+SC(8)
chipH=SC(40);chipW=(innerW-SC(8))//2
def chip(x,y,w,h,l,v,vc,ac):
    R(x,y,w,h,SC(6),TPanel,TBorder);d.rectangle([OX+x+SC(2),OY+y+SC(5),OX+x+SC(4),OY+y+h-SC(5)],fill=ac)
    T(x+SC(10),y+SC(5),l,TTextDim,7);T(x+SC(10),y+SC(16),v,vc,9,1)
chip(pad,y,chipW,chipH,"BALANCE","$200.00",TText,TAccent);chip(pad+chipW+SC(8),y,chipW,chipH,"EQUITY","$203.41",TBull,TAccent2)
y+=chipH+SC(6)
chip(pad,y,chipW,chipH,"FLOATING P/L","+3.41",TBull,TBull);chip(pad+chipW+SC(8),y,chipW,chipH,"DAY P/L","+1.70%",TBull,TAccent)
y+=chipH+SC(8)
R(pad,y,innerW,SC(riskH),SC(10),TPanel,TBorder)
T(pad+SC(12),y+SC(8),"RISK CONSOLE",TTextDim,7,1)
T(pad+SC(12),y+SC(26),"DAILY LOSS BUDGET",TTextDim,7);TR(pad+innerW-SC(12),y+SC(26),"0%",TText,7,1)
track("r1",pad+SC(12),y+SC(26),"DAILY LOSS BUDGET",7)
M(pad+SC(12),y+SC(39),innerW-SC(24),SC(7),0.0,TFlat,TGridC);spans.append(("m1",(OX+pad+SC(12),OY+y+SC(39),OX+pad+innerW-SC(12),OY+y+SC(39)+SC(7))))
T(pad+SC(12),y+SC(54),"DAILY TARGET",TTextDim,7);TR(pad+innerW-SC(12),y+SC(54),"28%",TBull,7,1)
track("r2",pad+SC(12),y+SC(54),"DAILY TARGET",7)
M(pad+SC(12),y+SC(67),innerW-SC(24),SC(7),0.28,TBull,TGridC);spans.append(("m2",(OX+pad+SC(12),OY+y+SC(67),OX+pad+innerW-SC(12),OY+y+SC(67)+SC(7))))
T(pad+SC(12),y+SC(82),"TRADES TODAY  2 / 6",TTextDim,7);TR(pad+innerW-SC(12),y+SC(82),"STREAK 0L",TTextDim,7,1)
track("r3",pad+SC(12),y+SC(82),"TRADES TODAY  2 / 6",7)
M(pad+SC(12),y+SC(95),innerW-SC(24),SC(7),2/6,TAccent2,TGridC);spans.append(("m3",(OX+pad+SC(12),OY+y+SC(95),OX+pad+innerW-SC(12),OY+y+SC(95)+SC(7))))
y+=SC(riskH)+SC(8)
R(pad,y,innerW,SC(tkH),SC(10),TPanel,TBorder)
R(pad+SC(10),y+SC(10),SC(56),SC(20),SC(5),TBull,TBull);TC(pad+SC(38),y+SC(13),"LONG",(6,10,18),8,1)
T(pad+SC(74),y+SC(12),"0.01 lots @ 3912.450",TText,8,1);TR(pad+innerW-SC(12),y+SC(11),"+3.41",TBull,11,1)
cc=(innerW-SC(20))//3
for i,(l,v,c) in enumerate([("SL","3897.180",TBear),("TP","3937.600",TBull),("BREAK-EVEN","3912.544",TAccent)]):
    T(pad+SC(12)+cc*i,y+SC(38),l,TTextDim,7);T(pad+SC(12)+cc*i,y+SC(48),v,c,8)
y+=SC(tkH)+SC(8)
bw=(innerW-SC(16))//3
for i,(l,c) in enumerate([("PAUSE",TFlat),("CLOSE ALL",TBear),("OVERLAY",TAccent2)]):
    bx=pad+(bw+SC(8))*i;R(bx,y,bw,SC(26),SC(5),TAccent2 if i==2 else TPanel,c)
    TC(bx+bw//2,y+SC(26)//2-SC(7),l,(6,10,18) if i==2 else TText,8,1)
bottom=y+SC(26)
def ov(a,b): return not(a[2]<=b[0] or b[2]<=a[0] or a[3]<=b[1] or b[3]<=a[1])
bad=[(spans[i][0],spans[j][0]) for i in range(len(spans)) for j in range(i+1,len(spans)) if ov(spans[i][1],spans[j][1])]
print("overlaps:",bad if bad else "NONE")
print(f"used {bottom}/{H}px, slack {H-bottom}")
assert not bad and bottom<=H
img.save("docs/hud_core_preview.png");print("saved")
