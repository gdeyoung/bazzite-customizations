#!/usr/bin/env bash
# Remove the Hermes KRunner runner completely (user-level).
set -euo pipefail
systemctl --user disable --now hermes-runner.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/hermes-runner.service"
rm -f "$HOME/.local/share/krunner/dbusplugins/org.kde.runners.hermes.desktop"
rm -rf "$HOME/.local/share/hermes-runner"
# config + cache intentionally kept: rm -rf ~/.config/hermes-runner ~/.cache/hermes-runner
systemctl --user daemon-reload
systemctl --user restart plasma-krunner.service
echo "removed (config/cache kept — delete ~/.config/hermes-runner to forget settings)"
