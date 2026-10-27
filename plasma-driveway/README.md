# Plasma Driveway

Every drive you own, one click from the KDE Plasma 6 panel — a **Driveway** chip that
expands into a three-section popup: **Drives** (USB/local disks with usage bars, plus a
read-only System row), **Shares** (config-defined SMB/NFS/sshfs entries with live
mounted state), **Cloud** (rclone remotes on supervised systemd user units with health
states, quotas and pending-upload badges).

Ported from the author's own [omarchy-driveway](https://github.com/gdeyoung/omarchy-driveway)
(Hyprland/Quickshell bar plugin) to native Plasma 6 — the python engine is vendored
**byte-identical**, only the QML layer was rewritten. User-level only: no sudo, no
compiling, no rpm-ostree layering; survives Bazzite/ostree updates.

```
panel chip:      󰇅 3          ← drive glyph + mounted count (dim when nothing mounted,
                                  negative-text colored when a cloud remote failed or a drive hit the full threshold)
popup:           Drives · Shares · Cloud
```

## What runs what

The plasmoid shells out to the driveway CLI (`contents/scripts/driveway` →
`contents/lib/driveway/*.py`) via Plasma's `executable` dataengine
(`org.kde.plasma.plasma5support`):

| Purpose | Command (fired per poll / per click) |
|---|---|
| Drives tab data | `driveway list --thumb-max-gb N [--min-unmounted-mb N] [--no-network] [--no-unmounted]` |
| Cloud tab data | `driveway cloud status` |
| Mount a disk | `driveway action mount --dev <dev> --name <label>` (udisksctl, no root) |
| Unmount/eject | `driveway action eject --mode udisks|fuse|gio|loop …` (busy-process aware) |
| LUKS unlock | terminal command from config (passphrase typed in a real terminal, never the widget) |
| Cloud mount/unmount | `driveway cloud mount|unmount <remote>` (starts/stops `driveway-cloud@<remote>.service`) |
| Share unmount | `driveway netmap unmount <url>` (gio) |
| Share mount | configurable command, default `xdg-open <url>` (file managers mount smb:// etc. natively) |
| Open | `xdg-open <path>` |

Full command inventory and security notes: upstream
[README](https://github.com/gdeyoung/omarchy-driveway#what-the-plugin-runs). No secrets
pass through the widget; engine is stdlib-only python.

## v0.1 scope decisions (deliberate)

Recorded so future-us knows these were choices, not omissions:

1. **No resident daemon.** The Omarchy plugin runs a `udevadm monitor` child for
   instant plug/unplug reaction. v0.1 matches that plugin's own current *panel-only*
   deployment instead: the popup polls every 2 s while open and every
   `pollIntervalSec` (default 10 s) while closed. A plugged-in drive appears within
   one poll tick. Roadmap v0.2: KWin/udev event bridge if instant reaction is wanted.
2. **NetMapWizard and CloudAddWizard UIs are not ported.** Their function is covered by
   config fields here: the Cloud tab lists whatever remotes exist in `rclone config`
   (optionally filtered), and shares are declared as config entries (below). In-panel
   LAN browsing (avahi/smbclient) and OAuth sign-in flows stay on the Omarchy side for
   now — roadmap v0.2.
3. **Host-specific inventory lives in config, not code.** This is a public repo; no LAN
   specifics are hardcoded anywhere (house rule).

## Prerequisites

- Plasma 6.3+ (any Fedora Atomic / Bazzite / Kinoite or standard distro).
- `python3` at `/usr/bin/python3` or on PATH — **stdlib only** (verified: the engine
  imports argparse/json/os/re/select/signal/subprocess/sys/time/socket/threading/
  urllib.request/http.client/pathlib/tempfile/shutil/secrets/stat/pty — no pip packages).
  `install.sh` checks this.
- `lsblk`, `findmnt` (util-linux) — enumeration; standard everywhere.
- `udisks2` (`udisksctl`) — disk mount/unlock/eject actions without root.
- Optional: `rclone` — Cloud tab; without it the tab shows a hint instead of remotes.
- Optional (Shares tab unmount lane): `gio` (glib2) — used by `driveway netmap unmount`.

`install.sh` verifies the hard prerequisites and degrades gracefully on the optional
ones.

## Configuration (widget settings)

All keys are KConfig XT (`contents/config/main.xml`); gear icon on the widget, or
right-click → Configure Driveway:

| Key | Default | Meaning |
|---|---|---|
| `pollIntervalSec` | 10 | Poll while the popup is closed (2 s while open) |
| `showNetwork` | true | Include network/cloud rows in `driveway list`, poll cloud status |
| `showUnmounted` | true | Show plugged-in-but-unmounted drives with a Mount button |
| `thumbMaxGb` | 256 | USB disks ≤ this size classify as thumb drives |
| `minUnmountedMb` | 64 | Hide unmounted partitions under this (EFI/boot helpers) |
| `fullWarnPct` | 90 | Usage bars / chip turn urgent at this fill % |
| `glyphFontFamily` | *(empty)* | Nerd Font family for drive glyphs (install one for the 󰇅 icons; falls back to the default font) |
| `cloudRemotes` | *(empty)* | Comma/space list to filter the Cloud tab; empty = all remotes |
| `unlockCommand` | `konsole -e udisksctl unlock -b {dev}` | Terminal command for LUKS unlock; `{dev}` substituted |
| `sharesJson` | `[]` | Share inventory — see below |

### `sharesJson` schema

A JSON array; each entry renders one row in the Shares tab:

```json
[
  {
    "id": "nas-media",
    "label": "NAS media",
    "url": "smb://nas/media",
    "mountpoint": "/run/user/1000/gvfs/smb-share:server=nas,share=media",
    "scheme": "smb",
    "fstype": "SMB",
    "mountCommand": "gio mount smb://nas/media"
  }
]
```

- `mountpoint` is matched exactly against the lister's live network rows — found =
  mounted. For kernel mounts (nfs/sshfs via fstab) use the real mount path; for gvfs
  mounts use the `/run/user/<uid>/gvfs/…` path.
- `mountCommand` is optional (default `xdg-open <url>`). Unmount always goes through
  the engine (`netmap unmount`, gio-based, no root).
- `scheme` picks the glyph (smb/sftp/ftp/nfs/dav/davs).
- The settings page validates the JSON inline and warns when it won't parse.

## Install

```bash
git clone https://github.com/gdeyoung/bazzite-customizations
cd bazzite-customizations/plasma-driveway
./install.sh
```

Parameters (nothing is hardcoded): `DRIVEWAY_DEST` overrides the install directory
(default `~/.local/share/plasma/plasmoids/com.gdeyoung.plasma.driveway`);
`DRIVEWAY_NO_RESTART=1` skips the plasmashell restart. Then: right-click panel →
**Enter Edit Mode** → **Add Widgets** → search **Driveway** → drag to panel.

Cloud tab first use: the engine installs the `driveway-cloud@.service` unit template
into `~/.config/systemd/user/` automatically on the first cloud mount (or copy
`contents/systemd/driveway-cloud@.service` there and `systemctl --user daemon-reload`
yourself).

## Rollback / remove

```bash
kpackagetool6 -t Plasma/Applet -r com.gdeyoung.plasma.driveway
systemctl --user restart plasma-plasmashell.service
# optional engine state (only if you used the Cloud tab):
systemctl --user stop 'driveway-cloud@*' 2>/dev/null
rm -f ~/.config/systemd/user/driveway-cloud@.service && systemctl --user daemon-reload
rm -rf ~/.config/driveway
```

Nothing else is touched — the widget lives entirely under `~/.local/share/plasma/`.

## Install-day verification plan (run when Greg is back)

Not run during the build — no live-shell changes while away. In order:

1. `./install.sh`, add widget to panel, confirm the chip renders with a mounted count.
2. `journalctl --user -u plasma-plasmashell.service | grep -i driveway` — no QML
   errors naming these files.
3. `bash ~/.local/share/plasma/plasmoids/com.gdeyoung.plasma.driveway/contents/scripts/driveway list`
   — one JSON line; verify `drives[]` includes the System row and any USB disks.
4. Open the popup: all three tabs render; Drives rows show usage bars; Shares shows
   configured entries with live state; Cloud shows remotes (if rclone present).
5. Cloud tab: click Mount on a remote → unit starts, state chip flips to Mounted.
6. Insert a USB stick → row appears within one poll tick (≤10 s closed / ≤2 s open) →
   Mount → Open → Eject (busy-apps dialog if something holds files open).
7. Shares tab: Unmount a mounted share → state flips to not-mounted.
8. Desktop-containment instance test for popup compile, then remove it (per skill).

## Provenance

- Upstream: github.com/gdeyoung/omarchy-driveway @ `9034ef8` (vendored 2026-10-26;
  engine copied byte-identical — `lib/driveway/*.py` verified by sha256 against the
  source tree).
- Engine vendored-code lineage (jgarza9788/drives, bmaltais/StartDrive,
  jonspinks/omarchy-rclone): see [NOTICE.md](NOTICE.md), copied verbatim.
- QML layer rewritten Quickshell → Plasma 6 per the plasma-plasmoid-development skill;
  `Model.js` reused byte-identical (pure ES5, no Quickshell deps).
- License: MIT — see [LICENSE](LICENSE).

## Development

```bash
tools/check_qml.py plasma-driveway        # from repo root; static QML check
python3 -m py_compile plasma-driveway/contents/lib/driveway/*.py
bash plasma-driveway/contents/scripts/driveway --help
```

House port rules honored: `PlasmoidItem` root with compact/full direct children;
`plasma5support 2.0` unaliased + versioned; `onNewData` formal params (never
`in connectedSources`); one handler per signal per file (buttons funnel through
`ActionIconButton` + Repeater dispatch); `Qt.resolvedUrl`; no `smallRadius`; no
`Layout.horizontalAlignment`; theme colors only; popup self-sizes to the visible tab;
`DriveRow` is a `RowLayout` with PC3 controls.
