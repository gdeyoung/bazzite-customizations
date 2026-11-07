#!/usr/bin/env python3
"""Build plasma-tailfin's iteration GALLERY.html.

Living artifact: every build iteration appends to iterations/manifest.json
(via add-iteration.py or by hand), then this script regenerates the single
self-contained gallery at docs/gallery/GALLERY.html. Greg keeps that file
open and refreshes — new iterations appear at the top of their section.

Format law (ui-redesign-loop): dark bg #0d0e12, figure cards with
`vN · HH:MM` badges, one-line what-changed captions, header carries the
workflow subtitle: iteration count · research inputs · council · commits.
"""
import base64
import html
import io
import json
import os
import sys
from datetime import datetime
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))  # tools/gallery/
MANIFEST = os.path.join(ROOT, "manifest.json")
STATUS_FILE = os.path.join(ROOT, "status.txt")  # optional live status line
OUT = os.path.expanduser("~/work/bazzite-customizations/plasma-tailfin/docs/gallery/GALLERY.html")


def embed(path, crop_right=False):
    img = Image.open(path)
    if crop_right and img.size[0] > 700:  # full-desktop shot → popup crop
        w, h = img.size
        img = img.crop((w - 680, h - 780, w, h - 50)).resize((680, 730))
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode()


def main():
    with open(MANIFEST) as f:
        manifest = json.load(f)

    status = ""
    if os.path.exists(STATUS_FILE):
        status = open(STATUS_FILE).read().strip()

    sections = []
    n_shots = 0
    for it in manifest["iterations"]:
        verdict = it.get("verdict", "")
        vclass = {"rejected": "vr", "accepted": "va", "pending": "vp"}.get(verdict, "vp")
        vlabel = {"rejected": "REJECTED", "accepted": "ACCEPTED", "pending": "IN FLIGHT"}.get(verdict, "")
        cards = []
        for sh in it["shots"]:
            p = os.path.join(ROOT, sh["file"]) if not sh["file"].startswith("/") else sh["file"]
            if not os.path.exists(p):
                continue
            cards.append(
                f'<figure><div class="v">{html.escape(sh.get("label", ""))}</div>'
                f'<img src="data:image/png;base64,{embed(p, sh.get("crop", True))}"/>'
                f"<figcaption>{html.escape(sh['caption'])}</figcaption></figure>"
            )
            n_shots += 1
        meta = " · ".join(x for x in [it.get("commits", ""), it.get("note", "")] if x)
        sections.append(
            f'<section><h2><span class="badge {vclass}">{it["version"]}</span>'
            f'{f"<span class=\"{vclass}-tag\">{vlabel}</span>" if vlabel else ""}'
            f'<span class="meta">{html.escape(meta)}</span></h2>'
            f'<div class="grid">{"".join(cards)}</div></section>'
        )

    n_iter = len(manifest["iterations"])
    doc = f"""<!doctype html><meta charset="utf-8">
<meta http-equiv="refresh" content="120">
<title>plasma-tailfin — iteration gallery</title>
<style>
body{{margin:0;background:#0d0e12;color:#e6e7ee;font:15px/1.5 "Inter","Noto Sans",sans-serif;padding:34px 40px}}
h1{{font-size:26px;margin:0 0 4px}}
.sub{{color:#9ba0ac;margin:0 0 6px}}
.status{{color:#8b7cf8;font-size:14px;margin:0 0 26px}}
section{{margin-bottom:34px}}
h2{{font-size:17px;margin:0 0 14px;display:flex;gap:12px;align-items:baseline;flex-wrap:wrap}}
.badge{{font-weight:700;font-size:15px}}
.vr{{color:#e0564f}}.va{{color:#5ec26a}}.vp{{color:#8b7cf8}}
.vr-tag,.va-tag,.vp-tag{{font-size:11.5px;font-weight:700;letter-spacing:.6px;padding:2px 8px;border-radius:6px}}
.vr-tag{{background:#e0564f22;color:#e0564f}}.va-tag{{background:#5ec26a22;color:#5ec26a}}.vp-tag{{background:#8b7cf822;color:#8b7cf8}}
.meta{{color:#7c8290;font-size:13px;font-weight:400}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:26px}}
figure{{margin:0;background:#141519;border:1px solid #26282f;border-radius:12px;overflow:hidden}}
.v{{display:inline-block;background:#8b7cf8;color:#14151a;font-weight:700;font-size:12.5px;padding:3px 10px;border-radius:0 0 8px 0}}
img{{width:100%;display:block}}
figcaption{{padding:10px 14px 13px;color:#a6abb8;font-size:13.5px}}
</style>
<h1>plasma-tailfin — iteration gallery</h1>
<p class="sub">{html.escape(manifest.get("subtitle", ""))} · {n_iter} iterations · {n_shots} shots · refreshed {datetime.now().strftime("%H:%M")}</p>
{f'<p class="status">▸ {html.escape(status)}</p>' if status else ""}
{''.join(sections)}
"""
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write(doc)
    print(f"{OUT}: {n_iter} iterations, {n_shots} shots, {os.path.getsize(OUT)//1024} KB")


if __name__ == "__main__":
    sys.exit(main())
