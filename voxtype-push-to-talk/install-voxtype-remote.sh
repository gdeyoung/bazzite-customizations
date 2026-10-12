#!/usr/bin/env bash
# Recreate the VoxType push-to-talk dictation setup on a KDE Plasma Wayland box
# (Bazzite / Fedora Kinoite, immutable) using a REMOTE WhisperX backend —
# no local model on the desktop.
#
# Proven on: Fedora Kinoite 44 (immutable, rpm-ostree), Plasma 6.7.5 Wayland,
# PipeWire/WirePlumber 0.5.17, glibc 2.43, systemd user units. 2026-10.
# Companion write-up: README.md in this directory.
#
# Everything lands in $HOME — no sudo, no rpm-ostree layering, fully reversible
# (a CLEANUP block prints at the end). Run as the desktop user:
#   ASR_ENDPOINT="http://<your-whisperx-host>:10230" bash install-voxtype-remote.sh
set -euo pipefail

# ── Parameters (override via environment) ─────────────────────────────
VOXTYPE_VERSION="${VOXTYPE_VERSION:-1.1.0}"
# REQUIRED: your whisperx-asr-service endpoint. It must serve the
# OpenAI-compatible route POST /v1/audio/transcriptions (the
# learnedmachine/whisperx-asr-service container does, alongside /asr).
ASR_ENDPOINT="${ASR_ENDPOINT:-}"
HOTKEY_EVDEV_CODE="${HOTKEY_EVDEV_CODE:-127}"   # 127 = KEY_COMPOSE (Menu-position key)
TYPE_DELAY_MS="${TYPE_DELAY_MS:-2}"             # KWin drops zero-delay tails; 2/5/10 verified 5/5
MIC_NODE_PATTERN="${MIC_NODE_PATTERN:-usb-Shure}"  # PipeWire node.name regex for the PTT mic

# Known-good SHA256 for v1.1.0 x86_64-avx2 (verified against release SHA256SUMS.txt)
VOXTYPE_SHA256="e7d5de68cc8fc610c3c961c47f879451db9bee4a2df152e9a66f1078072e7f28"

