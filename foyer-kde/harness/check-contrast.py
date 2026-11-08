#!/usr/bin/env python3
"""check-contrast.py — Foyer UI law, enforced.

LAW: no light box fills behind text, ever (user directive 2026-11-08).
A "fill" is a connected light region large enough that it cannot be a
text glyph run. Games-cell-sized fills are ~23k px²; the largest
legitimate text runs measure well under 700 px². Threshold: 720 px².

Modes:
  --shots DIR       scan every *.png (harness offscreen frames; static bg)
  --pair OFF ON     live pair: only pixels that changed (diff >= 40) are
                    judged, so the user's desktop can't pollute the verdict
Card geometry is auto-detected as the changed bbox (pair mode) or the
full frame (shots mode). Exit 0 = law upheld; exit 1 = violation, with
the offending region list on stdout.
"""
import sys, glob
from PIL import Image, ImageChops

STRIDE = 3          # px sampling stride
NODES = 80          # connected nodes (each ~STRIDE^2 px²) = 720 px² fill
LUM = 110           # "light" luminance threshold (0..255)
SAT = 25            # max channel spread to count as grayish/white fill

def light_mask_points(img):
    W, H = img.size
    pts = {}
    for y in range(0, H, STRIDE):
        for x in range(0, W, STRIDE):
            r, g, b = img.getpixel((x, y))[:3]
            if 0.2126*r + 0.7152*g + 0.0722*b > LUM and abs(r-g) < SAT and abs(g-b) < SAT:
                pts[(x, y)] = (r, g, b)
    return pts

def fills(pts):
    seen, comps = set(), []
    for p in pts:
        if p in seen: continue
        stack, comp = [p], []
        while stack:
            q = stack.pop()
            if q in seen: continue
            seen.add(q); comp.append(q)
            x, y = q
            for n in ((x+STRIDE,y),(x-STRIDE,y),(x,y+STRIDE),(x,y-STRIDE)):
                if n in pts and n not in seen: stack.append(n)
        comps.append(comp)
    return sorted((c for c in comps if len(c) >= NODES), key=len, reverse=True)

def report(name, pts, bad):
    status = "PASS" if not bad else "FAIL"
    print(f"{name}: {status} ({len(pts)} light px)")
    for c in bad[:6]:
        xs = [p[0] for p in c]; ys = [p[1] for p in c]
        r = sum(pts[p][0] for p in c)//len(c); g = sum(pts[p][1] for p in c)//len(c); b = sum(pts[p][2] for p in c)//len(c)
        print(f"  FILL {len(c)*STRIDE*STRIDE}px² bbox=({min(xs)},{min(ys)})-({max(xs)},{max(ys)}) avg=({r},{g},{b})")
    return not bad

def main():
    args = sys.argv[1:]
    ok = True
    if args[:1] == ["--shots"]:
        for f in sorted(glob.glob(args[1] + "/*.png")):
            ok = report(f.split("/")[-1], *(lambda p: (p, fills(p)))(light_mask_points(Image.open(f).convert("RGB")))) and ok
    elif args[:1] == ["--pair"]:
        off = Image.open(args[1]).convert("RGB"); on = Image.open(args[2]).convert("RGB")
        diff = ImageChops.difference(off, on).convert("L")
        pts = {}
        base = light_mask_points(on)
        for (x, y), rgb in base.items():
            v = diff.getpixel((x, y))
            if isinstance(v, int) and v >= 40: pts[(x, y)] = rgb
        ok = report("pair", pts, fills(pts))
    else:
        print(__doc__); sys.exit(2)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
