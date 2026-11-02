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

# --- 2026-10-31 isolation (2026-10-30 incident): private XDG_RUNTIME_DIR,
# harness HOME exported BEFORE kwin launch so the environ gate can identify
# and clean every harness process. Self-wrap holds however we're invoked.
H="$ROOT/home/kr-$TAG"
rm -rf "$H"
export HOME="$H"
export XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" XDG_CACHE_HOME="$H/.cache"
if [ -z "${HARNESS_RT_ISOLATED:-}" ]; then
  RT="$ROOT/run"; mkdir -p "$RT"; chmod 700 "$RT" 2>/dev/null || true
  exec dbus-run-session env HARNESS_RT_ISOLATED=1 XDG_RUNTIME_DIR="$RT" \
      HOME="$H" XDG_CONFIG_HOME="$H/.config" XDG_DATA_HOME="$H/.local/share" \
      XDG_CACHE_HOME="$H/.cache" QT_QPA_PLATFORM=wayland \
      LIBGL_ALWAYS_SOFTWARE=1 bash "$0" "$@"
fi
SOCK="wayland-h$$"

kwin_wayland --virtual --no-lockscreen --width 2560 --height 1440 --socket "$SOCK" \
    > "$ROOT/kwin-krunner-$TAG.log" 2>&1 &
KWIN_PID=$!
for i in $(seq 1 30); do [ -S "$XDG_RUNTIME_DIR/$SOCK" ] && break; sleep 0.5; done
export WAYLAND_DISPLAY="$SOCK"

mkdir -p "$XDG_DATA_HOME/krunner/dbusplugins" "$XDG_DATA_HOME/hermes-runner" \
         "$H/.config/hermes-runner"
install -m 0755 "$PKG_SRC/hermes_runner.py" "$XDG_DATA_HOME/hermes-runner/hermes_runner.py"
install -m 0755 "$PKG_SRC/apps_model.py" "$XDG_DATA_HOME/hermes-runner/apps_model.py"

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

# stub hermes for the task lane — MUST be in the config BEFORE the daemon
# starts (kr7 lesson: a post-start sed left the daemon on real-hermes
# autodetect and the harness spawned a genuine agent turn)
cat > "$H/stub-hermes.sh" <<'EOF'
#!/usr/bin/env bash
echo "STUB-START $*"
sleep 3
echo "STUB-TASK-OK $*"
EOF
chmod +x "$H/stub-hermes.sh"
/usr/bin/python3 - "$H" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1]) / ".config/hermes-runner/config.json"
c = json.loads(p.read_text())
c["hermes_exe"] = str(pathlib.Path(sys.argv[1]) / "stub-hermes.sh")
p.write_text(json.dumps(c, indent=2))
PY
# dead-port config for the error-lane daemon (second instance)
sed 's#http://192.168.1.243:4000/v1#http://127.0.0.1:9/v1#' \
    "$H/.config/hermes-runner/config.json" \
    > "$H/.config/hermes-runner/config-dead.json"

# --- §L launcher lane (v0.6): fixture apps + stub kioclient BEFORE the
# daemon starts (which() resolves from the daemon's inherited PATH; the
# stub guarantees the harness never performs a real launch)
mkdir -p "$H/.local/share/applications" "$H/stub-bin"
cat > "$H/.local/share/applications/hxfire.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=HermesFire
GenericName=Harness Browser
Exec=hxfire %u
Categories=Network;
Keywords=harness;web;
EOF
cat > "$H/.local/share/applications/hxmine.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=HermesMine
GenericName=Harness Game
Exec=hxmine
Categories=Game;
EOF
cat > "$H/.local/share/applications/hxhidden.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=HiddenApp
Exec=hxhidden
NoDisplay=true
EOF
# v0.7 kickoff-favorites fixture: kactivitymanagerd-shaped SQLite under the
# harness HOME — AppStore reads it read-only; favorites must lead the root view
mkdir -p "$H/.local/share/kactivitymanagerd/resources"
/usr/bin/python3 - "$H/.local/share/kactivitymanagerd/resources/database" <<'EOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE ResourceLink (usedActivity TEXT, "
          "initiatingAgent TEXT, targettedResource TEXT)")
c.execute("INSERT INTO ResourceLink VALUES (?,?,?)",
          (":global", "org.kde.plasma.favorites.applications",
           "applications:hxmine.desktop"))
