#!/usr/bin/env python3
"""Catch 'declaration of X hides local variable' before MetaEditor does.

MQL4 warns when a nested block re-declares a name that already exists in an
enclosing block of the SAME function. It is only a warning, but it is the
class of mistake that silently changes which variable a line writes to, so
it is worth failing on. Both EAs are checked.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = ["Breakout Forge XAUUSD M5 EA.mq4", "Signal Forge PRO XAUUSD M5 EA.mq4"]

TYPES   = (r'(?:bool|int|uint|long|ulong|short|ushort|char|uchar|double|'
           r'float|string|datetime|color|CCanvas)')
DECL    = re.compile(r'^\s*(?:static\s+|const\s+)*' + TYPES + r'\s+([A-Za-z_]\w*)\s*(?:=|;|,|\[)')
FORDECL = re.compile(r'for\s*\(\s*' + TYPES + r'\s+([A-Za-z_]\w*)')
FNSTART = re.compile(r'^(?:void|bool|string|int|uint|double|datetime|color|long|ulong)\s+\w+\s*\([^;]*\)\s*$')


def clean(line):
    """Drop comments and string literals so their contents never parse as code."""
    line = re.sub(r'//.*', '', line)
    return re.sub(r'"(\\.|[^"\\])*"', '""', line)


def scan(path):
    lines = open(path, encoding='utf-8').read().split("\n")
    issues, i, n = [], 0, len(lines)
    while i < n:
        if FNSTART.match(lines[i]) and i + 1 < n and lines[i + 1].strip() == "{":
            fname, depth, j, scopes = lines[i].strip(), 0, i + 1, []
            while j < n:
                c = clean(lines[j])
                opens, closes = c.count("{"), c.count("}")

                # A for-header variable belongs to the LOOP's own scope, which
                # MQL4 treats as a fresh block. Two sibling `for(int i...)`
                # loops therefore do not shadow each other, and a loop counter
                # does not shadow an enclosing block variable of the same name
                # unless that variable is a plain block local. Track them
                # separately so the check matches what MetaEditor reports.
                fm = FORDECL.search(c)
                loop_names = set()
                if fm:
                    loop_names.add(fm.group(1))

                m = DECL.match(c)
                if m and m.group(1) not in loop_names:
                    name = m.group(1)
                    # only ENCLOSING scopes shadow; same scope is a redeclare
                    for sc in (scopes[:-1] if len(scopes) > 1 else []):
                        if name in sc:
                            issues.append((j + 1, name, sc[name], fname))
                    if scopes:
                        scopes[-1][name] = j + 1

                scopes.extend({} for _ in range(opens))
                for _ in range(closes):
                    if scopes:
                        scopes.pop()
                depth += opens - closes
                if depth <= 0 and j > i + 1:
                    break
                j += 1
            i = j
        i += 1
    return issues


bad = 0
for f in FILES:
    path = os.path.join(HERE, "..", f)
    if not os.path.exists(path):
        continue
    issues = scan(path)
    if issues:
        bad += len(issues)
        print(f"{f}: {len(issues)} shadowed local(s)")
        for ln, name, orig, fn in issues:
            print(f"   line {ln}: '{name}' hides the declaration at line {orig}  in {fn}")
    else:
        print(f"{f}: no shadowed locals")

if bad:
    print(f"\nFAIL: {bad} shadowing warning(s) the compiler will report")
    sys.exit(1)
print("\nNO SHADOWED LOCALS IN EITHER EA")
