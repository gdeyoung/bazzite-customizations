# Foyer for KDE

> **KDE Plasma 6 version** — the native Plasma counterpart of
> [`gdeyoung/omarchy-foyer`](https://github.com/gdeyoung/omarchy-foyer) (Quickshell / Hyprland). The Omarchy
> original lives in its own repo; this directory is the KDE one.

A keyboard-first, **fan-out launcher overlay for KDE Plasma 6** (Meta+Space) that
unifies Foyer's browsable menu tree with the Hermes fleet lanes in one instantly-open
native window — the thing KRunner's rows-only protocol could never be. Built as a
user-space PySide6 daemon on LayerShellQt: no rpm-ostree layering, no sudo, nothing
compiled.

| Document | What it is |
|---|---|
| [PRODUCT.md](PRODUCT.md) | One-sentence product, owner/scene, mode, success budget |
| [CONVERGED-DESIGN.md](CONVERGED-DESIGN.md) | **Design of record** — converged tree, nav model, data lanes |
| [DESIGN-BRIEF.md](DESIGN-BRIEF.md) | Original brief |
| [docs/](docs/) | Research teardowns of the Omarchy original |
| [harness/](harness/) | Nested-session harness (`run-hotkey-harness.sh`) + `install.sh` |
| [src/](src/) | `daemon/` (PySide6 + D-Bus `gdeyoung.foyer`) and `qml/` |

## Install (user space)
```
harness/install.sh --install            # stage to ~/.local/share/foyer, dbus activation, foyer.service
harness/install.sh --take-hotkey        # also bind Meta+Space (names the combo it releases)
harness/install.sh --uninstall
```
Summon with `systemctl --user start foyer.service` or just call the bus
(`busctl --user call gdeyoung.foyer / gdeyoung.foyer toggle`). Functional QA happens
in the nested harness, never on the live desktop.

## State
Installed and running on the tower. The data lanes are a static snapshot; live wiring
(.desktop splice, ICMP fleet probe, AI lane) is the open work — see the roadmap in the
repo root.