c.execute("INSERT INTO ResourceLink VALUES (?,?,?)",   # noise: other agent
          (":global", "org.kde.plasma.favorites.contacts",
           "applications:hxfire.desktop"))
c.commit(); c.close()
EOF
cat > "$H/stub-bin/kioclient" <<'EOF'
#!/usr/bin/env bash
echo "STUB-KIOCLIENT $*" >> "$HOME/stub-kioclient.log"
EOF
chmod +x "$H/stub-bin/kioclient"
export PATH="$H/stub-bin:$PATH"

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

echo "--- T11 task lane via stub hermes (full Run cycle) ---"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss \
    "task:count to three then stop" ""
sleep 2
probe "hr count to three then stop"          # expect taskrun: RUNNING
sleep 5
probe "hr count to three then stop"          # expect task: again (registry cleared)
grep -c "STUB-TASK-OK" "$H/.cache/hermes-runner/"task-*.log | tail -1

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

# Phase 2: handoffs lane — config injects gh/el/sea; query a gh handoff
python3 - "$H/.config/hermes-runner/config.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["handoffs"] = [
    {"prefix": "gh", "label": "GitHub",
     "url": "https://github.com/search?q=%s"},
    {"prefix": "sea", "label": "SearXNG fleet",
     "url": "http://192.168.1.249:8787/search?q=%s"},
]
json.dump(c, open(p, "w"), indent=1)
PYEOF
kill -HUP $RUNNER_PID 2>/dev/null; sleep 2
# /App query drives the KRunner UI (async, returns void — kr-appquery is
# always 0 bytes); Match on the runner is the deterministic row check.
$B call org.kde.krunner /App org.kde.krunner.App query s "gh krunner hermes" >/dev/null 2>&1
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "gh krunner hermes" \
    > "$ROOT/kr-handoff-$TAG.txt" 2>&1 && echo "CKPT-HANDOFF-QUERY=OK" || echo "CKPT-HANDOFF-QUERY=FAIL"
grep -q "handoff:gh:" "$ROOT/kr-handoff-$TAG.txt" && echo "CKPT-HANDOFF-ROW=OK" || echo "CKPT-HANDOFF-ROW=FAIL"
sleep 1
spectacle -b -n -o "$OUT/kr-handoff-$TAG.png" 2>/dev/null && echo "SHOT-kr-handoff"

# Phase 3: model subcommand — bare list with CURRENT marked
$B call org.kde.krunner /App org.kde.krunner.App query s "ai model" >/dev/null 2>&1
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "ai model" \
    > "$ROOT/kr-model-$TAG.txt" 2>&1 && echo "CKPT-MODEL-QUERY=OK" || echo "CKPT-MODEL-QUERY=FAIL"
grep -q "model-cur:" "$ROOT/kr-model-$TAG.txt" && echo "CKPT-MODEL-CUR=OK" || echo "CKPT-MODEL-CUR=FAIL"
sleep 1
spectacle -b -n -o "$OUT/kr-model-$TAG.png" 2>/dev/null && echo "SHOT-kr-model"

# Phase 4 (v0.5): ssh lane + snippets CRUD + layered help index.
# Synthetic hosts ONLY — never fleet hostnames.
mkdir -p "$H/.ssh"
cat > "$H/.ssh/config" <<'EOF'
# harness synthetic
Host alpha
Host beta b2
  HostName 10.0.0.9
  Port 2222
  User root
Host gamma-*
EOF
python3 - "$H/.config/hermes-runner/config.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
c["snippets"] = [
    {"name": "sig", "text": "Greg DeYoung"},
    {"name": "hello", "text": "synthetic snippet for kr battery"},
]
json.dump(c, open(p, "w"), indent=1)
PYEOF
kill -HUP $RUNNER_PID 2>/dev/null; sleep 2

$B call org.kde.krunner /App org.kde.krunner.App query s "ssh b" >/dev/null 2>&1
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "ssh b" \
    > "$ROOT/kr-ssh-$TAG.txt" 2>&1 && echo "CKPT-SSH-QUERY=OK" || echo "CKPT-SSH-QUERY=FAIL"
grep -q "ssh:beta" "$ROOT/kr-ssh-$TAG.txt" && grep -q "ssh:b2" "$ROOT/kr-ssh-$TAG.txt" \
    && echo "CKPT-SSH-ROWS=OK" || echo "CKPT-SSH-ROWS=FAIL"
