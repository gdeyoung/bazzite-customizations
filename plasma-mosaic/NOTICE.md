# Notice

plasma-mosaic is a KDE Plasma 6 port of **Mosaic** by Naol Selemon
(https://github.com/naolselemon/mosaic), MIT licensed.

- `contents/lib/mosaic/*.py` and `contents/lib/mosaic/en.json` are vendored
  BYTE-IDENTICAL from upstream (see PORT-NOTES.md ledger) and remain under the
  upstream MIT license (LICENSE in this directory is the upstream license text).
- `contents/icons/mosaic.svg` is the upstream Mosaic mark.
- Everything else (host orchestration layer, QML, tests for the host layer,
  docs) is new code for the Plasma port, MIT, Greg DeYoung.
- Mosaic's UI inspiration is credited upstream to Screen Time by ax1g.
