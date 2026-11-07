#!/usr/bin/env python3
"""Build foyer-kde's iteration GALLERY.html (living artifact).

Same format law as the fleet's other galleries: dark bg #0d0e12, one section
per iteration, base64-embedded PNGs, live status line, meta-refresh so an
open tab picks up new previews. Append to manifest.json, rerun this.
"""
import base64, html, io, json, os, sys
from datetime import datetime
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(ROOT))  # foyer-kde/
MANIFEST = os.path.join(ROOT, "manifest.json")
STATUS = os.path.join(ROOT, "status.txt")
OUT = os.path.expanduser("~/work/bazzite-customizations/foyer-kde/docs/gallery/GALLERY.html")
RESAMPLE = getattr(getattr(Image, "Resampling", Image), "LANCZOS")

def embed(path):
    img = Image.open(path if os.path.isabs(path) else os.path.join(PROJ, path))
    if img.width > 1400:
        img = img.resize((1400, int(img.height * 1400 / img.width)), RESAMPLE)
    buf = io.BytesIO(); img.save(buf, "PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode()

def main():
    m = json.load(open(MANIFEST))
    status = open(STATUS).read().strip() if os.path.exists(STATUS) else ""
    parts = []
    parts.append("""<!doctype html><html><head><meta charset="utf-8">
<title>Foyer for KDE — design iterations</title>
<meta http-equiv="refresh" content="20">
<style>
body{background:#0d0e12;color:#d7dce2;font:14px/1.55 'Noto Sans',system-ui,sans-serif;margin:0;padding:34px 40px}
h1{font-size:21px;margin:0 0 4px} .sub{color:#8b93a1;font-size:13px;margin-bottom:6px}
.status{color:#3daee9;font:500 13px/1.4 'Noto Sans Mono',monospace;border:1px solid #1c2530;border-radius:8px;padding:10px 14px;margin:14px 0 26px;background:#10141b}
section{margin-bottom:38px}
.vh{display:flex;align-items:baseline;gap:12px;margin:0 0 10px}
.vbadge{font:600 13px/1 'Noto Sans Mono',monospace;background:#1a2b3f;color:#3daee9;border-radius:6px;padding:6px 10px}
.vt{font-size:16px;font-weight:600;color:#e8ecf1}
.verdict{font:600 11px/1 'Noto Sans Mono',monospace;letter-spacing:.08em;border-radius:99px;padding:5px 10px}
.shipped,.accepted{background:#12351f;color:#3ddc84}.rejected{background:#3a1620;color:#ff6b81}
.flight{background:#2b2f14;color:#d9c94a}.note{color:#9aa3b2;font-size:13px;margin:0 0 14px;max-width:110ch}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(410px,1fr));gap:16px}
figure{margin:0;background:#12161d;border:1px solid #1c2530;border-radius:10px;overflow:hidden}
figure img{width:100%;display:block}
figcaption{padding:9px 12px;font-size:12px;color:#8b93a1}
figcaption b{color:#c7d0da;font:600 11px/1 'Noto Sans Mono',monospace;margin-right:8px}
</style></head><body>""")
    n = len(m["iterations"])
    parts.append(f"<h1>Foyer for KDE — design loop</h1>")
    parts.append(f"<div class='sub'>{m.get('subtitle','')} · {n} iteration{'' if n==1 else 's'} · updated {datetime.now():%H:%M}</div>")
    if status: parts.append(f"<div class='status'>{html.escape(status)}</div>")
    for it in m["iterations"]:
        parts.append(f"<section><div class='vh'><span class='vbadge'>{html.escape(it['version'])}</span>"
                     f"<span class='vt'>{html.escape(it.get('title',''))}</span>"
                     f"<span class='verdict {it['verdict'].split()[0].lower()}'>{html.escape(it['verdict'].upper())}</span></div>")
        if it.get("commits"): parts.append(f"<div class='sub' style='margin-bottom:8px'>commits: {html.escape(it['commits'])}</div>")
        if it.get("note"): parts.append(f"<p class='note'>{html.escape(it['note'])}</p>")
        parts.append("<div class='grid'>")
        for s in it["shots"]:
            try: b64 = embed(s["file"])
            except Exception as e: parts.append(f"<figure><figcaption>{s['file']}: {e}</figcaption></figure>"); continue
            parts.append(f"<figure><img src='data:image/png;base64,{b64}' alt=''>"
                         f"<figcaption><b>{html.escape(s.get('label',''))}</b>{html.escape(s.get('caption',''))}</figcaption></figure>")
        parts.append("</div></section>")
    parts.append("</body></html>")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w").write("".join(parts))
    print(f"wrote {OUT} ({os.path.getsize(OUT)//1024}KB, {n} iterations)")

if __name__ == "__main__":
    main()
