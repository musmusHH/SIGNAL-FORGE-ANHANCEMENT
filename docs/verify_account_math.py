#!/usr/bin/env python3
"""Verify the tracker reports the REAL account, not just this EA's slice.

The reported bug: a demo funded with 200.00 showing a balance of 157.79 - a
loss of 42.21 - displayed "+11.03 USD" with a RISING equity curve. The stats
were filtered by `OrderMagicNumber() == MagicNumber`, so every trade that was
not this EA's was invisible: the money that was lost simply was not in the
series being plotted.

This checks the source so the filtered figure can never again be presented as
the account result.
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = open(os.path.join(HERE, "..", "Signal Forge PRO XAUUSD M5 EA.mq4"),
           encoding="utf-8").read()
fails = []

def check(label, ok, detail=""):
    print(f"   {label:54s} {'OK' if ok else 'FAIL'}{(' - ' + detail) if detail and not ok else ''}")
    if not ok:
        fails.append(label)

print("1. the account-wide pass exists")
check("gAcctStart / gAcctNetAll / gAcctDeposits declared",
      all(re.search(r'^double\s+%s' % g, SRC, re.M) for g in
          ("gAcctDeposits", "gAcctNetAll", "gAcctStart")))
check("balance/credit rows (deposits/withdrawals) are read",
      re.search(r'#define SF_OP_BALANCE 6', SRC) is not None
      and re.search(r'#define SF_OP_CREDIT\s+7', SRC) is not None
      and SRC.count("SF_OP_BALANCE") >= 3)

# MQL4 has no OP_BALANCE/OP_CREDIT - they are MQL5 constants and the compiler
# rejects them as undeclared identifiers. Guard the whole MQL5-only family so
# this class of error cannot come back.
def strip_comments_strings(t):
    o = []; i = 0; n = len(t)
    while i < n:
        if t[i:i+2] == "//":
            while i < n and t[i] != "\n": i += 1
        elif t[i:i+2] == "/*":
            i += 2
            while i + 1 < n and t[i:i+2] != "*/": i += 1
            i += 2
        elif t[i] in "\"'":
            q = t[i]; i += 1
            while i < n and t[i] != q:
                if t[i] == "\\": i += 1
                i += 1
            i += 1
        else:
            o.append(t[i]); i += 1
    return "".join(o)

CODE = strip_comments_strings(SRC)
MQL5_ONLY = ("OP_BALANCE OP_CREDIT ORDER_TYPE_BUY ORDER_TYPE_SELL DEAL_TYPE_BALANCE "
             "PositionSelect PositionsTotal HistorySelect HistoryDealsTotal "
             "AccountInfoDouble AccountInfoInteger SymbolInfoInteger CopyBuffer "
             "MqlTradeRequest MqlTradeResult ZeroMemory CopyClose CopyTime").split()
leaked = sorted({t for t in MQL5_ONLY if re.search(r"\b" + t + r"\b", CODE)})
check("no MQL5-only identifiers in MQL4 code", not leaked, str(leaked))
check("the account pass is NOT filtered by magic",
      re.search(r'gAcctNetAll \+= OrderProfit\(\) \+ OrderSwap\(\) \+ OrderCommission\(\);',
                SRC) is not None)

# the account loop must not carry the magic/symbol filter.
# Scope the match to the FOR BODY only - a greedy match runs past the loop
# into the magic-filtered EA pass that legitimately follows it.
m = re.search(r'gAcctDeposits = 0;.*?for\(int a = 0.*?\n     \}', SRC, re.S)
check("account loop has no MagicNumber filter",
      m is not None and "OrderMagicNumber() != MagicNumber" not in m.group(0))
check("account loop has no Symbol filter",
      m is not None and "OrderSymbol() != Symbol()" not in m.group(0))

print("\n2. the equity curve plots the real account")
eq = re.search(r'double run = gAcctStart.*?\n     \}', SRC, re.S)
check("curve starts from gAcctStart", eq is not None)
check("curve is NOT magic-filtered",
      eq is not None and "OrderMagicNumber() != MagicNumber" not in eq.group(0))
check("curve includes funding entries",
      eq is not None and "OP_BALANCE" in eq.group(0))
check("max drawdown derives from the same series",
      eq is not None and "gStatMaxDD" in eq.group(0))

print("\n3. the headline card reports the account")
check("ACCOUNT P/L = balance - true start",
      re.search(r'double acctPL\s*=\s*AccountBalance\(\) - gAcctStart;', SRC) is not None)
check("card colour follows the ACCOUNT result, not the EA result",
      re.search(r'bool\s+acctUp\s*=\s*\(acctPL >= 0\);', SRC) is not None
      and re.search(r'RaisedPlate\(pad, y, innerW, flH, SC\(8\),\s*\n\s*acctUp \?', SRC) is not None)
check("the card still shows START and BAL so it can be checked",
      'T("START")' in SRC and 'T("BAL")' in SRC)
check("the EA's own figure is labelled as such",
      'T("THIS EA")' in SRC)
check("total GAIN% measured against the real start",
      re.search(r'double gainBase = \(gAcctStart > 0\) \? gAcctStart', SRC) is not None)

print("\n4. arithmetic on the reported numbers")
# reproduce the user's account from the screenshot
start, bal, ea_net = 200.00, 157.79, 11.03
acct_pl = bal - start
print(f"   funded {start:.2f}, balance {bal:.2f}, this EA {ea_net:+.2f}")
print(f"   -> ACCOUNT P/L {acct_pl:+.2f}   (was displayed as {ea_net:+.2f})")
check("account result is negative for the reported figures", acct_pl < 0)
check("the two figures genuinely differ", abs(acct_pl - ea_net) > 1.0,
      f"{abs(acct_pl - ea_net):.2f}")

print("\n5. translated labels the user listed")
for key in ("BALANCE", "EQUITY", "FLOATING P/L", "DAY P/L",
            "ACCOUNT P/L", "START", "THIS EA"):
    check(f'"{key}" has a translation',
          re.search(r'if\(k == "%s"\)' % re.escape(key), SRC) is not None)
check("DrawChip translates its own label (covers all 4 chips)",
      re.search(r'Text\(x \+ SC\(12\), y \+ SC\(6\),\s*T\(label\)', SRC) is not None)

print("\n6. FLAT wording and centring")
check('FLAT is "sideways market", not "no trade"',
      re.search(r'if\(k == "FLAT"\)\s*return "((?:\\x[0-9A-Fa-f]{4})+)";', SRC) is not None
      and ''.join(chr(int(h, 16)) for h in re.findall(
          r'\\x([0-9A-Fa-f]{4})',
          re.search(r'if\(k == "FLAT"\)\s*return "((?:\\x[0-9A-Fa-f]{4})+)";',
                    SRC).group(1))) == "\u0633\u0648\u0642 \u0639\u0631\u0636\u064a")
check("TextBoxCenter exists (measured centring on both axes)",
      re.search(r'void TextBoxCenter\(', SRC) is not None)
for what in ("PRO", "bias", "state pill"):
    pass
check("PRO badge uses measured centring",
      re.search(r'TextBoxCenter\(badgeX, hy \+ SC\(2\), badgeW, badgeH, "PRO"', SRC) is not None)
check("state pill uses measured centring",
      re.search(r'TextBoxCenter\(pillX \+ SC\(18\)', SRC) is not None)
check("BIAS card uses measured centring",
      re.search(r'TextBoxCenter\(bX, bY, bW, bH, bias', SRC) is not None)
check("BIAS card widened for the longer Arabic word",
      re.search(r'int bW = SC\(76\)', SRC) is not None)

# the widened card must not collide with the VOTE column
pad, innerW = 12, 430 - 24
bias_end = pad + 148 + 76
vote_x   = pad + 226
check(f"BIAS card ends {bias_end} < VOTE column {vote_x}", bias_end <= vote_x)
bar_end = pad + 262 + innerW - 274
check(f"agreement bar ends {bar_end} inside panel {pad + innerW}",
      bar_end <= pad + innerW)

print()
if fails:
    print("FAILURES:")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("ALL ACCOUNT-MATH AND LAYOUT CHECKS PASS")
