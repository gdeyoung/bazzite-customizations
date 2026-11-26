# Plasma WeatherX

Weather glyph + current temperature in the KDE Plasma 6 panel — click for the
tabbed popup: **Here** (device location from widget settings) plus pinned
places, current conditions with feels-like and H/L, a details grid with level
bars (wind, gusts, humidity, pressure, UV, dew point, AQI, rain chance), a
remaining-hours strip starting at NOW, the 7-day forecast, sun times, and a
live **keyless radar map** (Esri dark basemap + RainViewer precipitation
overlay) beside the 7-day. Right-click the panel chip to cycle the bar label
mode (temp → temp + condition → icon only).

Ported from the author's own Omarchy bar plugin
[gdeyoung.weather](https://github.com/gdeyoung/omarchy-weather) (Quickshell) to
native Plasma 6 — same data logic, same glyphs, same behavior. Pure QML, no
compiled code, no daemons, no system mutations, no API keys.

```
panel (compact):  ⛅ 72°              ← click opens popup; right-click cycles label
popup:            Here · Chicago · ＋
                  ⛅ 72°  Partly cloudy
                  Feels 70°   H 75° L 48°
                  Details · Next hours · 7-Day + Radar · Sunrise/Sunset
```

## Provenance

- Source: [github.com/gdeyoung/omarchy-weather](https://github.com/gdeyoung/omarchy-weather)
  at commit `93758c0` (clone used for the port).
- `contents/ui/Model.js` is **verbatim** from that upstream (pure helpers —
  WMO code table, URL builders, tile math, formatters) with exactly two
  documented deltas, marked in its header:
  - `STATE_DIR` → `~/.cache/gdeyoung.weatherx/` (was
    `~/.local/state/gdeyoung.weather/` on Omarchy; cache location for the
    Plasma port, no collision with an Omarchy install on the same host),
  - `DEFAULT_PINNED` emptied — this is a public repo and no personal
    coordinates ship in defaults.
- Fetch pipeline, glyph set, layout and behavior mirror
  `BarWidget.qml`/`Panel.qml` from the same commit; only the container QML
  (Quickshell → PlasmoidItem/DataSource/KConfig XT) was rewritten.

## Data sources (no API keys)

- Forecast + air quality: [Open-Meteo](https://open-meteo.com/)
- Geocoding (city search for pinned tabs): Open-Meteo geocoding API
- Radar frames: [RainViewer](https://www.rainviewer.com/) public weather maps
- Radar basemap + labels: Esri World Dark Gray Canvas tiles

Fetches write one merged JSON per location into `~/.cache/gdeyoung.weatherx/`
(atomic tmp+mv via `jq`) — the panel chip and every popup tab read the same
files, so they can never disagree.

## Configuration

Configured through the widget's own settings dialog (gear ⚙ in the popup, or
the widget context menu → Configure WeatherX…). Keys (KConfig XT, group
`General`):

| Key | Default | Meaning |
|---|---|---|
| `latitude` / `longitude` | `0` / `0` (**unset**) | Home coordinates, decimal degrees. `0,0` counts as unset — the widget shows a first-run hint until set. |
| `locationName` | *(empty)* | Label for the Here tab. If set without coordinates, it geocodes on first refresh. |
| `units` | `imperial` | `imperial` (°F, mph) or `metric` (°C, km/h) |
| `barExtra` | `temp` | Bar label mode: `temp` / `tempcondition` / `icon` |
| `refreshMin` | `15` | Forecast refresh interval, minutes (min 5) |
| `pinnedLocations` | `[]` | JSON array of `{name, lat, lon}` — managed by the ＋ button in the popup; click a pinned tab twice to remove it |

The location **defaults to empty**: this is a public repo, so no personal
coordinates ship. Enter e.g. `40.7128, -74.0060` (example only) in settings,
or pin cities via the popup's ＋ search.

## Install

```bash
git clone https://github.com/gdeyoung/bazzite-customizations
cd bazzite-customizations/plasma-weatherx
./install.sh          # or: WX_DEST=/tmp/test-plasmoids ./install.sh for a dry-run copy
```

No sudo, no compiling, no layering — installs to
`~/.local/share/plasma/plasmoids/com.gdeyoung.plasma.weatherx` and survives
Bazzite/ostree updates. Then: right-click panel → **Enter Edit Mode** →
**Add Widgets** → search **WeatherX** → drag to the panel.

Rollback / remove:

```bash
kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.weatherx
systemctl --user restart plasma-plasmashell.service
rm -rf ~/.cache/gdeyoung.weatherx   # optional: cached forecasts
```

## Verify (install day)

This port is code-complete but **not installed** — verified statically only.
On install day, in order (per the plasma-plasmoid-development skill):

1. `tools/check_qml.py plasma-weatherx` → 0 errors (done pre-commit).
2. Install, add to panel, open popup once — the chip shows 🌡️ until a
   location is set; the popup shows the first-run hint with a Configure button.
3. Set latitude/longitude in settings → within ~15 s the chip shows a temp;
   heartbeat `/tmp/plasma-weatherx-hb.json` advances on every fetch (it
   carries `{t, key, temp}`; two reads ~20 s apart during a manual ⟳ refresh
   prove the dataengine chain end to end).
4. `journalctl --user -u plasma-plasmashell.service` — grep `weatherx`, no
   QML errors naming these files.
5. Radar: popup shows "radar loading…" → tiles within a few seconds; the
   "© Esri · RainViewer" attribution line renders with frame age. ⟳ refetches;
   "Radar ↗" opens windy.com for the active tab.
6. ＋ search a city (e.g. "Chicago"), click a result → pinned tab appears and
   fetches; click that tab again to remove it. Restart plasmashell → pinned
   tabs persist (KConfig).
7. Desktop-containment instance for a popup compile test at icon size
   (geometry numbers there are garbage — proof of compilation only), then
   remove it.

## Why (design notes)

- **Same file bus as upstream** — one merged JSON per location under
  `~/.cache/gdeyoung.weatherx/`; fetch pipelines return the merged JSON on
  stdout too, so the bar chip updates the instant a fetch lands. Every jq runs
  with `-c`: state files and probe stdout are ONE strict JSON line, and every
  QML handler parses the last stdout line — the fleet's one-line-per-tick
  contract (a pretty-printed state file parses as garbage on last-line reads
  and blanks the widget).
- **Keyless by construction** — every URL lives in `Model.js` (ported
  verbatim); no API keys anywhere.
- **One handler per signal per file** — all clickable chrome is factored into
  `TabChip`/`ChipButton`/`SearchField`/`ResultRow` components because Plasma
  loads the whole applet lazily and a duplicate property handler in ANY
  referenced file blocks the entire applet ("Property value set multiple
  times").
- **Popup self-sizes** to the visible column's implicit height (setup hint,
  search view, or main content); a single 2 s Timer drives both the tab-file
  poll and the 5-min radar frame refetch, with a timestamp cache-buster on the
  RainViewer overlay tiles.
- **User-level only** — nothing outside `$HOME`; survives ostree updates.

## Lineage

Forked conceptually from the author's own
[omarchy-weather](https://github.com/gdeyoung/omarchy-weather) (MIT), whose
radar/attribution strings and behavior this port preserves. Radar imagery ©
RainViewer; basemap © Esri; data © Open-Meteo.

## License

MIT — see [LICENSE](LICENSE).
