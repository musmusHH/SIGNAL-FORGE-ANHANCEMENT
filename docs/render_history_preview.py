# What the chart keeps after a run: every range, every trade.
import os, math, random
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__))
BG=(9,14,24);PANEL=(16,24,38);EDGE=(38,54,78);CY=(0,214,255)
DIM=(120,140,165);TXT=(226,236,248);BULL=(0,230,160);BEAR=(255,70,102);AMB=(255,206,84)
def f(sz,b=False):
    n="DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/"+n,sz)
    except: return ImageFont.load_default()
W,H=1240,700
img=Image.new("RGB",(W,H),BG);d=ImageDraw.Draw(img)
d.text((26,16),"HISTORY RETENTION  -  the whole run stays on the chart",font=f(20,True),fill=TXT)
d.text((26,46),"Every past range keeps its own box; every closed trade keeps an entry->exit marker.",font=f(12),fill=DIM)

ox,oy,ow,oh=26,80,1188,392
d.rounded_rectangle([ox,oy,ox+ow,oy+oh],9,fill=PANEL,outline=EDGE)
px,py,pw,ph=ox+18,oy+18,ow-36,oh-56
pmin,pmax=4960.0,5080.0
def Y(p): return py+ph-(p-pmin)/(pmax-pmin)*ph

random.seed(11)
# five sessions: (x0,x1 of range, hi, lo, valid, trades, fails, dir)
sessions=[(0.02,0.14,5000,4988,True ,1,0,+1),
          (0.21,0.33,4996,4991,False,0,0, 0),
          (0.40,0.52,5030,5012,True ,2,1,+1),
          (0.59,0.71,5044,5028,True ,0,0, 0),
          (0.78,0.90,5060,5041,True ,1,0,-1)]
# candle backdrop
price=4994.0
for i in range(150):
    x=px+ (i/150.0)*pw
    drift=math.sin(i/14.0)*3 + i*0.30
    o=price+drift; c=o+random.uniform(-2.2,2.4)
    hi=max(o,c)+abs(random.uniform(0,1.6)); lo=min(o,c)-abs(random.uniform(0,1.6))
    col=(36,70,62) if c>=o else (78,38,48)
    d.line([x,Y(hi),x,Y(lo)],fill=col)
    d.rectangle([x-2,Y(max(o,c)),x+2,Y(min(o,c))],fill=col)

for (a,b,hi,lo,valid,trades,fails,dr) in sessions:
    x0,x1=px+a*pw, px+b*pw
    if not valid: col=DIM
    elif trades>0: col=BULL if dr>=0 else BEAR
    else: col=CY
    if trades>0:
        d.rectangle([x0,Y(hi),x1,Y(lo)],fill=(col[0]//7,col[1]//7,col[2]//7))
    # dotted for rejected, solid otherwise
    if valid:
        d.rectangle([x0,Y(hi),x1,Y(lo)],outline=col)
    else:
        for xx in range(int(x0),int(x1),7): d.line([xx,Y(hi),xx+3,Y(hi)],fill=col)
        for xx in range(int(x0),int(x1),7): d.line([xx,Y(lo),xx+3,Y(lo)],fill=col)
        for yy in range(int(Y(hi)),int(Y(lo)),7):
            d.line([x0,yy,x0,yy+3],fill=col); d.line([x1,yy,x1,yy+3],fill=col)
    lbl=f"{(hi-lo)*1000:.0f}p  x{random.uniform(0.6,2.2):.2f}"
    if not valid: lbl+="  SKIP"
    if trades>0:  lbl+=f"  {trades}T"
    if fails>0:   lbl+=f"  {fails}F"
    d.text((x0+2,Y(hi)-13),lbl,font=f(9),fill=col)

# trade markers
trades=[(0.16,4999,0.19,5006,True),(0.55,5029,0.58,5039,True),
        (0.56,5031,0.62,5024,False),(0.93,5057,0.97,5047,True)]
for (a,p1,b,p2,win) in trades:
    x0,y0=px+a*pw,Y(p1); x1,y1=px+b*pw,Y(p2)
    c=BULL if win else BEAR
    if win: d.line([x0,y0,x1,y1],fill=c,width=2)
    else:
        n=14
        for s in range(n):
            if s%2: continue
            xa=x0+(x1-x0)*s/n; ya=y0+(y1-y0)*s/n
            xb=x0+(x1-x0)*(s+1)/n; yb=y0+(y1-y0)*(s+1)/n
            d.line([xa,ya,xb,yb],fill=c,width=2)
    d.polygon([(x0,y0-6),(x0-5,y0+3),(x0+5,y0+3)],fill=c)
    d.line([x1-4,y1-4,x1+4,y1+4],fill=c,width=2); d.line([x1-4,y1+4,x1+4,y1-4],fill=c,width=2)

# legend
ly=oy+oh-26
items=[("traded range (filled)",BULL),("valid, untraded",CY),("rejected by width gate (dotted)",DIM),("losing trade (dashed)",BEAR)]
lx=px
for t,c in items:
    d.rectangle([lx,ly,lx+14,ly+10],outline=c,fill=(c[0]//7,c[1]//7,c[2]//7))
    d.text((lx+20,ly-2),t,font=f(10),fill=DIM); lx+=d.textlength(t,font=f(10))+52

# CSV panel
by=492
d.rounded_rectangle([26,by,W-26,by+186],10,fill=PANEL,outline=EDGE)
d.text((44,by+14),"AND TWO CSV FILES, WRITTEN TO MQL4/Files WHEN THE EA STOPS",font=f(14,True),fill=CY)
d.text((44,by+44),"BKF_ranges_SYMBOL_PERIOD_MAGIC.csv",font=f(12,True),fill=TXT)
d.text((44,by+64),"start, end, high, low, width_points, bars, ratio, valid, trades, failed_breaks, last_dir",font=f(10),fill=DIM)
d.text((44,by+94),"BKF_trades_SYMBOL_PERIOD_MAGIC.csv",font=f(12,True),fill=TXT)
d.text((44,by+114),"ticket, type, lots, open_time, open_price, close_time, close_price, sl, tp,",font=f(10),fill=DIM)
d.text((44,by+130),"stop_points, target_points, profit, swap, commission, net, comment",font=f(10),fill=DIM)
d.text((44,by+156),"Open them in Excel to answer: which ranges got skipped and were they right to be?",font=f(11),fill=AMB)
img.save(os.path.join(HERE,"breakout_history_preview.png"))
print("saved docs/breakout_history_preview.png")
