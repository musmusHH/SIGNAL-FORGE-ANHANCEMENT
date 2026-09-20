# Why v1.01 said NO VALID RANGE, and what v1.02 does instead.
import os, math
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__))
BG=(9,14,24);PANEL=(16,24,38);EDGE=(38,54,78);CY=(0,214,255)
DIM=(120,140,165);TXT=(226,236,248);BULL=(0,230,160);BEAR=(255,70,102);AMB=(255,206,84)
def f(sz,b=False):
    n="DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/"+n,sz)
    except: return ImageFont.load_default()
W,H=1180,700
img=Image.new("RGB",(W,H),BG);d=ImageDraw.Draw(img)
d.text((26,18),"WHY THE PANEL SAID  \u201cNO VALID RANGE\u201d",font=f(20,True),fill=TXT)
d.text((26,48),"The width gate compared a 7-hour session range against ONE M5 bar's ATR. Different scales.",font=f(12),fill=DIM)

# --- old vs new bar chart ---
def block(ox,oy,w,h,title,tc,sub):
    d.rounded_rectangle([ox,oy,ox+w,oy+h],9,fill=PANEL,outline=EDGE)
    d.text((ox+16,oy+12),title,font=f(14,True),fill=tc)
    d.text((ox+16,oy+33),sub,font=f(11),fill=DIM)

atr=0.80; bars=84
ranges=[3,6,9,12,15,18,25,40]
oldmax=6.0*atr
span=atr*math.sqrt(bars)

block(26,86,552,286,"v1.01  BROKEN","#".replace("#","")or BEAR,"width vs 6 x M5 ATR  =  max $%.2f allowed"%oldmax)
block(602,86,552,286,"v1.02  FIXED",BULL,"width vs ATR x sqrt(84) = $%.2f expected travel"%span)
for i,(ox,mode) in enumerate(((26,"old"),(602,"new"))):
    bx,by,bw=ox+16,86+70,552-32
    for j,r in enumerate(ranges):
        y=by+j*25
        if mode=="old": ok = r<=oldmax
        else:
            ratio=r/span; ok = 0.40<=ratio<=3.00 and r>=6.0
        c=BULL if ok else BEAR
        d.text((bx,y),"$%-3d"%r,font=f(11,True),fill=TXT)
        barw=int((r/40.0)*(bw-150))
        d.rectangle([bx+42,y+2,bx+42+max(barw,2),y+13],fill=c)
        lbl = "PASS" if ok else "REJECT"
        d.text((bx+bw-52,y),lbl,font=f(10,True),fill=c)
    # healthy band marker
    hb1=bx+42+int((9/40.0)*(bw-150)); hb2=bx+42+int((18/40.0)*(bw-150))
    d.line([hb1,by-10,hb2,by-10],fill=AMB,width=3)
    d.text((hb1,by-26),"healthy Asian range $9-18",font=f(10),fill=AMB)

# verdict strip
d.rounded_rectangle([26,384,W-26,432],8,fill=(24,12,16),outline=BEAR)
d.text((44,398),"v1.01 rejected EVERY healthy range (0 of 170 combinations passed)  ->  the engine could never arm",font=f(13,True),fill=BEAR)
d.rounded_rectangle([26,442,W-26,490],8,fill=(10,30,24),outline=BULL)
d.text((44,456),"v1.02 accepts 85% of the healthy band, still rejects dead-flat and trending ranges",font=f(13,True),fill=BULL)

# rules
by=506
d.rounded_rectangle([26,by,W-26,by+172],10,fill=PANEL,outline=EDGE)
d.text((44,by+14),"THE NEW TEST",font=f(14,True),fill=CY)
d.text((44,by+40),"ratio  =  range width  /  ( ATR x sqrt(bars the range spans) )",font=f(14,True),fill=TXT)
rows=[("0.40 - 3.00","the ratio must fall in this band - it is scale-free, so SESSION and DONCHIAN use one rule",TXT),
      ("6000 points","new MinRangePoints: an absolute $6 floor, because a proportionate range can still be too",DIM),
      ("","small in dollars to pay for spread and commission. Set 0 to disable.",DIM),
      ("on the panel","the WIDTH row now shows x1.64 (0.40-3.00), and a rejection says TOO TIGHT / TOO WIDE",CY)]
yy=by+70
for tag,txt,c in rows:
    if tag:
        d.rounded_rectangle([44,yy-2,166,yy+20],5,fill=(12,20,32),outline=c)
        tw=d.textlength(tag,font=f(10,True)); d.text((44+(122-tw)/2,yy+3),tag,font=f(10,True),fill=c)
    d.text((182,yy+2),txt,font=f(11),fill=c if c!=DIM else DIM)
    yy+=26
img.save(os.path.join(HERE,"breakout_width_gate_fix.png"))
print("saved docs/breakout_width_gate_fix.png")