grep -q "root@10.0.0.9:2222" "$ROOT/kr-ssh-$TAG.txt" && echo "CKPT-SSH-TARGET=OK" || echo "CKPT-SSH-TARGET=FAIL"
sleep 1
spectacle -b -n -o "$OUT/kr-ssh-$TAG.png" 2>/dev/null && echo "SHOT-kr-ssh"

$B call org.kde.krunner /App org.kde.krunner.App query s ";sig New Sig" >/dev/null 2>&1
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s ";sig New Sig" \
    > "$ROOT/kr-snip-$TAG.txt" 2>&1 && echo "CKPT-SNIP-QUERY=OK" || echo "CKPT-SNIP-QUERY=FAIL"
grep -q "snippet:sig" "$ROOT/kr-snip-$TAG.txt" && grep -q "snippet-save:sig" "$ROOT/kr-snip-$TAG.txt" \
    && echo "CKPT-SNIP-OVERWRITE=OK" || echo "CKPT-SNIP-OVERWRITE=FAIL"
sleep 1
spectacle -b -n -o "$OUT/kr-snip-$TAG.png" 2>/dev/null && echo "SHOT-kr-snip"

$B call org.kde.krunner /App org.kde.krunner.App query s "hermes" >/dev/null 2>&1
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "hermes" \
    > "$ROOT/kr-help-$TAG.txt" 2>&1 && echo "CKPT-HELP-QUERY=OK" || echo "CKPT-HELP-QUERY=FAIL"
for lane in help-ssh help-snippet help-model help-docs help-handoff-gh; do
    grep -q "$lane" "$ROOT/kr-help-$TAG.txt" || { echo "CKPT-HELP-INDEX=FAIL($lane)"; break; }
    echo "CKPT-HELP-INDEX=OK"
done
sleep 1
spectacle -b -n -o "$OUT/kr-help-$TAG.png" 2>/dev/null && echo "SHOT-kr-help"

# --- §L launcher lane probes (v0.6): Match rows, drill, launch, pin ------
echo "--- §L apps lane ---"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "apps" \
    > "$ROOT/kr-apps-$TAG.txt" 2>&1 && echo "CKPT-APPS-ROOT-QUERY=OK" || echo "CKPT-APPS-ROOT-QUERY=FAIL"
grep -q "apps-root" "$ROOT/kr-apps-$TAG.txt" \
    && echo "CKPT-APPS-ANCHOR=OK" || echo "CKPT-APPS-ANCHOR=FAIL"
grep -q "appcat:internet" "$ROOT/kr-apps-$TAG.txt" && grep -q "appcat:games" "$ROOT/kr-apps-$TAG.txt" \
    && echo "CKPT-APPS-CATS=OK" || echo "CKPT-APPS-CATS=FAIL"
grep -q "app:hxhidden.desktop" "$ROOT/kr-apps-$TAG.txt" \
    && echo "CKPT-APPS-NODISPLAY=FAIL" || echo "CKPT-APPS-NODISPLAY=OK"

$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "apps games" \
    > "$ROOT/kr-appsgames-$TAG.txt" 2>&1
grep -q "app:hxmine.desktop" "$ROOT/kr-appsgames-$TAG.txt" \
    && echo "CKPT-APPS-CATVIEW=OK" || echo "CKPT-APPS-CATVIEW=FAIL"

$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "apps harness" \
    > "$ROOT/kr-appsfz-$TAG.txt" 2>&1
grep -q "app:hxfire.desktop" "$ROOT/kr-appsfz-$TAG.txt" \
    && echo "CKPT-APPS-FUZZY=OK" || echo "CKPT-APPS-FUZZY=FAIL"

$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "apps pins" \
    > "$ROOT/kr-appspins-$TAG.txt" 2>&1
# v0.7: with a kickoff favorite present, pins view shows the kickoff block
# (empty-state row only when favorites AND pins are both empty — unit-tested)
# note: busctl escapes UTF-8 — '·' appears as \302\267 in Match output
grep -q 'kickoff \\302\\267 games' "$ROOT/kr-appspins-$TAG.txt" \
    && echo "CKPT-APPS-PINS-KICKOFF=OK" || echo "CKPT-APPS-PINS-KICKOFF=FAIL"

# v0.7: kickoff favorite leads the root view, launch-only (kickoff · group)
grep -q 'kickoff \\302\\267 games' "$ROOT/kr-apps-$TAG.txt" \
    && echo "CKPT-APPS-KICKOFF=OK" || echo "CKPT-APPS-KICKOFF=FAIL"
