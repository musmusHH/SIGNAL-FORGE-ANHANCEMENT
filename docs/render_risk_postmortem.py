# Post-mortem of the 17-trade run that ended at -0.09 from a $200 deposit.
import os
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__))
BG=(9,14,24);PANEL=(16,24,38);EDGE=(38,54,78);CY=(0,214,255)
DIM=(120,140,165);TXT=(226,236,248);BULL=(0,230,160);BEAR=(255,70,102);AMB=(255,206,84)
def f(sz,b=False):
    n="DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/"+n,sz)
    except: return ImageFont.load_default()
W,H=1240,792
img=Image.new("RGB",(W,H),BG);d=ImageDraw.Draw(img)
d.text((26,16),"POST-MORTEM  -  16 wins, 1 loss, account gone",font=f(21,True),fill=TXT)
d.text((26,48),"$200 deposit  ->  $429.60 after 16 winners  ->  -$0.09 after trade 17",font=f(12),fill=DIM)

# equity curve
ox,oy,ow,oh=26,82,1188,220
d.rounded_rectangle([ox,oy,ox+ow,oy+oh],9,fill=PANEL,outline=EDGE)
bals=[200,219.09,225.13,238.61,255.74,266.42,272.53,292.64,298.79,337.23,347.78,376.70,386.84,396.26,408.64,416.84,429.60,-0.09]
mx=440.0
px,py,pw,ph=ox+50,oy+18,ow-80,oh-52
d.text((ox+14,oy+8),"EQUITY",font=f(11,True),fill=CY)
for gy,lbl in ((0,"440"),(0.5,"220"),(1.0,"0")):
    yy=py+gy*ph
    d.line([px,yy,px+pw,yy],fill=(30,42,60))
    d.text((ox+14,yy-6),lbl,font=f(9),fill=DIM)
pts=[]
for i,b in enumerate(bals):
    x=px+i*(pw/(len(bals)-1)); y=py+ph-(max(b,0)/mx)*ph
    pts.append((x,y))
for i in range(len(pts)-1):
    c=BULL if bals[i+1]>=bals[i] else BEAR
    d.line([pts[i],pts[i+1]],fill=c,width=3)
for i,(x,y) in enumerate(pts):
    d.ellipse([x-3,y-3,x+3,y+3],fill=BULL if bals[i]>0 else BEAR)
d.text((pts[-1][0]-72,pts[-1][1]-22),"-$0.09",font=f(12,True),fill=BEAR)
d.text((pts[-2][0]-30,pts[-2][1]-20),"$429.60",font=f(11,True),fill=BULL)

# three causes
cy0=318
def cause(x,w,num,title,body,fixtxt):
    d.rounded_rectangle([x,cy0,x+w,cy0+248],9,fill=PANEL,outline=EDGE)
    d.ellipse([x+14,cy0+14,x+38,cy0+38],fill=BEAR)
    tw=d.textlength(num,font=f(13,True)); d.text((x+26-tw/2,cy0+18),num,font=f(13,True),fill=(12,18,28))
    d.text((x+48,cy0+19),title,font=f(13,True),fill=BEAR)
    yy=cy0+52
    for ln in body:
        d.text((x+16,yy),ln,font=f(11),fill=TXT if not ln.startswith("  ") else DIM)
        yy+=18
    d.rounded_rectangle([x+14,cy0+248-66,x+w-14,cy0+248-10],6,fill=(10,30,24),outline=BULL)
    yy=cy0+248-60
    for ln in fixtxt:
        d.text((x+24,yy),ln,font=f(10,True),fill=BULL); yy+=16

cause(26,392,"1","CONSTANT LOT, FLOATING STOP",
 ["lots = NormalizeLots(FixedLots)  = 0.10","always, regardless of the stop.","",
  "trade 17 stop was $95.65 wide","  0.10 lots x $95.65 x 100 = $956","  on a $429.60 account = 223%","",
  "The broker stopped it out first."],
 ["FIX  lot is derived FROM the stop","     and the trade is refused if even","     0.01 lot exceeds the budget"])

cause(430,392,"2","REWARD SMALLER THAN RISK",
 ["TakeProfitPoints = 5000","3-digit gold: 5000 x 0.001 = $5.00","",
  "stops were $27.62 - $95.65 wide","  planned R:R  1 : 0.05 .. 1 : 0.18","",
  "16 wins made +$229.60","1 loss took  -$429.69"],
 ["FIX  TP_By_ATR default, plus a hard","     MinRewardRiskRatio = 1.5 floor","     applied after every TP rule"])

cause(834,392,"3","DAILY CAP CHECKED TOO LATE",
 ["MaxDailyLossUSD = $10 is tested","BEFORE a trade opens, against","already-CLOSED trades only.","",
  "Trade 17 opened with the day green","then lost $429 while OPEN.","",
  "Nothing was watching the position."],
 ["FIX  EnforceFloatingLossCap() runs","     every tick: MaxOpenLossUSD = $8","     closes on open drawdown"])

# bottom strip
by=584
d.rounded_rectangle([26,by,W-26,by+186],10,fill=PANEL,outline=EDGE)
d.text((44,by+14),"WHAT THE SAME 17 TRADES DO NOW",font=f(14,True),fill=CY)
rows=[("trade 17","stop $95.65 vs $4.30 budget at 1% -> REFUSED, journal says RISK TOO HIGH",BEAR),
      ("sizing","risk is 1-2% of equity on every fill instead of 12-223%",BULL),
      ("targets","target >= 1.5x the stop, so a 94% win rate now compounds instead of bleeding",BULL),
      ("structural stop","OFF by default: the far side of a 7h range is $27-95 away, and at the 0.01",AMB),
      ("","lot minimum that IS $27-95 of risk. Turn it on above ~$2000 equity.",AMB),
      ("honest note","on $200 with gold near $5000, only tight-ATR setups are affordable.",DIM),
      ("","The EA will now SKIP rather than oversize - expect fewer trades.",DIM)]
yy=by+46
for tag,txt,c in rows:
    if tag:
        d.rounded_rectangle([44,yy-2,186,yy+20],5,fill=(12,20,32),outline=c)
        tw=d.textlength(tag,font=f(10,True)); d.text((44+(142-tw)/2,yy+3),tag,font=f(10,True),fill=c)
    d.text((202,yy+2),txt,font=f(11),fill=c if c!=AMB else AMB)
    yy+=19
img.save(os.path.join(HERE,"breakout_risk_postmortem.png"))
print("saved docs/breakout_risk_postmortem.png")
