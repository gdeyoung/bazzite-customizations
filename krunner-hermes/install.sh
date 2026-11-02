#!/usr/bin/env bash
# Install the Hermes KRunner runner (user-level, reversible).
# NOTE: review-first software — read before running. Nothing here needs sudo.
#
# Usage:
#   ./install.sh                                  # defaults
#   ./install.sh --litellm-url http://HOST:4000/v1 --model local-fast \
#                --api-key-env ZHW_PROXY_API_KEY --api-key-file ~/.hermes/secrets/infra.env \
#                --web-search-url http://192.168.1.249:8787/search?q=%s --web-search-name SEARXNG
set -euo pipefail

LITELLM_URL="http://localhost:4000/v1"
MODEL="local-fast"
API_KEY_ENV="LITELLM_API_KEY"
API_KEY_FILE=""
WEB_SEARCH_URL="https://duckduckgo.com/?q=%s"
WEB_SEARCH_NAME="DUCKDUCKGO"
FORCE_CONFIG=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --litellm-url) LITELLM_URL="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --api-key-env) API_KEY_ENV="$2"; shift 2 ;;
    --api-key-file) API_KEY_FILE="$2"; shift 2 ;;
    --web-search-url) WEB_SEARCH_URL="$2"; shift 2 ;;
    --web-search-name) WEB_SEARCH_NAME="$2"; shift 2 ;;
    --force-config) FORCE_CONFIG=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

SRC="$(cd "$(dirname "$0")" && pwd)"
SHARE="$HOME/.local/share/hermes-runner"
CONF="$HOME/.config/hermes-runner/config.json"

mkdir -p "$SHARE" "$HOME/.local/share/krunner/dbusplugins" "$HOME/.config/systemd/user"

# 1. daemon + desktop spec + unit
install -m 0755 "$SRC/hermes_runner.py" "$SHARE/hermes_runner.py"
install -m 0755 "$SRC/apps_model.py" "$SHARE/apps_model.py"   # v0.6 launcher lane
install -m 0644 "$SRC/README.md" "$SHARE/README.md"   # `hermes docs` opens it
install -m 0644 "$SRC/org.kde.runners.hermes.desktop" \
        "$HOME/.local/share/krunner/dbusplugins/org.kde.runners.hermes.desktop"
install -m 0644 "$SRC/hermes-runner.service" \
        "$HOME/.config/systemd/user/hermes-runner.service"

# 2. config (existing config is kept unless --force-config)
if [[ ! -f "$CONF" || "$FORCE_CONFIG" -eq 1 ]]; then
  API_KEY_FILE="${API_KEY_FILE/#\~/$HOME}"
  mkdir -p "$(dirname "$CONF")"   # silent cat-fail bug: daemon ran on defaults
  cat > "$CONF" <<EOF
{
  "answer_prefix": "ai",
  "task_prefix": "hr",
  "litellm": {
    "base_url": "${LITELLM_URL%/}",
    "model": "${MODEL}",
    "timeout_s": 45,
    "api_key_env": "${API_KEY_ENV}",
    "api_key_file": "${API_KEY_FILE}"
  },
  "max_answer_chars": 700,
  "copy_answers": true,
  "notify_icon": "help-browser",
  "web_search_url": "${WEB_SEARCH_URL}",
  "web_search_name": "${WEB_SEARCH_NAME}"
}
EOF
  echo "wrote $CONF"
else
  echo "keeping existing $CONF"
fi

# 3. sanity: the runtime pieces the daemon needs
/usr/bin/python3 - <<'PY'
import dbus, gi  # noqa
print("python3-dbus + gobject present")
PY
command -v notify-send >/dev/null || echo "WARN: notify-send not found (notifications will be skipped)"

# 4. start (restart, not enable --now — that no-ops on a running service and
# leaves the old code in memory; bit us twice on 2026-10-31)
systemctl --user daemon-reload
systemctl --user enable hermes-runner.service
systemctl --user restart hermes-runner.service
sleep 1
busctl --user status org.kde.runners.hermes >/dev/null 2>&1 \
  || { echo "runner did not own the bus name; check: journalctl --user -u hermes-runner -e"; exit 1; }
systemctl --user restart plasma-krunner.service

echo
echo "OK. In KRunner (Alt+Space or Super+Space) try:"
echo "  apps                  # browse: pins, most-used, categories (↓ + Enter)"
echo "  apps games            # category drill (or Enter on a category row)"
echo "  apps pins             # favorites only; pin/unpin via row buttons"
echo "  ai what is the fleet LiteLLM alias for GLM-5.3"
echo "  hr check the jellyfin service health and notify me"
