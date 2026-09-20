# The v1.07 gates: range width in POINTS, and the money-defined stop.
# ATR has been removed from the EA entirely, so this replaces the old
# "ratio vs ATR x sqrt(bars)" diagram.
import os
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__))
BG=(9,14,24);PANEL=(16,24,38);EDGE=(38,54,78);CY=(0,214,255)
DIM=(120,140,165);TXT=(226,236,248);BULL=(0,230,160);BEAR=(255,70,102);AMB=(255,206,84)
def f(sz,b=False):
    n="DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/"+n,sz)
    except: return ImageFont.load_default()
W,H=1180,760
img=Image.new("RGB",(W,H),BG);d=ImageDraw.Draw(img)

d.text((26,20),"PRICE-RELATIVE WIDTH GATE  +  MONEY-DEFINED STOP",font=f(20,True),fill=CY)
d.text((26,48),"ATR is gone. The range is judged as a PERCENT OF PRICE; the stop is whatever distance loses the budget at 0.10 lot.",font=f(12),fill=DIM)

def block(x,y,w,h,title,col,sub):
    d.rounded_rectangle([x,y,x+w,y+h],10,fill=PANEL,outline=EDGE,width=2)
    d.text((x+16,y+12),title,font=f(15,True),fill=col)
    d.text((x+16,y+34),sub,font=f(11),fill=DIM)

# ---------- width gate ----------
MINPCT,MAXPCT=0.25,3.00
block(26,86,1128,238,"RANGE WIDTH GATE  -  PERCENT OF PRICE",BULL,
      "accepted band: %.2f%% - %.2f%% of the gold price.  Scale-free: it does not go stale when gold re-rates."%(MINPCT,MAXPCT))
x0,y0=60,164
d.text((x0,y0-24),"range width as % of price",font=f(11),fill=DIM)
SPAN=4.0
scale=1040/SPAN
for t in [x*0.5 for x in range(0,9)]:
    px=x0+t*scale
    d.line([px,y0,px,y0+12],fill=EDGE,width=1)
    d.text((px-12,y0+16),"%.1f%%"%t,font=f(10),fill=DIM)
d.rectangle([x0+MINPCT*scale,y0+34,x0+MAXPCT*scale,y0+74],fill=(0,70,55),outline=BULL,width=2)
d.text((x0+MINPCT*scale+10,y0+46),"ACCEPTED   %.2f%% - %.2f%%"%(MINPCT,MAXPCT),font=f(13,True),fill=BULL)
d.rectangle([x0,y0+34,x0+MINPCT*scale,y0+74],fill=(60,18,26),outline=BEAR,width=2)
d.rectangle([x0+MAXPCT*scale,y0+34,x0+SPAN*scale,y0+74],fill=(60,18,26),outline=BEAR,width=2)
d.text((x0+MAXPCT*scale+10,y0+46),"trend, not a range",font=f(10),fill=BEAR)
# the user's real range
obs=2.29
px=x0+obs*scale
d.line([px,y0+78,px,y0+98],fill=CY,width=3)
d.text((px-116,y0+102),"the REJECTED $99.05 range @ $4324 gold = 2.29%  -> now PASSES",font=f(11,True),fill=CY)
d.text((x0,y0+126),"the old absolute band ($6-$40) was only 0.14%-0.93% at $4324 gold, so it rejected every real session range.",font=f(11),fill=AMB)

# ---------- money stop ----------
block(26,344,1128,392,"MONEY-DEFINED STOP AT 0.10 LOT",CY,"stop distance = risk budget / money-per-point.  0.10 lot on 3-digit gold = $0.01 per point.")
def mpp(l): return l*0.10
def solve(bal,pct=0.5,cap=0.0,minstop=200.0,spread=90,slip=30,stoplevel=0):
    budget=bal*pct/100.0
    if cap>0: budget=min(budget,cap)
    want=budget/mpp(0.10)
    floor=max(minstop,stoplevel+spread+slip+2)
    used=max(want,floor)
    return budget,want,used,used*mpp(0.10),want<floor

hdr=["balance","0.5% budget","stop wanted","stop used","actual loss","actual %","verdict"]
colx=[60,210,360,520,670,830,950]
ty=392
for i,h in enumerate(hdr): d.text((colx[i],ty),h,font=f(11,True),fill=CY)
d.line([60,ty+18,1120,ty+18],fill=EDGE,width=1)
ty+=26
for bal in (157.79,200,300,400,600,1000,2000,5000):
    budget,want,used,loss,over=solve(bal)
    col=AMB if over else BULL
    vals=["$%.2f"%bal,"$%.2f"%budget,"%.0f pts"%want,"%.0f pts"%used,"$%.2f"%loss,"%.2f%%"%(loss/bal*100),
          "floored - still trades" if over else "exact 0.5%"]
    for i,v in enumerate(vals):
        d.text((colx[i],ty),v,font=f(11,True) if i==6 else f(11),fill=col if i>=4 else TXT)
    ty+=24

ty+=10
d.line([60,ty,1120,ty],fill=EDGE,width=1); ty+=14
d.text((60,ty),"THE FLOOR, AND WHY IT IS NOT A BLOCK",font=f(13,True),fill=AMB); ty+=22
for line,col in [
  ("A stop tighter than the spread is hit on the fill. Below ~$400 balance, 0.5% of equity buys a stop",DIM),
  ("narrower than the 90-point spread, so it is widened to MinStopPoints (200) and the trade is STILL TAKEN.",DIM),
  ("The EA never refuses an entry over sizing: AllowRiskOverrun defaults to true and the panel reports the real risk.",BULL),
  ("The structural range stop may only ever TIGHTEN this distance - never widen it. That is what caps the loss.",BULL),
  ("Regression: ticket #17 took a 95,646-point structural stop = $956 on a $429.60 account. Now capped at $2.15.",BEAR)]:
    d.text((60,ty),line,font=f(11),fill=col); ty+=20

out=os.path.join(HERE,"breakout_width_gate.png")
img.save(out)
print("wrote",out)