[ -n "$ASR_ENDPOINT" ] || { echo "ERROR: set ASR_ENDPOINT, e.g. ASR_ENDPOINT=\"http://host:10230\""; exit 1; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
say() { printf '\n==> %s\n' "$*"; }

# ── 0. Preflight ───────────────────────────────────────────────────────
say "Preflight"
command -v curl python3 systemctl >/dev/null
[ -n "${XDG_RUNTIME_DIR:-}" ] || { echo "Run inside the desktop session (no XDG_RUNTIME_DIR)"; exit 1; }
command -v ydotoold >/dev/null || { echo "Install the 'ydotool' package first (distro package manager)"; exit 1; }
# /dev/uinput must be rw for your user. Logind grants this to the seated user
# via ACL on most distros; if missing, the fix is a udev rule + input group
# (needs root). Plain check:
if ! ls -l /dev/uinput | grep -q "$(id -un)\|+"; then
  echo "WARNING: /dev/uinput may not be writable by you — ydotoold may fail."
fi
# Remote backend reachable? (GET / is the health route)
curl -sf -m 8 -o /dev/null "$ASR_ENDPOINT/" && echo "ASR endpoint OK: $ASR_ENDPOINT" \
  || echo "WARNING: $ASR_ENDPOINT did not answer / — continuing anyway"

# ── 1. Voxtype binary (standalone avx2; NOT the 374MB rpm — remote mode
#      needs none of the bundled GPU runtimes) ──────────────────────────
say "Installing voxtype $VOXTYPE_VERSION -> ~/.local/bin"
mkdir -p ~/.local/bin
curl -sfL -o "$WORKDIR/voxtype" \
  "https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/voxtype-${VOXTYPE_VERSION}-linux-x86_64-avx2"
echo "$VOXTYPE_SHA256  $WORKDIR/voxtype" | sha256sum -c -
install -m 0755 "$WORKDIR/voxtype" ~/.local/bin/voxtype
~/.local/bin/voxtype --version

# ── 2. Config: remote backend + hotkey + paced typing ─────────────────
say "Writing ~/.config/voxtype/config.toml"
mkdir -p ~/.config/voxtype
cat > ~/.config/voxtype/config.toml <<EOF
# Voxtype push-to-talk via remote WhisperX — installed $(date +%F) by install-voxtype-remote.sh

[whisper]
mode = "remote"                      # v1.1.0: 'mode', NOT 'backend' (deprecated)
remote_endpoint = "${ASR_ENDPOINT}"
language = "en"

[hotkey]
key = "EVTEST_${HOTKEY_EVDEV_CODE}"  # raw kernel code; not all keys have builtin names
mode = "push_to_talk"
cancel_key = "ESC"

[audio]
sample_rate = 16000
device = "default"
pause_media = true
max_duration_secs = 120

[output]
mode = "type"
# KWin accepts zero-delay typing bursts then silently drops the tail of long
# dictations (intermittent ~20-char truncation). Nonzero delay is REQUIRED.
type_delay_ms = ${TYPE_DELAY_MS}
EOF

# ── 3. ydotoold as a USER service (injection backend; unprivileged via the
#      logind uinput ACL — no input-group membership needed) ────────────
say "Installing ydotoold user service"
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/ydotoold.service <<'EOF'
[Unit]
Description=ydotool daemon (uinput injection for voxtype)
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/ydotoold
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now ydotoold

# ── 4. Voxtype daemon service (upstream's own setup command) ───────────
say "Installing + starting voxtype systemd user service"
~/.local/bin/voxtype setup systemd

# ── 5. OSD frontend (recording waveform) — GTK4 variant + layer-shell lib
#      extracted from the Fedora rpm (not packaged on Kinoite) ──────────
say "Installing OSD frontend (GTK4)"
curl -sfL -o "$WORKDIR/osd" \
  "https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/voxtype-${VOXTYPE_VERSION}-linux-x86_64-osd"
curl -sfL -o "$WORKDIR/osd-gtk4" \
  "https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/voxtype-${VOXTYPE_VERSION}-linux-x86_64-osd-gtk4"
install -m 0755 "$WORKDIR/osd" ~/.local/bin/voxtype-osd
install -m 0755 "$WORKDIR/osd-gtk4" ~/.local/bin/voxtype-osd-gtk4.real
mkdir -p ~/.local/lib/voxtype-osd
# layer-shell lib: pick your Fedora release's package page under .../releases/<N>/Everything/x86_64/os/Packages/g/
LS_URL="${LS_URL:-https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Everything/x86_64/os/Packages/g/gtk4-layer-shell-1.3.0-1.fc44.x86_64.rpm}"
curl -sfL -o "$WORKDIR/layer-shell.rpm" "$LS_URL"
(cd ~/.local/lib/voxtype-osd && rpm2cpio "$WORKDIR/layer-shell.rpm" | cpio -idmu --quiet)
# wrapper injects the lib path; the daemon execs 'voxtype-osd' which dispatches
cat > ~/.local/bin/voxtype-osd-gtk4 <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$HOME/.local/lib/voxtype-osd/usr/lib64:${LD_LIBRARY_PATH:-}"
exec "$HOME/.local/bin/voxtype-osd-gtk4.real" "$@"
EOF
chmod +x ~/.local/bin/voxtype-osd-gtk4

# ── 6. Kill the Menu-key context-menu via a KWin no-op shortcut.
#      ONLY relevant when the hotkey is KEY_COMPOSE (Menu keysym opens
#      right-click menus in Qt apps). NO XKB remap — it would map the key
#      onto Right Ctrl and only fix XWayland apps until re-login anyway.
#      KWin consumes the key above all apps; voxtype reads raw evdev below.
say "Installing KWin menu-key neutralizer"
mkdir -p ~/.local/share/kwin/scripts/voxtypemenukill/contents/code
cat > ~/.local/share/kwin/scripts/voxtypemenukill/metadata.json <<'EOF'
{
  "KPlugin": {
    "Id": "voxtypemenukill",
    "Name": "Voxtype Menu Neutralizer",
    "Description": "Consumes the Menu key so no context menu opens; voxtype reads the raw key below KWin",
    "Version": "1.0",
    "License": "MIT"
  },
  "X-Plasma-API": "javascript"
}
EOF
cat > ~/.local/share/kwin/scripts/voxtypemenukill/contents/code/main.js <<'EOF'
registerShortcut(
  "voxtypeMenuNeutralizer",
  "Voxtype Menu Neutralizer (no-op)",
  "Menu",
  function () { /* swallow the key */ }
);
EOF
kwriteconfig6 --file kwinrc --group Plugins --key voxtypemenukillEnabled true
gdbus call --session --dest org.kde.KWin --object-path /Scripting \
  --method org.kde.kwin.Scripting.loadScript \
  "$HOME/.local/share/kwin/scripts/voxtypemenukill/contents/code/main.js" >/dev/null || true
gdbus call --session --dest org.kde.KWin --object-path /KWin \
  --method org.kde.KWin.reconfigure >/dev/null || true

# ── 7. Keep the PTT mic always RUNNING (PipeWire auto-suspend eats the
#      first words after idle via device-resume latency) ────────────────
say "WirePlumber: disable auto-suspend for mic pattern: $MIC_NODE_PATTERN"
mkdir -p ~/.config/wireplumber/wireplumber.conf.d
cat > ~/.config/wireplumber/wireplumber.conf.d/51-ptt-mic-no-suspend.conf <<EOF
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "~alsa_input.*${MIC_NODE_PATTERN}.*" }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF
systemctl --user restart wireplumber

# ── 8. Verify ──────────────────────────────────────────────────────────
say "Verification"
systemctl --user is-active --quiet ydotoold  && echo "OK  ydotoold active"
systemctl --user is-active --quiet voxtype   && echo "OK  voxtype active"
if command -v espeak-ng >/dev/null; then
  espeak-ng -v en-us -s 160 -w "$WORKDIR/t.wav" "Testing remote dictation. The quick brown fox jumps over the lazy dog."
  echo "    end-to-end transcribe test:"
  ~/.local/bin/voxtype transcribe "$WORKDIR/t.wav"
else
  echo "    (espeak-ng not installed — skip the end-to-end sample test)"
fi

cat <<'EOF'

DONE. Hold the push-to-talk key, speak, release.
 - Journal:      journalctl --user -u voxtype -f
 - Reconfigure:  voxtype configure
 - If typed text truncates intermittently: raise output.type_delay_ms through 5, then 10.
 - Known limits: ydotool types raw US keycodes (non-US layouts garble);
                 OSD crash exit 127 = layer-shell wrapper LD_LIBRARY_PATH.

CLEANUP (full removal):
  systemctl --user disable --now voxtype ydotoold
  rm -rf ~/.local/bin/voxtype ~/.local/bin/voxtype-osd ~/.local/bin/voxtype-osd-gtk4{,.real} \
         ~/.config/voxtype ~/.config/systemd/user/{voxtype,ydotoold}.service \
         ~/.local/lib/voxtype-osd ~/.local/share/kwin/scripts/voxtypemenukill \
         ~/.config/wireplumber/wireplumber.conf.d/51-ptt-mic-no-suspend.conf
  kwriteconfig6 --file kwinrc --group Plugins --key voxtypemenukillEnabled --delete
  systemctl --user daemon-reload && systemctl --user restart wireplumber
EOF
