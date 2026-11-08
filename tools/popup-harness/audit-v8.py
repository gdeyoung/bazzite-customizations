#!/usr/bin/env python3
"""Pixel audit for tailfin v8 harness shots.

Usage: audit-v8.py TAG FIXTURE [SCALE LIGHT]
Asserts: all 6 shots exist, are non-blank (stddev > 2), and pairwise
pixel-distinct (histogram distance) so no two "different" states
rendered identically. Prints PASS/FAIL per pair. Exit 0 only on full
pass; partial metadata pass exits 2.
"""
import sys, os, itertools
from PIL import Image, ImageStat

ROOT = "/tmp/stk-harness/shots"
NAMES = ["machines", "offexp", "search", "exittab", "connection", "detail"]

def main():
    tag, fx = sys.argv[1], sys.argv[2]
    scale = sys.argv[3] if len(sys.argv) > 3 else "1"
    light = sys.argv[4] if len(sys.argv) > 4 else "0"
    sfx = f"s{scale}{light}"
    imgs = {}
    fail = 0
    for n in NAMES:
        p = f"{ROOT}/{tag}-{fx}-{n}-{sfx}.png"
        if not os.path.exists(p):
            print(f"MISSING {n}: {p}")
            fail += 1
            continue
        im = Image.open(p).convert("L")
        # blank check: stddev across a center crop
        w, h = im.size
        crop = im.crop((w//4, h//4, 3*w//4, 3*h//4))
        st = ImageStat.Stat(crop).stddev[0]
        if st < 2:
            print(f"BLANK?  {n} stddev={st:.1f}")
            fail += 1
        imgs[n] = (im, im.histogram())
    if fail:
        sys.exit(2)
    bad = 0
    for a, b in itertools.combinations(NAMES, 2):
        if a not in imgs or b not in imgs:
            continue
        ha, hb = imgs[a][1], imgs[b][1]
        dist = sum(abs(x - y) for x, y in zip(ha, hb))
        if dist == 0:
            print(f"IDENTICAL {a}=={b}")
            bad += 1
    print(f"AUDIT {tag}-{fx}-{sfx}: {'PASS' if bad == 0 else 'FAIL'} "
          f"({len(imgs)}/6 shots, {bad} identical pairs)")
    sys.exit(0 if bad == 0 else 1)

if __name__ == "__main__":
    main()
