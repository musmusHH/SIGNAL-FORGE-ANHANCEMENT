#!/usr/bin/env python3
"""Render the BREAKOUT page using the SAME coordinates the .mq4 computes,
in both languages, and assert nothing overlaps or overflows."""
import os, re, sys
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
from verify_arabic import arfix
from PIL import Image, ImageDraw, ImageFont
R="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"; B="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def f(s,b=False): return ImageFont.truetype(B if b else R,max(7,s))

SRC=open(os.path.join(HERE,"..","Breakout Forge XAUUSD M5 EA.mq4"),encoding="utf-8").read()
SC=lambda v:v
W=430; headerH=SC(54); pad=SC(12); innerW=W-pad*2
BK_GATES=8
pageH=headerH+SC(6)+SC(32)+SC(96)+SC(8)+SC(54)+SC(8)+SC(64)+SC(8)+SC(30)+BK_GATES*SC(20)+SC(10)+SC(8)+SC(46)+SC(8)
boxes=[]   # (x0,y0,x1,y1,label) for the collision assert - reset per pass

def draw(lang):
    global boxes
    boxes=[]           # only compare boxes from THIS pass
    AR=(lang=="ar")
    def T(en,ar): return arfix(ar) if AR else en
    im=Image.new("RGB",(W,pageH),(11,15,26)); d=ImageDraw.Draw(im)
    def plate(x,y,w,h,fill,edge):
        d.rectangle([x,y,x+w,y+h],fill=fill,outline=edge)
        d.line([(x+1,y+1),(x+w-1,y+1)],fill=(70,90,124))
    CY=(34,211,238); TX=(226,232,240); DIM=(148,163,184); GR=(52,211,153); RD=(248,113,113); AM=(251,191,36)
    PB=(17,24,39); PB2=(23,32,50); EDGE=(46,60,86)
    # header
    d.rectangle([0,0,W,headerH],fill=(13,32,58))
    d.text((42,10),"BREAKOUT FORGE",font=f(15,True),fill=TX)
    d.rectangle([196,12,228,26],fill=CY); d.text((203,13),"BK",font=f(9,True),fill=(6,10,18))
    y=headerH+SC(6)
    # tabs
    sqW=SC(30); tabW3=(innerW-SC(8)*3-sqW*2)//2
    names=[T("CORE","الرئيسية"),T("BREAKOUT","الاختراق")]
    for i,nm in enumerate(names):
        x=pad+i*(tabW3+SC(8)); act=(i==1)
        plate(x,y,tabW3,SC(24),(16,60,86) if act else PB2,CY if act else EDGE)
        d.text((x+(tabW3-d.textlength(nm,font=f(10,True)))/2,y+6),nm,font=f(10,True),fill=CY if act else DIM)
        boxes.append((x,y,x+tabW3,y+SC(24),"tab%d"%i))
    lx=pad+(tabW3+SC(8))*2; tx=lx+sqW+SC(8)
    for x,t,c in ((lx,"ع|A",CY),(tx,"◐",(167,139,250))):
        plate(x,y,sqW,SC(24),PB2,EDGE); d.text((x+5,y+6),t,font=f(9,True),fill=c)
        boxes.append((x,y,x+sqW,y+SC(24),"sq"))
    y+=SC(32)
    # range card
    plate(pad,y,innerW,SC(96),PB,EDGE); boxes.append((pad,y,pad+innerW,y+SC(96),"range"))
    d.text((pad+SC(12),y+6),T("SESSION RANGE","نطاق الجلسة"),font=f(9,True),fill=CY)
    mode=T("SESSION 0-7","جلسة 0-7")
    d.text((pad+innerW-SC(12)-d.textlength(mode,font=f(9)),y+7),mode,font=f(9),fill=DIM)
    rY=y+SC(30)
    for i,(lab,val,col) in enumerate([(T("HIGH","الأعلى"),"2651.400",GR),
                                      (T("LOW","الأدنى"),"2643.100",RD),
                                      (T("WIDTH","العرض"),"830p",TX)]):
        d.text((pad+SC(12),rY+i*SC(21)),lab,font=f(9),fill=DIM)
        d.text((pad+innerW-SC(12)-d.textlength(val,font=f(11,True)),rY+i*SC(21)),val,font=f(11,True),fill=col)
    y+=SC(96)+SC(8)
    # state strip
    plate(pad,y,innerW,SC(54),(32,44,64),AM); boxes.append((pad,y,pad+innerW,y+SC(54),"state"))
    st=T("WAITING FOR BREAK","بانتظار الاختراق")
    d.text((pad+(innerW-d.textlength(st,font=f(13,True)))/2,y+8),st,font=f(13,True),fill=AM)
    sub=T("PRICE INSIDE RANGE","السعر داخل النطاق")
    d.text((pad+(innerW-d.textlength(sub,font=f(9)))/2,y+32),sub,font=f(9),fill=DIM)
    y+=SC(54)+SC(8)
    # distance
    plate(pad,y,innerW,SC(64),PB,EDGE); boxes.append((pad,y,pad+innerW,y+SC(64),"dist"))
    d.text((pad+SC(12),y+6),T("DISTANCE TO BREAK","المسافة إلى الاختراق"),font=f(9,True),fill=CY)
    d.text((pad+innerW-SC(12)-d.textlength("72%",font=f(9)),y+7),"72%",font=f(9),fill=TX)
    mx,mw=pad+SC(12),innerW-SC(24)
    d.rectangle([mx,y+SC(34),mx+mw,y+SC(48)],fill=(12,18,30),outline=EDGE)
    d.rectangle([mx,y+SC(34),mx+int(mw*.72),y+SC(48)],fill=(16,90,120))
    y+=SC(64)+SC(8)
    # checklist
    d.rectangle([pad,y,pad+innerW,y+SC(26)],fill=PB2,outline=EDGE)
    d.text((pad+SC(10),y+6),T("ENTRY CHECKLIST","قائمة الشروط"),font=f(9,True),fill=CY)
    cnt="7 / 8"
    d.text((pad+innerW-SC(10)-d.textlength(cnt,font=f(9)),y+7),cnt,font=f(9),fill=DIM)
    y+=SC(30)
    gates=[(T("RANGE OK","النطاق"),1),(T("VOLATILITY","التذبذب"),1),(T("SPREAD","السبريد"),1),
           (T("SESSION","الجلسة"),1),(T("RANGE WIDTH","عرض النطاق"),1),(T("BODY CLOSE","إغلاق الجسم"),0),
           (T("NO ROLLOVER","خارج التبييت"),1),(T("DAILY LIMIT","الحد اليومي"),1)]
    for nm,ok in gates:
        col=GR if ok else DIM
        d.ellipse([pad+SC(10),y+SC(5),pad+SC(18),y+SC(13)],fill=col)
        d.text((pad+SC(26),y+SC(3)),nm,font=f(9),fill=TX)
        s2=T("OK","تم") if ok else T("WAIT","انتظار")
        d.text((pad+innerW-SC(12)-d.textlength(s2,font=f(9,True)),y+SC(3)),s2,font=f(9,True),fill=col)
        boxes.append((pad,y,pad+innerW,y+SC(20),"gate"))
        y+=SC(20)
    y+=SC(10)
    # footer
    bw3=(innerW-SC(8))//2
    for i,(t,c) in enumerate([(T("PAUSE","إيقاف"),AM),(T("CLOSE ALL","إغلاق الكل"),RD)]):
        x=pad+i*(bw3+SC(8)); plate(x,y,bw3,SC(26),PB2,c)
        d.text((x+(bw3-d.textlength(t,font=f(10,True)))/2,y+7),t,font=f(10,True),fill=c)
        boxes.append((x,y,x+bw3,y+SC(26),"btn%d"%i))
    assert y+SC(26) <= pageH, f"footer {y+SC(26)} overflows pageH {pageH}"
    return im

en=draw("en"); boxes_en=list(boxes)
ar=draw("ar"); boxes_ar=list(boxes)
out=Image.new("RGB",(W*2+30,pageH+40),(9,13,22)); dd=ImageDraw.Draw(out)
out.paste(en,(10,30)); out.paste(ar,(W+20,30))
dd.text((10,8),"BREAKOUT page - ENGLISH",font=f(11,True),fill=(34,211,238))
dd.text((W+20,8),"BREAKOUT page - ARABIC",font=f(11,True),fill=(34,211,238))
out.save(os.path.join(HERE,"breakout_page_preview.png"))

# overlap assert among same-column boxes
def overlaps(bs):
    out=[]
    for i in range(len(bs)):
        for j in range(i+1,len(bs)):
            a,b=bs[i],bs[j]
            if a[0]<b[2] and b[0]<a[2] and a[1]<b[3] and b[1]<a[3]:
                out.append((a[4],b[4]))
    return out
bad=overlaps(boxes_en)+overlaps(boxes_ar)
print("page height:",pageH,"px")
print("overlaps:",bad if bad else "none")
print("saved docs/breakout_page_preview.png")
if bad: sys.exit(1)
print("BREAKOUT PAGE LAYOUT OK")
