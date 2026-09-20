# Draws the two re-entry cases the user specified, straight from the rules in
# ReEntryResult(): CASE A = closes back inside -> re-arm; CASE B = wick back
# inside but closes outside -> immediate re-entry.
import os
from PIL import Image, ImageDraw, ImageFont
HERE = os.path.dirname(os.path.abspath(__file__))

BG=(9,14,24); PANEL=(16,24,38); EDGE=(38,54,78); CY=(0,214,255)
DIM=(120,140,165); TXT=(226,236,248); BULL=(0,230,160); BEAR=(255,70,102)
AMB=(255,206,84)

def f(sz,b=False):
    for n in (("DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"),):
        for d in ("/usr/share/fonts/truetype/dejavu/",):
            try: return ImageFont.truetype(d+n,sz)
            except: pass
    return ImageFont.load_default()

HIGH,LOW,BUF = 2650.0,2642.0,2.0
UPPER,LOWER = HIGH+BUF, LOW-BUF

W,H=1180,684
img=Image.new("RGB",(W,H),BG); d=ImageDraw.Draw(img)

def py(price,top,bot,pmin,pmax):
    return bot-(price-pmin)/(pmax-pmin)*(bot-top)

def panel(x,y,w,h,title,sub,subc):
    d.rounded_rectangle([x,y,x+w,y+h],8,fill=PANEL,outline=EDGE)
    d.text((x+14,y+10),title,font=f(15,True),fill=CY)
    d.text((x+14,y+32),sub,font=f(11),fill=subc)

def scene(ox,oy,w,h,title,verdict,vc,bars,note):
    panel(ox,oy,w,h,title,note,DIM)
    cx,cy,cw,ch = ox+14, oy+62, w-28, h-132
    pmin,pmax = 2635.0, 2661.0
    yH  = py(HIGH ,cy,cy+ch,pmin,pmax); yL = py(LOW  ,cy,cy+ch,pmin,pmax)
    yU  = py(UPPER,cy,cy+ch,pmin,pmax); yD = py(LOWER,cy,cy+ch,pmin,pmax)
    # range box
    d.rectangle([cx,yH,cx+cw,yL],fill=(18,40,58),outline=(0,150,190))
    d.text((cx+cw-132,(yH+yL)/2-7),"RANGE %.0f - %.0f"%(LOW,HIGH),font=f(10),fill=(0,190,225))
    # trigger lines
    for yy,lbl,c in ((yU,"TRIGGER %.0f"%UPPER,AMB),(yD,"TRIGGER %.0f"%LOWER,AMB)):
        for xx in range(int(cx),int(cx+cw),9): d.line([xx,yy,xx+5,yy],fill=c)
        d.text((cx+2,yy-15),lbl,font=f(10),fill=c)
    # candles
    n=len(bars); step=cw/(n+1)
    for i,(o,hi,lo,c,tag) in enumerate(bars):
        x=cx+step*(i+1); bw=step*0.34
        col = BULL if c>=o else BEAR
        d.line([x,py(hi,cy,cy+ch,pmin,pmax),x,py(lo,cy,cy+ch,pmin,pmax)],fill=col,width=2)
        y1=py(max(o,c),cy,cy+ch,pmin,pmax); y2=py(min(o,c),cy,cy+ch,pmin,pmax)
        d.rectangle([x-bw,y1,x+bw,max(y2,y1+2)],fill=col,outline=col)
        if tag:
            d.multiline_text((x-bw-10,cy+ch+8),tag,font=f(10,True),fill=TXT,spacing=2)
    # verdict
    vy=oy+h-30
    d.rounded_rectangle([ox+14,vy-6,ox+w-14,vy+20],6,fill=(12,20,32),outline=vc)
    tw=d.textlength(verdict,font=f(12,True))
    d.text((ox+(w-tw)/2,vy-1),verdict,font=f(12,True),fill=vc)

d.text((26,16),"RE-ENTRY AFTER A BREAK  -  the two cases",font=f(19,True),fill=TXT)
d.text((26,44),"A break that was already traded does not retire the range. The level stays live.",font=f(12),fill=DIM)

scene(26,80,552,296,
      "CASE A   comes back and CLOSES INSIDE",
      "BREAK FAILED  ->  RE-ARM, trade the next genuine break",BULL,
      [(2648,2651,2647,2650.5,""),
       (2650.5,2653.5,2650,2653.0,"break"),
       (2653.0,2653.2,2648.0,2648.5,"closes\ninside")],
      "the body ends back below the range high")

scene(602,80,552,296,
      "CASE B   wicks inside, REJECTED, CLOSES OUTSIDE",
      "LEVEL HELD  ->  RE-ENTER NOW, same direction",CY,
      [(2648,2651,2647,2650.5,""),
       (2650.5,2653.5,2650,2653.0,"break"),
       (2653.0,2655.0,2649.0,2654.0,"rejected\ncloses out")],
      "wick pierces the level, the body closes beyond it again")

# rule strip
by=400
d.rounded_rectangle([26,by,W-26,by+252],10,fill=PANEL,outline=EDGE)
d.text((44,by+14),"THE RULE THE ENGINE APPLIES  (ReEntryResult)",font=f(14,True),fill=CY)
rows=[
 ("back inside", "CLOSE is back inside the RAW range (High / Low)","-> re-arm: state returns to READY, next real break trades",BULL),
 ("rejection",   "LOW pierces the trigger but CLOSE is beyond it again","-> re-enter immediately in the same direction",CY),
 ("direction",   "a rejection bar must also close WITH the break","a bearish close is not a bullish re-entry",AMB),
 ("buffer",      "drifting inside the buffer zone is not 'back inside'","only the raw range edge counts, so noise cannot re-arm",DIM),
 ("cap",         "MaxBreakoutsPerRange = 3 trades per range","AllowReEntry = true switches the whole behaviour off",DIM),
]
yy=by+46
for tag,a,b,c in rows:
    d.rounded_rectangle([44,yy,150,yy+22],5,fill=(12,20,32),outline=c)
    tw=d.textlength(tag,font=f(10,True)); d.text((44+(106-tw)/2,yy+5),tag,font=f(10,True),fill=c)
    d.text((166,yy+1),a,font=f(12,True),fill=TXT)
    d.text((166,yy+18),b,font=f(11),fill=DIM)
    yy+=42
img.save(os.path.join(HERE,"breakout_reentry_cases.png"))
print("saved docs/breakout_reentry_cases.png")
