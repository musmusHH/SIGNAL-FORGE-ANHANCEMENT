# New York ORB on an Exness (UTC+0) server, and the automatic DST switch.
import os, datetime
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__))
BG=(9,14,24);PANEL=(16,24,38);EDGE=(38,54,78);CY=(0,214,255)
DIM=(120,140,165);TXT=(226,236,248);BULL=(0,230,160);BEAR=(255,70,102);AMB=(255,206,84)
VIO=(170,150,255)
def f(sz,b=False):
    n="DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/"+n,sz)
    except: return ImageFont.load_default()
W,H=1180,760
img=Image.new("RGB",(W,H),BG);d=ImageDraw.Draw(img)

def dow(y,m,dd):
    t=[0,3,2,5,0,3,5,1,4,6,2,4]
    yy=y-1 if m<3 else y
    return (yy+yy//4-yy//100+yy//400+t[m-1]+dd)%7
def nth(y,m,wd,n): return 1+(wd-dow(y,m,1)+7)%7+(n-1)*7

d.text((26,20),"NEW YORK ORB  +  AUTOMATIC DST",font=f(20,True),fill=CY)
d.text((26,48),"Exness servers are UTC+0 all year. New York is not. The EA converts NY wall-clock to server time and re-converts when DST flips.",font=f(11),fill=DIM)

def block(x,y,w,h,title,col,sub=""):
    d.rounded_rectangle([x,y,x+w,y+h],10,fill=PANEL,outline=EDGE,width=2)
    d.text((x+16,y+12),title,font=f(14,True),fill=col)
    if sub: d.text((x+16,y+33),sub,font=f(10),fill=DIM)

# ---------- the two seasons ----------
block(26,86,1128,250,"THE SAME SETTINGS, THE TWO SEASONS",BULL,
      "NYOpenHour 9 : NYOpenMinute 30 : ORBMinutes 15 : ORBTradeMinutes 330   -- never edited twice a year")
rows=[("SUMMER  (EDT, UTC-4)",-4,BULL),("WINTER  (EST, UTC-5)",-5,AMB)]
y=140
for lbl,off,col in rows:
    d.text((60,y),lbl,font=f(13,True),fill=col)
    o=(9.5-off)%24; c=(9.5+0.25-off)%24; t=(9.5+330/60-off)%24
    def clk(v): return "%02d:%02d"%(int(v),round((v-int(v))*60))
    # timeline
    x0,x1=300,1100; lo,hi=12.0,22.0
    sc=(x1-x0)/(hi-lo)
    d.line([x0,y+34,x1,y+34],fill=EDGE,width=2)
    for hh in range(12,23):
        px=x0+(hh-lo)*sc
        d.line([px,y+30,px,y+38],fill=EDGE,width=1)
        d.text((px-11,y+42),"%02d:00"%hh,font=f(8),fill=DIM)
    # ORB box
    d.rectangle([x0+(o-lo)*sc,y+16,x0+(c-lo)*sc,y+32],fill=col,outline=col)
    d.text((x0+(o-lo)*sc-4,y-2),"ORB "+clk(o),font=f(10,True),fill=col)
    # trade window
    d.rectangle([x0+(c-lo)*sc,y+20,x0+(t-lo)*sc,y+30],fill=(0,54,74),outline=CY,width=1)
    d.text((x0+(c-lo)*sc+6,y+20),"tradable to "+clk(t),font=f(10),fill=CY)
    # rollover
    d.rectangle([x0+(20-lo)*sc,y+14,x0+(22-lo)*sc,y+34],fill=(60,18,26),outline=BEAR,width=1)
    d.text((x0+(20-lo)*sc+4,y-2),"rollover",font=f(9),fill=BEAR)
    d.text((60,y+22),"NY 09:30  ->  server "+clk(o),font=f(11),fill=TXT)
    y+=92
d.text((60,y+4),"330 minutes is the most that still clears the 20:00 rollover in WINTER, when the open sits an hour later on the server clock.",font=f(10),fill=AMB)

# ---------- the rule ----------
block(26,350,552,180,"THE DST RULE (US)",VIO,"2nd Sunday of March  ->  1st Sunday of November")
yy=400
for y_ in (2025,2026,2027,2028):
    a=nth(y_,3,0,2); b=nth(y_,11,0,1)
    da=datetime.date(y_,3,a); db=datetime.date(y_,11,b)
    d.text((60,yy),"%d"%y_,font=f(12,True),fill=TXT)
    d.text((120,yy),"Mar %-2d (%s)  ->  Nov %-2d (%s)"%(a,da.strftime("%a"),b,db.strftime("%a")),font=f(12),fill=BULL)
    yy+=26
d.text((60,yy+2),"computed in-code, no table to expire",font=f(10),fill=DIM)

# ---------- exness cross-check ----------
block(602,350,552,180,"CROSS-CHECKED vs EXNESS",BULL,"their published New York hours, UTC")
yy=400
d.text((622,yy),"session",font=f(11,True),fill=CY)
d.text((800,yy),"summer UTC",font=f(11,True),fill=CY)
d.text((980,yy),"winter UTC",font=f(11,True),fill=CY)
yy+=24
for lbl,s_,w_ in (("NY open 09:30","13:30","14:30"),("NY close 16:00","20:00","21:00")):
    d.text((622,yy),lbl,font=f(11),fill=TXT)
    d.text((800,yy),s_,font=f(11,True),fill=BULL)
    d.text((980,yy),w_,font=f(11,True),fill=AMB)
    yy+=26
d.text((622,yy+6),"Exness: 'New York  13h30-20h  /  14h30-21h'",font=f(10),fill=DIM)
d.text((622,yy+24),"the EA's conversion reproduces this exactly.",font=f(10),fill=BULL)

# ---------- frequency ----------
block(26,546,1128,190,"MORE TRADES PER DAY",CY,"what changed, and what still caps you")
yy=596
for a,b,col in (("RangeMode","SESSION (Asian, 1 box/day)  ->  ORB (New York open)",TXT),
                ("MaxBreakoutsPerRange","3  ->  5   trades one ORB box may produce",BULL),
                ("MaxTradesPerDay","6  ->  10  daily ceiling",BULL),
                ("MinRangePoints","4000  ->  2500   a 15-min box is far smaller than a 7-hour session range",BULL),
                ("AllowReEntry","true (unchanged) - re-enters after a failed break",DIM),
                ("OnePositionOnly","true (unchanged) - still one position at a time",AMB)):
    d.text((60,yy),a,font=f(11,True),fill=CY)
    d.text((290,yy),b,font=f(11),fill=col)
    yy+=23

out=os.path.join(HERE,"breakout_ny_dst.png")
img.save(out); print("wrote",out)
