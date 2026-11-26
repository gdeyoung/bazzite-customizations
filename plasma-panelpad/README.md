# Plasma PanelPad

> **KDE Plasma 6 version** — KDE-native, no Omarchy counterpart. A tiny layout helper
> used by the other widgets in this repo.

An **invisible fixed-width panel spacer**: width from config (`padWidth`, default
48 px), no visuals, no click action. It exists purely to put exact, scriptable space
between panel widgets — Plasma's expanding spacers absorb interior gaps, a pad
widget does not (see `plasma-plasmoid-development`, *Panel placement & popup UX*).

## Why it is a widget
Plasma 6.7 panel containers do not size a `compactRepresentation` from
`implicitWidth` alone — a bare `Item` collapses to a ~34 px default cell and ignores
config. PanelPad sets `width` + `implicitWidth` + `Layout.preferredWidth` +
`Layout.minimumWidth` together from one property and roots the compact representation
in a `MouseArea` so the container treats it as a normal chip.

## Install
```
kpackagetool6 -t Plasma/Applet -i .        # first install; -u . to upgrade (run from THIS dir)
```
Then add **PanelPad** to the panel (Add Widgets, or the scripting API) and set its
width in the widget's configure dialog. No shell restart is needed or performed.
