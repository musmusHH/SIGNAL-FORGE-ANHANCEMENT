# Mirror of the EA's cost + sizing math, Exness Raw Spread 3-digit XAUUSD.
POINT=0.001; DIGITS=3
TICKSIZE=0.001; TICKVALUE=0.01   # 100oz contract: 0.001 move on 1.00 lot = $0.10
# MT4 reports TICKVALUE per 1.0 lot. 1 lot = 100oz; 0.001 price move => $0.10
TICKVALUE=0.10
MINLOT=0.01; LOTSTEP=0.01
COMM_RT_PER_001=0.07

def point_value(lots): return lots*TICKVALUE*(POINT/TICKSIZE)
def comm_rt(lots): return (lots/0.01)*COMM_RT_PER_001

pv001=point_value(0.01)
cost_points=COMM_RT_PER_001/pv001
print(f"point value @0.01 lot = ${pv001:.5f}")
print(f"commission round-turn = {cost_points:.1f} price points  (= ${COMM_RT_PER_001} )")
print(f"  -> in gold dollars  = ${cost_points*POINT:.3f} of price movement\n")

def norm_lots(l, maxlots=1.0):
    l=max(MINLOT,min(min(200.0,maxlots),l))
    return round((l//LOTSTEP)*LOTSTEP + 1e-9,2)

def calc_lots(capital, risk_pct, sl_points, cap_pct=2.0, allow_override=False):
    risk_money=capital*risk_pct/100.0
    per_lot_pv=point_value(1.0)
    loss_per_lot=per_lot_pv*sl_points + comm_rt(1.0)
    raw=risk_money/loss_per_lot
    if raw < MINLOT-1e-8:
        min_loss=point_value(MINLOT)*sl_points+comm_rt(MINLOT)
        min_pct=min_loss/capital*100
        if min_pct>cap_pct and not allow_override:
            return 0.0, min_pct, "REFUSED"
        lots=MINLOT
    else:
        lots=norm_lots(raw)
    used=(point_value(lots)*sl_points+comm_rt(lots))/capital*100
    return lots, used, "OK"

print("=== $200 account, risk 1%, SL sweep (ATR 1.6x on M5 gold) ===")
for slp in [600,900,1200,1500,2000,2500,3000]:
    lots,used,st=calc_lots(200,1.0,slp)
    money=point_value(max(lots,MINLOT))*slp+comm_rt(max(lots,MINLOT))
    print(f" SL {slp:5d} pts (${slp*POINT:6.2f})  lots={lots:.2f}  risk={used:5.2f}%  loss=${money:6.2f}  {st}")

print("\n=== balance sweep @1% risk, SL=1500pts ($1.50) ===")
for bal in [200,300,500,1000,2000,5000]:
    lots,used,st=calc_lots(bal,1.0,1500)
    print(f" bal ${bal:5d}  lots={lots:.2f}  risk={used:5.2f}%  {st}")

print("\n=== commission drag: % of a $200 account per round turn ===")
for lots in [0.01,0.02,0.05]:
    c=comm_rt(lots)
    print(f" {lots:.2f} lots -> ${c:.2f} = {c/200*100:.3f}% of $200  |  30 trades/mo = {c*30/200*100:.2f}%")

print("\n=== minimum viable TP (MinTPtoCostRatio=3) ===")
for spread in [10,20,40,80,130]:
    total=spread+cost_points
    print(f" spread {spread:3d}p -> round turn {total:5.0f}p (${total*POINT:.2f}) -> min TP {total*3:5.0f}p (${total*3*POINT:.2f})")
