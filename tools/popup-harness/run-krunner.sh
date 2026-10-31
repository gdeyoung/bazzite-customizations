#!/usr/bin/env bash
# run-krunner.sh — nested-session gate driver for krunner-hermes. v3.
# v0.2 contract: Match is pure (no fetch on keystrokes); Enter (Run) asks.
# Verifies: help rows, cold ask, Run->fetch->cached answer inline, Actions,
# SetActivationToken, error lane (dead-port daemon relaunch), krunner render
# of both ask and cached-answer states. 'hr' lane: Match + taskrun states are
# unit-tested; Run(task) is NOT fired here (it would spawn a real hermes -z
# agent turn with tool access — verified once, live, at install).
set -u

ROOT=/tmp/stk-harness
PKG_SRC=/var/home/gdeyoung/work/bazzite-customizations/krunner-hermes
TAG="${TAG:-kr5}"
OUT=$ROOT/shots
mkdir -p "$OUT" "$ROOT/home"

export QT_QPA_PLATFORM=wayland
export LIBGL_ALWAYS_SOFTWARE=1
export XDG_RUNTIME_DIR=/run/user/1000

kwin_wayland --virtual --no-lockscreen --width 2560 --height 1440 \
    > "$ROOT/kwin-krunner-$TAG.log" 2>&1 &
KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/wayland-1" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY=wayland-1

H="$ROOT/home/kr-$TAG"
rm -rf "$H"
export HOME="$H"
export XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_CACHE_HOME="$H/.cache"

mkdir -p "$XDG_DATA_HOME/krunner/dbusplugins" "$XDG_DATA_HOME/hermes-runner" \
         "$H/.config/hermes-runner"
install -m 0755 "$PKG_SRC/hermes_runner.py" "$XDG_DATA_HOME/hermes-runner/hermes_runner.py"

# --- single .desktop: the repo form (variants proved equivalent in kr2-kr4)
DBP="$XDG_DATA_HOME/krunner/dbusplugins"
install -m 0644 "$PKG_SRC/org.kde.runners.hermes.desktop" \
        "$DBP/org.kde.runners.hermes.desktop"

# harness config (dir created explicitly — v1 silent-fail bug)
cat > "$H/.config/hermes-runner/config.json" <<'EOF'
{
  "answer_prefix": "ai",
  "task_prefix": "hr",
  "litellm": {
    "base_url": "http://192.168.1.243:4000/v1",
    "model": "local-fast",
    "timeout_s": 30,
    "api_key_env": "ZHW_PROXY_API_KEY",
    "api_key_file": "/var/home/gdeyoung/.hermes/secrets/infra.env"
  },
  "notify": true
}
EOF
# dead-port config for the error-lane daemon (second instance)
sed 's#http://192.168.1.243:4000/v1#http://127.0.0.1:9/v1#' \
    "$H/.config/hermes-runner/config.json" \
    > "$H/.config/hermes-runner/config-dead.json"

start_daemon() {  # $1 = extra env (HERMES_RUNNER_CONF)
  /usr/bin/python3 "$XDG_DATA_HOME/hermes-runner/hermes_runner.py" \
      > "$ROOT/runner-$TAG.log" 2>&1 &
  RUNNER_PID=$!
  sleep 2
}
start_daemon

B="busctl --address=$DBUS_SESSION_BUS_ADDRESS"
echo "CKPT-BUS-OWNED=$($B status org.kde.runners.hermes >/dev/null 2>&1 && echo OK || echo FAIL)"

$B monitor > "$ROOT/kr-bus-$TAG.log" 2>&1 &
MON_PID=$!
sleep 1

Q="what port is searxng on watertower"
probe() { $B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "$1" 2>&1 | head -4; }

echo "--- T1 introspect signatures ---"
$B introspect org.kde.runners.hermes /hermes org.kde.krunner1 | grep -E "Match|Run|Actions|SetActivationToken"

echo "--- T2 help rows: 'ai ' / 'hr ' ---"; probe "ai "; probe "hr "
echo "--- T3 cold ask (must NOT fire fetch: no urlopen thread) ---"; probe "ai $Q"
echo "--- T4 Actions() triples ---"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Actions 2>&1 | head -4
echo "--- T5 SetActivationToken (no-op, no error) ---"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 SetActivationToken s "tok" && echo TOKEN-OK

echo "--- T6 Run on ask row fires the fetch ---"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "ask:$Q" ""
sleep 10
echo "--- T7 cached answer inline (retype) ---"; probe "ai $Q"
echo "--- T8 Run on answer row (clipboard fallback->notify, no crash) ---"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "answer:$Q" ""

echo "--- T9 hr match-only rows (cold + running shape via fresh key) ---"
probe "hr rebuild the nas index"
probe "hermes"

echo "--- T10 error lane: relaunch daemon on dead port ---"
kill $RUNNER_PID 2>/dev/null; sleep 1
HERMES_RUNNER_CONF="$H/.config/hermes-runner/config-dead.json" \
    /usr/bin/python3 "$XDG_DATA_HOME/hermes-runner/hermes_runner.py" \
    > "$ROOT/runner-dead-$TAG.log" 2>&1 &
RUNNER_PID=$!
sleep 2
EQ="will this fail fast"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "ask:$EQ" ""
sleep 4
probe "ai $EQ"     # expect error: row + ENTER RETRIES
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "error:$EQ" "" && echo RETRY-OK
sleep 4
probe "ai $EQ"     # still error (dead port), never cached as an answer

# --- error-lane daemon done: back to the good config for krunner render ---
kill $RUNNER_PID 2>/dev/null; sleep 1
start_daemon

# warm the fresh daemon's cache so the answer-state shot shows the cached row
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "ask:$Q" ""
sleep 10

export XDG_DATA_DIRS="$XDG_DATA_HOME:/usr/local/share:/usr/share"
QT_LOGGING_RULES="*.debug=false;kf.krunner*.debug=true" krunner --replace \
    > "$ROOT/krunner-$TAG.log" 2>&1 &
KRUNNER_PID=$!
sleep 10
echo "--- krunner hermes lines ---"
grep -iE "hermes" "$ROOT/krunner-$TAG.log" | head -6 || echo "(none in krunner log; check journal)"

FQ="ai who wrote the left hand of darkness"
$B call org.kde.krunner /App org.kde.krunner.App query s "$FQ" \
    > "$ROOT/kr-appquery-$TAG.txt" 2>&1 && echo "CKPT-APP-QUERY=OK" || echo "CKPT-APP-QUERY=FAIL"
sleep 2
spectacle -b -n -o "$OUT/kr-ask-$TAG.png" 2>/dev/null && echo "SHOT-kr-ask"

$B call org.kde.krunner /App org.kde.krunner.App query s "ai $Q" >/dev/null 2>&1
sleep 2
spectacle -b -n -o "$OUT/kr-answer-$TAG.png" 2>/dev/null && echo "SHOT-kr-answer"

kill $RUNNER_PID $KRUNNER_PID $MON_PID $KWIN_PID 2>/dev/null
sleep 2
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  [ -r "/proc/$pid/cmdline" ] || continue
  cmd=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
  case "$cmd" in
    *hermes_runner.py*|*"kwin_wayland --virtual"*|*"krunner --replace"*) ;;
    *) continue ;;
  esac
  tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -q "^HOME=$H$" || continue
  kill -9 "$pid" 2>/dev/null
done
echo "DONE-$TAG"
