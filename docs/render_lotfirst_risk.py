# The three risk models, measured against the trade from the user's log.
import os, math
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__))
BG=(9,14,24);PANEL=(16,24,38);EDGE=(38,54,78);CY=(0,214,255)
DIM=(125,145,170);TXT=(228,238,250);BULL=(0,230,160);BEAR=(255,70,102);AMB=(255,206,84)
def f(sz,b=False):
    n="DejaVuSans-Bold.ttf" if b else "DejaVuSans.ttf"
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/"+n,sz)
    except: return ImageFont.load_default()
PV=100.0
def norm(l,mn=0.01,st=0.01): return round(math.floor(max(mn,l)/st+1e-7)*st,2)
def cap(req,atr,lots,eq,pct,msa=0.5,sl=0.002,maxlots=0.50):
    lots=norm(min(lots,maxlots)); b=eq*pct/100.0
    if req*PV*lots<=b: return req,lots,req*PV*lots,"as requested"
    c=b/(PV*lots); fl=max(atr*msa,sl)
    if c>=fl: return c,lots,c*PV*lots,"stop capped"
    stop=fl; new=norm(min(lots,b/(stop*PV))); r=stop*PV*new
    if new<0.01 or r>b*1.02: return 0,0,0,"skipped"
    return stop,new,r,"lot reduced"

W,H=1280,800
img=Image.new("RGB",(W,H),BG);d=ImageDraw.Draw(img)
d.text((26,16),"LOT-FIRST RISK  -  your lot is honoured, the STOP is capped to 0.5%",font=f(21,True),fill=TXT)
d.text((26,48),"Measured against ticket #17 from the account log: sell 0.10 @ 5017.031, SL 5112.677, equity $429.60",font=f(12),fill=DIM)

# --- three models bar chart ---
y0=86
d.rounded_rectangle([26,y0,W-26,y0+250],9,fill=PANEL,outline=EDGE)
d.text((44,y0+14),"WHAT THAT ONE TRADE RISKED",font=f(14,True),fill=CY)
models=[("v1.02  fixed lot, no risk control", 956.46, BEAR, "0.10 lots x 95646 pt stop  ->  MARGIN CALL at -$429.69"),
        ("v1.03  stop-first sizing",            0.0,  DIM,  "trade REFUSED  ->  'the EA does not enter trades'"),
        ("v1.05  LOT-FIRST (this build)",       2.00, BULL, "0.02 lots x 1000 pt stop  ->  0.47% of equity")]
bx,bw=380,760
for i,(name,val,col,note) in enumerate(models):
    yy=y0+52+i*62
    d.text((44,yy+4),name,font=f(12,True),fill=TXT)
    frac=min(val/429.60,1.0)
    d.rectangle([bx,yy,bx+bw,yy+18],fill=(26,36,54),outline=EDGE)
    if val>0:
        d.rectangle([bx,yy,bx+int(bw*frac),yy+18],fill=col)
        lab=f"${val:,.2f}" + ("  = 222% OF THE ACCOUNT" if val>429 else f"  = {val/429.60*100:.2f}%")
        d.text((bx+int(bw*frac)+8 if frac<0.6 else bx+8,yy+2),lab,font=f(11,True),
               fill=col if frac<0.6 else (10,16,26))
    else:
        d.text((bx+8,yy+2),"no trade",font=f(11,True),fill=DIM)
    d.text((44,yy+24),note,font=f(10),fill=DIM)
# the budget line
bl=bx+int(bw*(429.60*0.005/429.60))
d.line([bl,y0+48,bl,y0+240],fill=AMB,width=2)
d.text((bl+6,y0+232),"0.5% budget = $2.15",font=f(10,True),fill=AMB)

# --- table ---
ty=356
d.rounded_rectangle([26,ty,W-26,ty+330],9,fill=PANEL,outline=EDGE)
d.text((44,ty+14),"THE LOT YOU TYPE IS THE LOT THAT IS SENT  (ATR $2.00, risk 0.5%)",font=f(14,True),fill=CY)
cols=[(44,"EQUITY"),(170,"LOT ASKED"),(300,"STOP WANTED"),(450,"STOP SENT"),(590,"LOT SENT"),(720,"RISK $"),(840,"% EQUITY"),(960,"WHAT HAPPENED")]
for x,t in cols: d.text((x,ty+48),t,font=f(10,True),fill=DIM)
d.line([44,ty+64,W-44,ty+64],fill=EDGE)
rows=[(157.79,0.01,3.0),(200,0.01,3.0),(200,0.05,3.0),(429.60,0.10,95.646),
      (1000,0.05,3.0),(1000,0.10,3.0),(5000,0.10,3.0),(5000,0.50,3.0)]
for i,(eq,lot,want) in enumerate(rows):
    yy=ty+74+i*27
    st,lo,rk,how=cap(want,2.0,lot,eq,0.5)
    ok = lo>0
    c = TXT if ok else DIM
    vals=[f"${eq:,.2f}",f"{lot:.2f}",f"{want/0.001:,.0f} pt",
          (f"{st/0.001:,.0f} pt" if ok else "-"),
          (f"{lo:.2f}" if ok else "-"),
          (f"${rk:.2f}" if ok else "-"),
          (f"{rk/eq*100:.2f}%" if ok else "-"), how]
    for (x,_),v in zip(cols,vals):
        col = c
        if _=="% EQUITY" and ok: col = BULL
        if _=="WHAT HAPPENED": col = (BULL if how=="as requested" else AMB if ok else BEAR)
        if _=="LOT SENT" and ok: col = BULL if lo==min(lot,0.5) else AMB
        d.text((x,yy),v,font=f(10,True if _ in("% EQUITY","LOT SENT") else False),fill=col)
d.text((44,ty+306),"amber = the cap had to act;  red = account too small for this instrument at this risk %",font=f(10),fill=DIM)

# footer
d.text((26,H-72),"Two knobs, in order of bluntness:",font=f(12,True),fill=TXT)
d.text((26,H-52),"MinStopATRMult = 0    -> the lot is NEVER reduced; the stop absorbs the whole cap (0.10 lots kept at 215 pts).",font=f(11),fill=DIM)
d.text((26,H-34),"SkipIfRiskTooHigh=false -> trade at minimum lot even when 0.5% cannot cover it (risk % is then exceeded).",font=f(11),fill=DIM)
img.save(os.path.join(HERE,"breakout_lotfirst_risk.png"))
print("saved docs/breakout_lotfirst_risk.png")
