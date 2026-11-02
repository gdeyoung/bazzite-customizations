# plasma-tailfin — Control Spec (v0.2 candidate)

Extends the read-only port with the three control operations, gated and
testable. Review scope: §T-1..§T-9. Conventions follow krunner-hermes
UX-SPEC.md: every interactive element has defined states, and every state a
source of truth. Design language: Kirigami primitives only, compact popup,
no modals launched from the applet popup (Plasmoid popup + Dialog window is
a known-janky combo; two-step inline is the widget-native confirm).

HARD invariants (not up for redesign):
- Automation never executes control ops against the real `tailscale` binary.
  All tests/harness runs use a stub. First real op is the user at the desk.
- Ops are a closed allowlist; argv is built only from typed enums (§T-2).
- Disconnect confirmation is mandatory and not configurable (§T-3).

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

- Header gains a trailing text button in the title row (right-aligned,
  next to selfName):
  - Running: `Disconnect` — neutral/disabled color at rest.
  - Stopped: `Connect` — normal text color.
- **Connect: single click.** Up is additive/safe.
- **Disconnect: two-step inline confirm.**
  1. Click 1 arms: button text becomes `Confirm disconnect`
     (negativeTextColor), and a one-line warning appears beneath the
     title (negative color, small font):
     `tailnet goes down here — remote access via ts.net drops until reconnect`
  2. Click 2 within 4 s fires `down`. Auto-disarm after 4 s, on popup
     close, on op-complete, or on any other control click.
  - No modal. No config to skip the confirm.
- In-flight (either op): button disabled, label `working…`.
- Result feedback = the next status poll (§T-5). No toast.

## T-4 — Exit-node set / clear

- **Candidates:** Online peers whose raw AllowedIPs contain `0.0.0.0/0`
  (same data the routes line already shows).
- **Set:** candidate rows get a trailing `use` ToolButton in the name row
  (small, neutralTextColor; positiveTextColor on hover). Single click, no
  confirm — trivially reversible. Active exit node's row keeps its existing
  `exit` tag and hides its own `use` button (re-select is a no-op).
- **Target resolution:** DNSName with trailing dot stripped; fallback first
  TailscaleIP. (Stable across renames better than HostName.)
- **Clear:** the active exit-node banner (`▸ exit node: X`) gains a
  trailing `×` ToolButton (tooltip `stop using exit node`). Single click.
  Works for Mullvad exits too (banner already names them).
- In-flight: all `use`/`×` buttons disabled; target row shows `switching…`
  as a transient sub-line (cleared on op-complete).
- Mullvad region *picking* stays out of scope (Trayscale/CLI territory).

## T-5 — Busy, refresh, failure

- One op at a time; presses during flight are ignored (no queue).
- Op completes → force an immediate status re-poll (bypass the interval
  Timer) so feedback is the refreshed list/banner/chip, not a toast.
- Failure: one error row under the header (negative color, small font):
  `op failed: <first line of stderr>`; dismissed by the next successful
  op or popup reopen. No auto-retry. Controls re-enabled immediately.

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
  - confirm machine: arm → fire, arm → timeout(4 s) → disarm,
    arm → popup close → disarm, connect needs no arm
  - exclusivity: second op while in-flight is refused at the API level
  - error formatting: stderr first line, empty-stderr fallback
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
gdtower                              [Disconnect]   ← title row button
100.x.y.z · gdtower.…dns
tailnet goes down here — …            ← only while armed (negative)
▸ exit node: tower                   [×]            ← clear action
● tower            exit              [use hidden — it's active]
  100.x.y.z · tower.dns
  routes: 0.0.0.0/0, ::/0
● nasbox                             [use]
  100.x.y.z · nasbox.dns
```
