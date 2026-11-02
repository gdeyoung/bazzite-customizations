# plasma-tailfin — Control Spec (v0.2 candidate, r2)

Extends the read-only port with the three control operations, gated and
testable. Review scope: §T-1..§T-9. Conventions follow krunner-hermes
UX-SPEC.md: every interactive element has defined states, and every state a
source of truth. Design language: Kirigami primitives only, compact popup,
no modals launched from the applet popup (Plasmoid popup + Dialog window is
a known-janky combo; two-step inline is the widget-native confirm).

r2 folds the UX verdict (deleg_96598ff9, APPROVE-WITH-CHANGES ×8):
arm dead-zone, explicit disarm ordering, op watchdog, honest button
styling, minimum hit targets, `use` tooltip, message-row stacking, and
switching/failure cleanup incl. the login-required case.

HARD invariants (not up for redesign):
- Automation never executes control ops against the real `tailscale` binary.
  All tests/harness runs use a stub. First real op is the user at the desk.
- Ops are a closed allowlist; argv is built only from typed enums (§T-2).
- Disconnect confirmation is mandatory and not configurable (§T-3).
- disabledTextColor is used ONLY for disabled=true. An enabled control is
  never styled to look disabled.

## T-1 — Operator gate

- On popup open (not per poll), run read-only `tailscale debug prefs`;
  parse `OperatorUser`. Probe once per plasmoid load; cache last-known.
- Controls render iff `OperatorUser === current user` (this box:
  gdeyoung — enabled).
- When disabled: no buttons anywhere; one hint row under the header:
  `control disabled — run: sudo tailscale set --operator=$USER`
  (disabled color, single line). Rows/list unchanged.
- Probe failure (tailscaled down): keep last-known verdict. First-ever
  load with daemon down = controls hidden, hint row says
  `control unavailable — tailscaled not responding` (retry next popup open).
- Hint row position: third in the header message stack (§T-5 order).

## T-2 — Closed op allowlist

Control.js exports `opArgv(op)`; the ONLY constructible invocations:

| op (typed) | argv | note |
|---|---|---|
| `up` | `tailscale up` | no flags — reuses saved prefs |
| `down` | `tailscale down` | confirmed path only (§T-3) |
| `exit-set` | `tailscale set --exit-node=<target>` | target resolved §T-4 |
| `exit-clear` | `tailscale set --exit-node=` | empty value = clear |
| (probe) | `tailscale debug prefs` | read-only, §T-1 |

Binary path overridable via `TS_BIN` (default `tailscale`) for the harness.
Tests assert: the exported map is total, exact, and contains no other
strings — no op ever yields `up/down/set` outside these five rows.

## T-3 — Connect / disconnect (header toggle)

- Header gains a trailing flat ToolButton in the title row (right-aligned,
  next to selfName):
  - Running: `Disconnect` — normal textColor at rest, hover background;
    negativeTextColor only while armed.
  - Stopped: `Connect` — normal textColor, hover background.
  - In-flight: disabled, label `working…` (disabledTextColor — honest).
- **Connect: single click.** Up is additive/safe.
- **Disconnect: two-step inline confirm with an arm dead-zone.**
  1. Click 1 arms: text becomes `Confirm disconnect`
     (negativeTextColor), and a one-line warning appears beneath the
     title (negative color, small font):
     `tailnet goes down here — remote access via ts.net drops until reconnect`
  2. **Dead-zone:** a click on the button within 500 ms of arming is
     IGNORED (state stays armed, the 4 s window keeps running). This
     closes the double-click path — the canonical stray in a panel popup.
  3. Click 2 after the dead zone, within the 4 s window, fires `down`.
  - Auto-disarm at: 4 s elapsed, popup close, op launch (armed=false at
    launch, so the warning line and `working…` never coexist), or any
    other control click.
  - **Other-control-click ordering:** clicking any other enabled control
    while armed DISARMS and PERFORMS that control's action (arm
    Disconnect → click `use` → exits armed state, exit-set fires,
    `down` never does).
  - No modal. No config to skip the confirm.

## T-4 — Exit-node set / clear

- **Candidates:** Online peers whose raw AllowedIPs contain `0.0.0.0/0`
  (same data the routes line already shows).
- **Set:** candidate rows get a trailing `use` ToolButton in the name row
  (flat, neutralTextColor, hover background; single click, no confirm —
  trivially reversible). Tooltip: `use <peer name> as exit node` (resolved
  DisplayName, so it teaches even when the row name is elided).
  Active exit node's row keeps its existing `exit` tag and hides its own
  `use` button (re-select is a no-op).