# noise row (other favorites agent) must NOT leak in as a favorite
grep -q 'kickoff \\302\\267 internet' "$ROOT/kr-apps-$TAG.txt" \
    && echo "CKPT-APPS-KICKOFF-FILTER=FAIL" || echo "CKPT-APPS-KICKOFF-FILTER=OK"

$B call org.kde.krunner /App org.kde.krunner.App query s "apps" >/dev/null 2>&1
sleep 1
spectacle -b -n -o "$OUT/kr-apps-$TAG.png" 2>/dev/null && echo "SHOT-kr-apps"
# empty-query state: does plasma render runner actions? (§L-7 verdict input)
$B call org.kde.krunner /App org.kde.krunner.App query s "" >/dev/null 2>&1
sleep 1.5
spectacle -b -n -o "$OUT/kr-empty-$TAG.png" 2>/dev/null && echo "SHOT-kr-empty"
# hermes-menu bind gate (keys v3): the EXACT Exec line from hermes-menu.desktop,
# replayed against this session's krunner — Super+Space must open ON the menu
$B call org.kde.krunner /App org.kde.krunner.App query s "apps" >/dev/null 2>&1 \
  && echo "CKPT-MENU-OPENER-CALL=OK" || echo "CKPT-MENU-OPENER-CALL=FAIL"
sleep 2
spectacle -b -n -o "$OUT/kr-menu-$TAG.png" 2>/dev/null && echo "SHOT-kr-menu"
[ -s "$OUT/kr-menu-$TAG.png" ] && echo "CKPT-MENU-OPENER=OK" || echo "CKPT-MENU-OPENER=FAIL"

# drill: Run on a category row re-drives the query via /App (async thread)
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "appcat:games" "" >/dev/null 2>&1
sleep 1.5
grep -q "HARNESS-APPCAT apps games" "$ROOT/runner-$TAG.log" \
    && echo "CKPT-APPCAT-RUN=OK" || echo "CKPT-APPCAT-RUN=FAIL"
spectacle -b -n -o "$OUT/kr-appcat-$TAG.png" 2>/dev/null && echo "SHOT-kr-appcat"

# launch: exactly one stub exec with the fixture's absolute path
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "app:hxmine.desktop" "" >/dev/null 2>&1
sleep 1
N=$(grep -c "STUB-KIOCLIENT exec" "$H/stub-kioclient.log" 2>/dev/null || echo 0)
[ "$N" = "1" ] && grep -q "$H/.local/share/applications/hxmine.desktop" "$H/stub-kioclient.log" \
    && echo "CKPT-APP-LAUNCH=OK" || echo "CKPT-APP-LAUNCH=FAIL(n=$N)"

# pin roundtrip: config write + pinned row first on the next root Match
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "app:hxmine.desktop" "pin" >/dev/null 2>&1
sleep 1
/usr/bin/python3 -c "import json,sys;sys.exit(0 if json.load(open('$H/.config/hermes-runner/config.json')).get('app_pins')==['hxmine.desktop'] else 1)" \
    && echo "CKPT-APP-PIN-CONF=OK" || echo "CKPT-APP-PIN-CONF=FAIL"
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Match s "apps" \
    > "$ROOT/kr-apps2-$TAG.txt" 2>&1
head -30 "$ROOT/kr-apps2-$TAG.txt" | grep -q "app:hxmine.desktop" \
    && echo "CKPT-APP-PIN-ROW=OK" || echo "CKPT-APP-PIN-ROW=FAIL"

# empty-state action buttons exist on the wire
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Actions \
    > "$ROOT/kr-actions-$TAG.txt" 2>&1
for a in launch pin unpin apps fav; do
    grep -q "\"$a\"" "$ROOT/kr-actions-$TAG.txt" || { echo "CKPT-ACTIONS=FAIL($a)"; break; }
    echo "CKPT-ACTIONS=OK"
done
$B call org.kde.runners.hermes /hermes org.kde.krunner1 Run ss "" "apps" >/dev/null 2>&1
sleep 1
grep -q "HARNESS-APPACTION apps" "$ROOT/runner-$TAG.log" \
    && echo "CKPT-APPACTION-RUN=OK" || echo "CKPT-APPACTION-RUN=FAIL"

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
