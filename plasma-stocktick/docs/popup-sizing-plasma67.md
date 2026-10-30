# Plasma 6.7 popup sizing — source-verified algorithm + harness verification

Task t_995d223d. All source citations from `libplasma` / `plasma-desktop` **v6.7.5**
(shallow clones in `reference-repos/`, gitignored) and verified empirically in the
headless nested-wayland harness (workspace `t_995d223d/harness/`, plus the
`tools/` harness from 248bccd). gdtower runs plasma-desktop-6.7.5-1.fc44.

## 1. The size-resolution algorithm (AC1)

`libplasma/src/plasmaquick/appletpopup.cpp`, `updateSize()`:

1. **Config keys win, forever.** `AppletPopup::showEvent` reads `popupWidth` /
   `popupHeight` from the *applet's own* config group (L128–139, L145–158) and
   sets `m_sizeExplicitlySetFromConfig`. While that flag is set, `updateSize()`
   early-returns at L212 — **no layout hint is ever consulted again**.
2. **`hideEvent` persists the size on EVERY close** (writes `popupWidth` /
   `popupHeight` = current popup size). Alt+RightClick-drag resize persists the
   same way. Consequence: one close at a wrong size pins the wrong size across
   restarts — this is why hint changes "did nothing" in earlier builds. The
   prior commit ce7b520 fought crash-resurrected keys; the same unstick
   runbook applies whenever it recurs: **stop plasmashell, delete the two keys
   from the applet group in `plasma-org.kde.plasma.desktop-appletsrc`, start**.
3. Without the keys, wanted size comes from `implicitSize()` (L268–286):
   `fullRepresentation.Layout.preferredWidth/Height` if finite and > 0, **else**
   the fullRep item's `implicitWidth/Height`, **else** the host fallback.
4. The host fallback is in `plasma-desktop/desktoppackage/contents/applet/CompactApplet.qml`
   (identical to the installed copy): the `MouseEventListener mainItem` implicit
   size falls back to `iconSizes.sizeForLabels * 35` × `* 25` = **700×500**
   content (+~20px frame) → the observed **720×520 floor**. A bare `Item`
   fullRep root has implicit size 0, so this fallback is what fired for every
   pre-eb4464d build.
5. Final size (L194–208, L288–301): `clamp(wanted, Layout.minimum*,
   min(Layout.maximum*, 95% of screen))`. So `Layout.minimum*` on the fullRep
   **clamps the fallback UP to the design size** — the shipped
   vpsone/stock-monitor-widget pattern.

## 2. What we ship

`fullRepresentation: Item { Layout.minimumWidth: 960; Layout.minimumHeight: 640 }`
— harness-verified (§4). `Layout.preferred*` would also work (step 3 reads it
first) but only one mechanism is set, per one-change-at-a-time.

## 3. Chart layout reflow (fixed alongside)

Headless trace (`HARNESSGeometry` channel, ms stamps) of the popup-open
lifecycle **before** the fix: chart item 920×469 → 920×239 → … → 920×417, one
paint per size, data arriving into the 239px state. Cause: `fetchMarkets()`
appends each market tile to `marketM` only inside its own XHR callback, so the
fixed-height tile strip grew response-by-response — every append reflowed the
popup and resized/re-painted the chart. With a slow fetch the truncated state
lingered for seconds (what v2/v4 screenshots caught).

Fix: `seedMarkets()` appends all six placeholder tiles synchronously in
`Component.onCompleted`; fetches then only `set()` values. After the fix the
trace is: one creation pass (469, n=0, invisible) → **single paint at final
920×417 with data**. The first layout pass is the final one.

Related but orthogonal: 51bf87d fixed dpr double-scaling in PriceChart paints
(labels off-canvas on dpr-2 sessions). Both fixes verified together in the
final harness run.

## 4. Verified numbers (AC2/AC3/AC4)

Nested session: private DBus socket, `kwin_wayland --virtual 1920x1080`
(socket `kstok-h1`), `plasmashell --no-respawn` with fake HOME, software
rendering, auto-open Timer (scripting-API `expanded` is a no-op on 6.7).

- fullRep content item: **960×641** (960×640 design + CompactApplet's 1px
  panel-separator `extraHeight`), dpr 1
- popup window: 968×649 @ (944,375) = content + 4px/side frame padding
- chart item 920×417, plot ih=383, single data paint at final size
- headroom (from the paint code's own mapping, not pixels): trough y=356,
  plot bottom y=393 → **37px = 9.7% of plot height** clear space (the
  `head = (max-min)*0.12` padding folded into the padded range = 12% of data
  span). Trough does not touch the plot bottom; min-gridline label and date
  ticks ("MMM d") render below the plot at the right edge (vision-confirmed
  on the 960×641 screenshot `popup-content-v6.png`).

## 5. Panel / chip diagnosis (AC5)

Live panel via `busctl … evaluateScript` (panels()/widgets() geometry):

- chip: 132×34 @ x=1392, y=8 — on a 46px-tall bar, 34px cell at y8 ≈ centered;
  no vertical spill (cluster y13–80 impression came from the popup, not the bar)
- chip→clock gap: 39px = 4px inner pad + 31px clock inner padding + 4px —
  target "~35px even" is effectively met; the *perceived* growth is the
  expanding spacer, not new elements
- the "5 unidentified elements" left of the chip are: kickoff, **icontasks
  (749px — 7 pinned tasks)**, **marginsseparator (1px, invisible)**,
  **panelspacer (568px, expanding)** — no new widgets were added; the spacer
  absorbs all slack when icontasks grows with pins
- conclusion: no stocktick-caused panel defect; chip fixed at 132px was a
  hit-target issue, addressed by 9d36250 (self-measuring cell)

## 6. Harness runbook

Workspace harness (private DBus + dedicated socket + HARNESSGeometry channel):

```sh
export HOME=/home/gdeyoung
cd <workspace>/t_995d223d/harness
bash session.sh start                     # dbus-daemon + kwin_wayland --virtual
REPO=$HOME/work/bazzite-customizations bash build-variant.sh   # verbatim-copy variant
eval "$(bash session.sh env)"             # client env (kpackagetool6, busctl)
kpackagetool6 -t Plasma/Applet -u ../build/stocktick-harness
bash session.sh shell                     # fresh plasmashell, auto-opens popup
bash session.sh shot shots/X.png          # spectacle via nested wayland socket
journalctl --user _COMM=plasmashell --since "1 min ago" | grep -a HARNESSGeometry
bash session.sh stop
```

Variant contract: plugin id `com.gdeyoung.plasma.stocktick.harness`, auto-open
Timer, `HARNESSGeometry` console.error channel — sizing layer copied verbatim
from the repo tree (builder asserts the anchors). The `tools/` harness
(248bccd) covers the same ground with a DPR-2 variant via `QT_SCALE_FACTOR`.