- **Hit targets:** `use` and `×` ToolButtons are at least
  `Units.gridUnit * 1.4` (~22–24 px) tall with horizontal padding, and
  separated from row/banner text by at least smallSpacing — a click aimed
  at the node name or banner text cannot land on a control.
- **Target resolution:** DNSName with trailing dot stripped; fallback first
  TailscaleIP. (Stable across renames better than HostName.)
- **Clear:** the active exit-node banner (`▸ exit node: X`) gains a
  trailing `×` ToolButton (tooltip `stop using exit node`). Single click.
  Works for Mullvad exits too (banner already names them).
- In-flight: all `use`/`×` buttons disabled; target row shows `switching…`
  as a transient sub-line, cleared on completion OR failure OR timeout.
- Mullvad region *picking* stays out of scope (Trayscale/CLI territory).

## T-5 — Busy, refresh, failure, message stack

- One op at a time; presses during flight are ignored (no queue).
- **Op watchdog:** each op has a timeout — 15 s for `down`/`exit-set`/
  `exit-clear`, 30 s for `up` (can block on auth/network). On timeout:
  kill the source, error row `op timed out`, re-enable controls. The
  executable engine only reports on process exit; without this the widget
  would sit in `working…` forever.
- Op completes → force an immediate status re-poll (bypass the interval
  Timer) so feedback is the refreshed list/banner/chip, not a toast.
- **Failure row:** one line, negative color, small font:
  - `up` failing with an auth/login URL in output →
    `login required — run: tailscale login` (actionable over raw stderr)
  - otherwise `op failed: <first line of stderr>` (fallback
    `op failed: exit <n>` when stderr is empty)
  - dismissed by the next successful op or popup reopen. No auto-retry.
  Controls re-enable immediately after any op end (exit or timeout).
- **Header message stack order** (coexistence defined, top→bottom):
  1. armed warning (§T-3)
  2. op error (this section)
  3. operator-gate hint (§T-1)
  4. health warnings (existing)
  All single-line elided except health (wrap, as today).

## T-6 — Chip unchanged

The compact chip reflects polled status only — no busy/armed state leaks
into the panel bar. (We do not display state we don't know.)

## T-7 — Execution + stub architecture

- Ops run through the same `plasma5support` `executable` engine as the
  status poll (source = argv string; connect on demand, disconnect on
  data), launched with `TS_BIN` if set in plasmashell's environment.
- Node tests (`tests/control.test.js`), no real binary anywhere in PATH:
  - allowlist totality/exactness (§T-2 table, byte-for-byte argv)
  - probe parser: operator match / mismatch / absent / daemon-down
  - target resolution: dot-strip, IP fallback, non-candidate rejection
  - confirm machine: arm → dead-zone re-click → still armed (no `down`
    in log) → post-zone click fires; arm → 4 s timeout → disarm;
    arm → popup close → disarm; arm → other-control click → that op
    fires, `down` never; connect needs no arm
  - watchdog: op with tiny timeout never resolving → timeout surfaces,
    controls re-enable, `switching…` cleared
  - exclusivity: second op while in-flight is refused at the API level
  - error formatting: auth-URL case, stderr first-line case,
    empty-stderr fallback
- Harness: stub `tailscale` shell script first in PATH + `TS_BIN` export;
  logs each argv line to a file; serves canned `status --json` (connected,
  one exit-node candidate, one offline peer) and `debug prefs`
  (OperatorUser gdeyoung). Driver asserts pixels (arm/confirm states, use
  buttons, banner ×) AND the stub log after synthetic clicks.

## T-8 — Scope guard

Still NOT ported: Mullvad region picker, Taildrop, tailscale SSH launcher,
account switching, advertise-routes toggles, preference editing.
README "Differences" section updates to move up/down + exit-node set/clear
into the ported column.

## T-9 — Popup wireframe (delta only)

```
gdtower                              [Disconnect]   ← title-row flat ToolButton
100.x.y.z · gdtower.…dns
tailnet goes down here — …            ← msg 1: armed only (negative)
op failed: …                          ← msg 2: last op failure (negative)
control disabled — run: sudo …        ← msg 3: operator gate (disabled color)
▸ exit node: tower                   [×]            ← clear action
● tower            exit              [use hidden — it's active]
  100.x.y.z · tower.dns
  routes: 0.0.0.0/0, ::/0
● nasbox                             [use]
  100.x.y.z · nasbox.dns             (≥gridUnit·1.4 tall, smallSpacing gap)
```
