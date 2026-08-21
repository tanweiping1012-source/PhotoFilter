import json, re, glob, sys
cat = set(json.load(open("Resources/Localizable.xcstrings"))["strings"])
def strip_interp(lit):
    out, i = [], 0
    while i < len(lit):
        if lit.startswith("\\(", i):
            depth, j = 0, i + 1
            while j < len(lit):
                if lit[j] == "(": depth += 1
                elif lit[j] == ")":
                    depth -= 1
                    if depth == 0: break
                j += 1
            out.append("\x00"); i = j + 1
        else:
            out.append(lit[i]); i += 1
    return "".join(out)
by_seg = {}
for k in cat:
    by_seg.setdefault(tuple(p for p in re.split(r"%(?:\d+\$)?(?:lld|ld|@|d|f)", k) if p), []).append(k)
missing = []
for path in sorted(glob.glob("Sources/PhotoCurator/*.swift")):
    for m in re.finditer(r'String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"', open(path).read(), re.S):
        lit = m.group(1)
        if not re.search(r"[一-鿿]", lit): continue
        if lit in cat: continue
        if tuple(p for p in strip_interp(lit).split("\x00") if p) in by_seg: continue
        missing.append(f"{path.split('/')[-1]}: {lit[:70]}")
if missing:
    print("\n".join(missing)); sys.exit(1)
