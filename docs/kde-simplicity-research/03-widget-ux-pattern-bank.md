# 03 — Desktop Shell Widget UX Pattern Bank
**Scope:** panel chips (compact reps), tray-class popup widgets (~34×38 grid units), system dashboards. Grounded in KDE HIG + KDE's own shipped plasmoid source + platform HIGs (Apple / GNOME / Windows / Material 3), mapped to our field-tested verdicts V1–V10.
**Purpose:** skill-reference bank — start new widgets from these patterns; every claim carries `[Snn]` source tag + tier.
**Date:** 2026-11-04. **Tier legend:** S = official spec/HIG/source code · A = vendor blogs, official docs secondary pages, W3C · B = independent research (NN/g), tech press · C = community (forums, Reddit, KDE Discourse) · D = blogs.
**Correction of premise up front:** `hig.kde.org` is no longer a separate site — it redirects to `develop.kde.org/hig/`, which was **rewritten (2025) as a topic-based HIG** (10 topic pages). There is **no plasmoid-specific HIG page**: the only Plasma-shell-specific guidance is the *System Tray icons* and *OSD* sections of "Communicating status changes" plus a "Plasma Widget" reference. Old component pages (typography, color, units, listviews) are now **aliases** that redirect into the new topic pages — e.g. `/hig/style/color/` → `status_changes`, `/hig/layout/units/` → `layout_and_nav`, `/hig/patterns-navigation/list/` → `displaying_content` (verified in the page front-matter aliases, invent.kde.org `documentation/develop-kde-org` repo [S]). The practical consequence: for widget UX, the HIG gives *principles + control-selection rules*, and **KDE's own shipped plasmoid source is the de-facto component-level pattern authority** (Section 2).

---

## 1. KDE HIG — what actually governs Plasma widgets

HIG corpus fetched raw from invent.kde.org/documentation/develop-kde-org `content/hig/` [S; also live at develop.kde.org/hig/]. Key rules for tray-class widgets, by topic page:

### 1.1 Views: list vs grid vs tabs vs tree (displaying_content)
- **Lists > grids for mostly-textual content** — "faster to visually scan and handle long text better"; grids win only when "scrolling is undesirable" or content is mostly-visual [S: develop.kde.org/hig/displaying_content/].
- **Tabs are for "related views sharing the same level of hierarchy"; immutable tabs (Kirigami.NavigationTabBar) are for "grouping settings or Contextual Toolview pages." Hard scaling limit: "On the desktop, tab views scale poorly beyond 4 or 5 tabs." Hide the tab bar entirely when only one tab would exist [S: same page].
- **Tree views: minimize.** "Consider a list view with collapsible sections" instead; a tree is acceptable "in an app meant for technical users where the content… already has an inherent tree-like structure (e.g. a tree of system processes)" — explicit blessing for a process tree in a sysmon-class widget [S: same page].
- **Remove controls belong inline on the rows themselves, "visible, rather than appearing on hover"** [S: same page] — refines our V6 hover-x (see §5).
- Add-content controls belong as actions on the view header (Kirigami.InlineViewHeader), not inline in content [S: same page].
- Selected/actively-used row = **bold text**; rows with trailing data may use alternating background colors to bind left↔right content [S: same page].
- Popups need a **contrasting outline** so they don't blend into dark backgrounds [S: same page].

### 1.2 Layout, spacing, units (layout_and_nav)
- **`gridUnit` = 18px**; "Fixed-size UI elements, including default and minimum window sizes: gridUnit multiplied as needed" [S: develop.kde.org/hig/layout_and_nav/]. Spacing scale: `smallSpacing` between related items, `mediumSpacing` in toolbars, `largeSpacing` between groups and at page edges; 0 between title and subtitle.
- **Reading order = importance order:** users attend first to the top-leading corner and treat bottom-trailing as the final action spot [S: same page] — for a popup: identity/status top-left, destructive/commit bottom.
- Hamburger menus only if ≤ ~15 items; global actions static, disabled-not-hidden when irrelevant [S: same page].
- Navigation: ≤5 destinations → tab-style NavigationTabBar; more → sidebar/GlobalDrawer; launch view must be the first item [S: same page].

### 1.3 Actions, dialogs, input (getting_input)
- **Dialogs are a last resort:** "Minimize their use, as they can be considered annoying; many users click through them without reading anything." Only two justifications: an immediate blocking decision, or task progress. Everything else = inline, non-modal [S: develop.kde.org/hig/getting_input/].
- **Instant-apply is a control-level contract:** Switch = "instant apply" (takes effect on click); CheckBox = takes effect on OK/Apply [S: same page].
- Search = Kirigami.SearchField (standard placeholder "Search"); text fields get trailing inline actions (e.g. clear) via ActionTextField [S: same page].
- Slider for bounded "fast > precise" input (volume/brightness), SpinBox when precision dominates; combine when both matter [S: same page].
- **Interactivity is signaled by hover effects** (background/outline color change in Breeze); custom controls must re-implement hover signaling; pointing-finger cursor only for web-style links [S: same page].

### 1.4 Status, color, notifications, tray (status_changes)
- **Semantic color roles:** highlight/blue = selection + "benign and ignorable"; **orange (NeutralText/Background) = warning or "non-default settings states"**; **red (NegativeText/Background) = errors, dangerous actions**. "Don't rely on color alone… also use different icons, shapes, or text" [S: develop.kde.org/hig/status_changes/].
- **System Tray icons are a last resort** — "annoying to users"; prefer task badges, notifications, progress, or "consider writing a Plasma Widget instead of a standalone app"; if you must, make the icon opt-in and show it "only when there is abnormal status" [S: same page]. (Relevant to chip-visibility policy: dormant chips may hide.)
- OSDs are for user-initiated system-level state changes (volume, brightness, connect, timezone) — windowed apps must not show OSDs [S: same page].
- Error ladder: best = make the error impossible / auto-recover; worst = silent failure; all error text must be actionable [S: same page].
- In-app: passive notification (auto-dismisses) for ignorable/undo-able; InlineMessage (persistent) for "truly destructive actions such as deleting files" [S: same page, and simple_by_default §1.6].

### 1.5 Empty states, tooltips, help (displaying_content, text_and_labels)
- **Empty views get a Kirigami.PlaceholderMessage: icon + explanation text + ideally a `helpfulAction` button** ("to tell users how to get content into it") [S: develop.kde.org/hig/text_and_labels/#placeholders; simple_by_default].
- Placeholder text style: imperative verb, no trailing ellipsis ("Search", "Enter file name") [S: text_and_labels].
- **Never put important text in a hover-only tooltip** (touchscreen users can't reach it; mouse users don't habitually hover) [S: displaying_content "Inline help and tooltips"].
- Long help → collapsed "Details"/"Show More" section [S: same page] — the same expandable pattern our OFFLINE section uses.

### 1.6 Safety: destructive actions & undo (simple_by_default)
- "The easier something is to remove from the app, the easier it should be to get it back. **Use menus or sub-pages to hide features that destroy data… so they can't be triggered by a stray click, or else use a confirmation dialog.**" Move to trash, don't delete. **"Offer an undo for every action that removes content not trivial to re-add."** Undo UI must be dismissable and non-modal [S: develop.kde.org/hig/simple_by_default/].
- Defaults: window must show all labels with no elision; don't keep running as a tray icon when closed [S: same page].

### 1.7 Accessibility QA protocol (accessibility)
Unplug-the-mouse keyboard-only pass (default focus must make sense, active focus visibly distinct); single-input-device pass; **swap the global color scheme** and check adaptation (kills hardcoded status colors); **raise system font to 14pt** and check nothing clips; tooltips must also appear on press-and-hold; screen-reader names every element [S: develop.kde.org/hig/accessibility/].

### 1.8 Power features (powerful_when_needed)
Settings should "switch between multiple supported and valid behaviors," not merely on/off toggles; on/off-only settings are "warning signs of sloppy design"; don't offload design decisions into settings [S: develop.kde.org/hig/powerful_when_needed/].

### 1.9 What the HIG does *not* cover for plasmoids
No guidance on: panel chip (compactRepresentation) content design, popup sizing/placement, chip typography or the unified type scale (our V4 has no HIG counterpart — only "increase system font to 14 and verify" as the adaptive test), section headers with counts, search placement inside popups, staleness/provenance stamps (V8), hit-target minimums (V5), or scroll-vs-fit rules for popups (V3). These come from shipped-plasmoid practice (§2) and other platforms (§3).

---

## 2. What KDE's own shipped plasmoids actually do (source-verified, S-tier)

All paths are `master` on invent.kde.org; line numbers from fetched source 2026-11-04. These five applets are the de-facto Plasma popup pattern library.

### 2.1 Digital clock + calendar (plasma/plasma-workspace `applets/digital-clock/`)
- **Chip = full-cell hit target with content-measured width.** `DigitalClock.qml` is a `MouseArea` with `Layout.fillHeight: true`; `Layout.minimumWidth: contentItem.width` where `contentItem.width` = max of the rendered label widths + `largeSpacing` (L147–155). The whole cell toggles the popup — no dead zones beside the glyphs (our V5 is upstream behavior).
- **Chip typography is a 2-step ratio scale, not fixed px:** time label height = 0.71 × panel height (0.56 when a second row is shown); timezone/date labels = 0.7–0.8 × time label; `tnum` (tabular figure) font feature enabled so digits don't jitter (L161–182, L429).
- **Chip fallback state:** if the timezone is invalid the compact rep swaps to `NoTimezoneWarning` rather than showing garbage (`main.qml` L139, L153–156). Chip has its own richer `toolTipItem` (Tooltip.qml) wired to `Accessible.name` (L148–149, L158–167).
- **Popup IA: two-pane, zero tabs.** `CalendarView.qml`: leading column = "Events" section (Kirigami Heading level 2) with an inline `Add…` ToolButton in the section-header row (L127–154), a scrolling events ListView, a labeled empty state, a hairline separator (L389–398), then "Time Zones" section (Heading level 2) with a `Switch…` ToolButton (L419–439) and a world-clocks ListView; trailing half = month grid (L618). Sections = Heading 2 + section-scoped action button; the month grid header height is synced to the agenda header height (L57).
- **Empty state:** `PlasmaExtras.PlaceholderMessage`, icon `checkmark`, "No events for today / No events for this day" (L376–386).
- **Open/close hygiene:** on expand, focus is forced to the month view's configure button and the view resets to today (`main.qml` L119–125); popup closes on focus loss unless pinned (`hideOnWindowDeactivate: !Plasmoid.configuration.pin`, L180); persistent "Keep Open" pin is a standard affordance.

### 2.2 System tray (plasma/plasma-workspace `applets/systemtray/qml/`)
- **The canonical popup header** (`ExpandedRepresentation.qml`): `PlasmoidHeading` containing back button (when drilled in) → Heading level 1 title that reflects the current applet and elides → high-priority `contextualActions` rendered as icon-only ToolButtons **with ToolTips** → "More actions" `application-menu` overflow (NormalPriority actions become a menu) → `configure` icon → pin ("Keep Open"). Every button is wired into a `KeyNavigation` web.
- **Master–detail inside one popup:** the tray popup is a grid of hidden/active items (master) that swaps to an embedded applet's full representation (detail) with a back button — popups may drill down one level, they don't paginate.
- **Footer is a first-class slot:** optional bottom `PlasmoidHeading` (`position: Footer`) shows applet-provided footer controls (e.g. media controls).
- **Grid of items** (`HiddenItemsView.qml`): 2-column GridView in a ScrollView; delegate = icon + up to 2 lines of label; `PlasmaExtras.Highlight` for focus/hover; accessible description announces "Grid with %1 items in %2 columns"; keyboard navigation lands on first item on focus.
- Popup minimum: **24×24 gridUnits** (L21–22).

### 2.3 Notifications (plasma/plasma-workspace `applets/notifications/`)
- Popup = PlasmoidHeading header (applet name, DND checkbox, clear/announce actions) + history ListView of swipe-dismissable grouped delegates; full rep min ~ preferred/maximum Layout set.
- **Empty states are distinct per cause** (`FullRepresentation.qml` L642–669): "No unread notifications" (checkmark icon) vs "Notification service not available" (notifications-disabled icon + vendor explanation). Labeled, never blank.
- **State reset on open:** on expand the list scrolls to beginning and every item is marked read (L53–61) — open = reconcile with reality (our V8's fresh-on-open instinct).

### 2.4 Network (plasma/plasma-nm `applet/`) — the closest analogue to tailfin
- **Chip:** symbolic status icon that reflects connection state; `Plasmoid.busy` while connecting (spinner overlay on chip); tooltip = "Networks" + active connections summary + middle-click hint (`main.qml` L39–56); **middle-click (secondary activation) toggles airplane mode** (L70–74); Wi-Fi/mobile/airplane toggles live in the context menu (L76–119). Popup min = iconSizes.medium × 10 wide, 20 gu tall (L64–65).
- **Freshness is budgeted, not streamed:** a 10.2 s rescan timer runs **only while expanded** (`main.qml` L154–161); the connection model is created on open and destroyed on close (`PopupDialog.qml` L117–132).
- **Header = Toolbar** (`PopupDialog.qml` L42–66): leading icon-only radio switches (Wi-Fi / mobile data / airplane — each with tooltip, plus BusyIndicator prolonged to `humanMoment` so fast scans are still visible), Hotspot toggle, then `PlasmaExtras.SearchField` that fills remaining width, then QR-scan and configure icon buttons (`Toolbar.qml`). **Search sits in the popup header, not the body; it auto-focuses on open and filters live** (`Toolbar.qml` SearchField; `PopupDialog.qml` Ctrl+F jumps to it, L92–105).
- **List = one flat ListView with section headers, not tabs** (`ConnectionListPage.qml` L52–91): `section.property: "Section"` + `PlasmaExtras.ListSectionHeader`; horizontal scrollbar explicitly `AlwaysOff`; portal captive-portal warning is a header `Kirigami.InlineMessage` with a "Log in" action (L26–42); ↑ from list top returns focus to search (L61–69).
- **Empty-state matrix** (L93–158): airplane on / Wi-Fi off / "Looking for Wi-Fi networks" / "No matches" (search) / "No available connections" — each with its own icon, text, and an explanation line that tells the user how to fix it.
- **Row anatomy** (`ConnectionItem.qml`, root = `PlasmaExtras.ExpandableListItem`): icon + title + live subtitle (activating → device state, deactivated → "Last used", connected → "↓ x/s, ↑ y/s"); busy spinner on the row; a **default action button that flips label/icon by state ("Connect"/"Disconnect")**; overflow actions (Share, Configure…) behind the item's expander; **inline expand for password entry — no modal dialog**; expanded details contain a 2-tab Speed/Details TabBar with a live traffic chart (L30–148, L219–238). **Disconnect fires on a single click with no confirmation** (L63–66, L287).
- Drill-down: StackView pushes secondary pages (Wi-Fi QR share) with header back button; Alt+Left/Back pops (`PopupDialog.qml` L56–64, L91–105).

### 2.5 System Monitor widget (plasma/plasma-workspace `applets/systemmonitor/systemmonitor/package/contents/ui/`)
- **Chip = a live chart, not numbers:** CompactRepresentation embeds a SensorFace compact chart (sparkline scaled to the panel) with a full-cell MouseArea toggle; the FullRepresentation is the *same* sensor face rendered large (`CompactRepresentation.qml`, `FullRepresentation.qml`). One metric family per widget; more widgets, not more cards in one popup.

### 2.6 Battery & Brightness (plasma/powerdevil `applets/batterymonitor/`, `applets/brightness/`)
- Chip: battery icon + "%1%" percentage beneath it, plus state string in tooltip ("Battery level unknown", "%1 until fully charged", "%1 remaining" — `main.qml`). Popup (`PopupDialog.qml`) = ScrollView with Repeater-built rows: per-battery items, brightness slider row, power-profile selector rows, inhibition items. Flat list of control rows; no tabs.

### 2.7 Cross-cutting upstream defaults (observed in all of the above)
1. Header pattern: title (Heading 1) + contextual icon buttons w/ tooltips + configure + pin. Footer pattern for row-scoped actions (tray, notifications).
2. Sections = Kirigami/PlasmaExtras Heading level 2, optionally with an inline section action; counts are NOT shown upstream (our V1/V6 count labels are an enhancement, not an upstream norm).
3. Empty/loading = PlaceholderMessage with cause-specific icon + text + explanation; there is always one per distinct cause.
4. Search lives in the header (SearchField), auto-focused, live-filtering, with Ctrl+F accelerator.
5. Full-cell click targets on chips; content-measured widths; symbolic icons in panel; `tnum` digits for changing numbers.
6. Destructive/state actions: single click, state-flipping label, no confirmation dialogs anywhere in the shipped set; undo/inline patterns instead.
7. Keyboard: every shipped popup implements KeyNavigation + focus-on-open; Esc/back-stack for drill-downs.
8. Popups are lazy: models load on open, die on close; timers only run while visible.

---

## 3. Platform guidance for tray-class surfaces (what the other HIGs agree on)

### 3.1 Apple (developer.apple.com/design/human-interface-guidelines)
- **Premise correction:** the old "Menu bar extras" HIG page is **gone** (404); the topic now lives inside "The menu bar" (`/the-menu-bar`) + the SwiftUI `MenuBarExtra` API docs. [S]
- **Popovers are for "a small amount of information or functionality… limit the amount of functionality to a few related tasks."** Dismiss on outside-click/item-selection; Close button only when it clarifies save-vs-cancel; **always save work when auto-closing** (never discard implicit work); **one popover at a time; never cascade popovers; nothing on top of a popover except an alert**; "avoid making a popover too big — only big enough to display its contents"; multiple-selection popovers stay open. [S: HIG Popovers, fetched 2026-11-04]
- Menu bar: app menu bold; **disable rather than hide unavailable items**; familiar icons for common actions; one-word titles where possible; extras sit on the trailing side. [S: HIG The menu bar]
- Menus: verb/verb-phrase labels; title-style capitalization; toggled menu items communicate current state and flip it. [S: HIG Menus]

### 3.2 GNOME (developer.gnome.org/hig, sources fetched from gitlab.gnome.org Teams/Websites/developer.gnome.org-hig)
- **Premise correction:** the current GNOME HIG has **no status-icon / tray guidance at all** — GNOME removed app indicators from the platform; tray-class behavior is specified only in GNOME *Shell* design (see below). Closest HIG analogues: Popovers pattern (guidance is in mockups, thin text), Dialogs, Placeholders, Search, View Switchers. [S]
- **Placeholders (empty views):** "fill a view with an image, a heading, and an optional line of descriptive text… used to fill a space that is empty but which would usually be populated" — two styles: illustration or symbolic icon. [S: patterns/feedback/placeholders]
- **Typography:** "Make an effort to minimize the number of font sizes and weights"; smaller/lighter for less important info, heavier/darker for important; **no all-caps**; **don't hard-code font styles or sizes** — use the standard named styles (body / heading / caption / caption-heading) so accessibility scaling works. [S: guidelines/typography]
- **Keyboard:** "every action should also be possible with the keyboard"; test the app with just a keyboard; Ctrl+letter for app shortcuts. [S: guidelines/keyboard]
- **Dialogs:** alert dialogs (respond before continuing) vs action dialogs — modal interruption is the exception, not the default. [S: patterns/feedback/dialogs]
- **GNOME Shell design team retrospective (Aug 2026, official blog, tier A):** Quick Settings is validated platform-wide ("puts a few essential pieces of information at your fingertips"), **but "as we've added more features… the quick settings menu has grown larger and larger"** — the fix is user-editable toggle sets (progressive disclosure by curation), not more sections. They also call their calendar popover "a bit of an odd mix of things… loosely related elements that can each have wildly different amounts of content," and are re-splitting it **by frequency and theme** (weather/clocks/events into calendar; notifications into quick settings). [A: blogs.gnome.org/shell-dev/2026/08/11/gnome-shell-design-dreams/]

### 3.3 Microsoft (learn.microsoft.com)
- **Premise correction:** Windows 11 **Quick Settings has no public design guidance** — Microsoft documents the shell surface only in support/answers pages (fixed layout, user-customizable toggle set). Documented official guidance for tray icons remains the **Windows 7-era UX Guide "Notification Area"** page, which Microsoft itself stamps as legacy but "still appl[ies] in principle": an icon is justified only if status is *useful and relevant* — "are users likely to monitor the icon and change their behavior as a result of this information? If not, either don't display the status, or put it in a log file"; icons live in an **overflow by default and are promoted by the user**; temporary status changes belong to notifications, not persistent icons. [A: learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification]
- Convergence note: all three vendors now ship a single-click quick-settings flyout with instant-apply toggles + sliders and **no confirmation dialogs** for connectivity/power state changes.

### 3.4 Material 3 (m3.material.io) + W3C
- **Lists:** "optimized for reading comprehension"; keep **primary text and supporting visuals in the same position in every row** — "Don't vary the position of elements within a list"; a row may host multiple actions (selection, icon buttons, overflow) but anchoring/alignment is what makes scanning possible; label + supporting text (1–2 lines) is the standard row anatomy. [S/A: m3.material.io/components/lists/guidelines]
- **WCAG 2.5.8 Target Size (Minimum) (AA, WCAG 2.2):** pointer targets ≥ **24×24 CSS px**, or undersized targets spaced so 24 px circles don't intersect. [A: w3.org/WAI/WCAG22/Understanding/target-size-minimum.html]
- **WCAG 1.4.1 Use of Color (A):** color must never be the only means of conveying information — pair status color with icon/shape/text. [A: w3.org/WAI/WCAG22/Understanding/use-of-color.html]

### 3.5 NN/g (independent research, tier B)
- **Fitts's Law:** acquisition time is log2(distance/width) — bigger, closer targets are faster; edge/corner targets effectively infinite along the panel edge. [B: nngroup.com/articles/fitts-law/]
- **Confirmation dialogs:** an interruption that only pays off if it actually prevents an error; overuse trains users to click through ("automaticity"). [B: nngroup.com/articles/confirmation-dialog/]
- **Proximity of consequential options:** destructive and benign actions must be **far apart** and carry **redundant visual differentiation** (position + color + label), because users act on autopilot in repetitive lists. [B: nngroup.com/articles/proximity-consequential-options/]
- **Progressive disclosure:** show a few important options initially; disclose the specialized set only on request — the canonical resolution of power-vs-simplicity. [B: nngroup.com/articles/progressive-disclosure/]

---

## 4. Pattern bank — one entry per decision, each with when/do/don't + evidence

Evidence shorthand: `HIG:<page>` = develop.kde.org/hig (S) · `SRC:<repo>/<file>` = invent.kde.org source (S) · `APPLE:<page>` · `GNOME:<page>` · `MS-UX` (A) · `M3` · `WCAG` (A) · `NN/g` (B). Full URLs in §6.

### P1 — Panel chip (compact representation) design
**When:** always; the chip is the widget's zero-interaction face.
**Do:** one identity datum + at most one status datum (symbolic icon that *changes with state*, plus optionally a number that updates: battery "%1%" [SRC:powerdevil applets/batterymonitor], clock time, live sparkline [SRC:plasma-workspace applets/systemmonitor]). Content-measured width = widest rendered content + one largeSpacing; full-cell MouseArea; `tnum` tabular digits for changing numbers; busy overlay (Plasmoid.busy) during transitions; rich tooltip with the next level of summary; middle-click secondary action for the most common toggle (airplane mode) [SRC:plasma-nm main.qml L39–74]; chip-level fallback state when data is invalid (NoTimezoneWarning) [SRC:digital-clock main.qml L153].
**Don't:** render a number that the user can't act on ("are users likely to monitor the icon and change their behavior…? If not, either don't display the status, or put it in a log file" [MS-UX, A]); keep a tray icon visible 100% of the time with nothing abnormal [HIG:status_changes]; use full-color icons in the panel (symbolic upstream [SRC:plasma-nm main.qml L56]).
**Verdict tie:** V5 (full-cell + measured width = upstream norm). Chip = 1–2 data points, trend optional via sparkline; more belongs in the tooltip/popup.

### P2 — Popup IA: flat sections vs tabs vs master-detail
**When:** choosing the skeleton of a 34×38-gu popup.
**Decision evidence:** Tabs are for "related views sharing the same level of hierarchy" and "scale poorly beyond 4 or 5 tabs" on desktop; hide the tab bar with a single tab [HIG:displaying_content]. ≤5 destinations → tab-style switcher; more → sidebar [HIG:layout_and_nav]. Lists beat grids for textual content [HIG:displaying_content]. Apple: popovers hold "a few related tasks" [APPLE:popovers].
**Do:** *homogeneous item collections* (peer lists: networks, peers, notifications, clocks) → **one flat scrolling ListView with section headers + search** (plasma-nm shape [SRC:plasma-nm ConnectionListPage.qml L52–91]; clock popup is flat sections too [SRC:digital-clock CalendarView.qml]). *Heterogeneous control surfaces* (different answer types: CPU vs GPU vs processes vs inventory) → **tabs** (2–4) — matches HIG's "grouping settings or toolview pages"; sysmon's V2 acceptance is HIG-consistent. *Selector → detail* (pick a thing, inspect it) → **master-detail with one back level** (tray pattern [SRC:systemtray ExpandedRepresentation.qml]; plasma-nm StackView drill-down [SRC:plasma-nm PopupDialog.qml]). Tree views only for inherently tree-shaped technical data (a process tree is the HIG's own example [HIG:displaying_content]).
**Don't:** tabs for a peer list (forces 2 clicks to any peer, hides counts — the V1 rejection); >4–5 tabs (HIG hard limit); nesting >1 drill-down level inside a popup; master-detail for a uniform list.
**Verdict tie:** V1+V2 are both correct and data-shaped: same-content sections → list; different-content sections → tabs.

### P3 — Progressive disclosure in small popups
**When:** content volume is unbounded or user-specific.
**Do:** collapse the low-value tail behind an explicit expander labeled "Show More" (HIG blesses the exact label for collapsed sections [HIG:displaying_content "Inline help and tooltips"]); keep the primary readout above the fold; overflow tray icons live hidden-by-default until promoted [MS-UX, A]; user-curation is the platform answer to popup bloat (GNOME Shell quick-settings editor, Windows quick-settings customization [GNOME shell-dev blog, A]).
**Don't:** hide the *only* copy of important text behind hover [HIG:displaying_content]; disclose with animation-only affordances; put "Show More" mid-list for a section that has a count header (count header + collapsed section is the consistent pair — see P4).
**Verdict tie:** V1's OFFLINE-behind-SHOW = textbook progressive disclosure [NN/g progressive-disclosure, B].

### P4 — Section headers with counts
**When:** any sectioned list view.
**Do:** upstream shape = `PlasmaExtras.ListSectionHeader` / Kirigami Heading level 2 with an optional inline section action (clock's "Events ⚙ Add…" row [SRC:digital-clock CalendarView.qml L127–154]). **Counts in headers are NOT an upstream KDE norm** — shipped plasmoids ship bare section names; counts appear in task badges and accessible descriptions ("Grid with %1 items in %2 columns" [SRC:systemtray HiddenItemsView.qml]). Our count labels (`ONLINE · 13`) are a *fleet extension* — justified ( NN/g: scannable structure; and counts make the collapsed section's stakes visible [B, inferred]), but expect no platform precedent either way.
**Don't:** counts that can be wrong (stale counts lie twice — see P9); section headers that are also toggles without a visible affordance.

### P5 — Search in popups
**When:** list can exceed ~8–10 items.
**Do:** one SearchField **in the popup header**, not the body; auto-focus on open; live filtering (`setFilterFixedString`); Ctrl+F accelerator; ↑ from list top returns to search [all: SRC:plasma-nm Toolbar.qml + PopupDialog.qml L91–105 + ConnectionListPage.qml L61–69]. Standard placeholder "Search" [HIG:text_and_labels].
**Don't:** search for short lists (plasma-nm's field stays enabled-but-pointless is a compromise, not a recommendation); search fields in the scrolling body (they scroll away); filter that doesn't update the empty state ("No matches" [SRC:plasma-nm ConnectionListPage.qml L132–134]).

### P6 — Hover states & hit targets
**When:** every interactive pixel in a panel or popup.
**Do:** hover = background/outline color change via standard controls; custom controls must re-implement hover signaling [HIG:getting_input "Signaling interactivity"]. Full-cell chip hit targets [SRC:digital-clock DigitalClock.qml]; row hover uses PlasmaExtras.Highlight [SRC:plasma-nm]. Targets ≥ 24×24 px [WCAG 2.5.8, A]; panel-edge chips get Fitts bonus at screen edge [NN/g, B].
**Don't:** click cells that miss content edges (V5 = bug by both upstream practice and WCAG); hover-only affordances for anything touch users must reach [HIG:accessibility]; pointing-finger cursor on non-link controls [HIG:getting_input].
**Nuance:** HIG says list-remove controls should be *visible, not hover-only* [HIG:displaying_content] — our V6 hover-x deviates; see V6 in §5.

### P7 — Destructive actions: armed/inline confirmation vs modal
**When:** kill process, disconnect VPN, delete row.
**Evidence stack:** KDE HIG: dialogs are last resort, "many users click through them without reading" [HIG:getting_input]; *prefer* hiding destructive commands in sub-pages/menus "so they can't be triggered by a stray click, **or else use a confirmation dialog**"; always offer undo where re-adding isn't trivial; trash over delete [HIG:simple_by_default]. NN/g: confirmations only when they truly prevent errors; separate destructive from benign options with redundant signals (distance + color + label) [B]. Apple: never stack anything above a popover except an alert [APPLE:popovers] — i.e., a modal *inside* a tray popup is anti-pattern by construction.
**Shipped reality:** KDE's own network applet disconnects VPN/Wi-Fi **on a single click, no confirmation** [SRC:plasma-nm ConnectionItem.qml L63–66], betting on instant reconnect as the "undo."
**Do (fleet rule that survives all sources):** single-click for *instantly reversible* state changes; **armed confirmation (button morphs to "Confirm disconnect" + red) or slide-to-confirm for actions with blast radius or slow recovery**; destructive always in the row's trailing position, visually distinct (red role + icon + label) from row-activate [NN/g proximity]; undo toast where possible (HIG passive-notification pattern).
**Don't:** modal dialogs from a popup (breaks popover layering + HIG dialog policy); armed state on everything (becomes click-through training [NN/g confirmation]).
**Verdict tie:** V7 is *stricter than* every shipped precedent — defensible for tailfin (VPN disconnect = workspace-wide blast radius), but not a platform norm; document per-widget which class each destructive action is.

### P8 — Semantic status color (incl. colorblind-safe)
**Do:** three semantic roles only — highlight/blue = selected+benign, orange = warning/non-default state, red = error/dangerous [HIG:status_changes]; theme-provided (Kirigami.Theme.*), never hardcoded [HIG:accessibility "change the system color scheme" test]; **always pair color with icon/shape/text** [HIG:status_changes; WCAG 1.4.1, A]. For ONLINE/OFFLINE, use presence *shape/icon* + color (green/red alone fails deuteranopia ~8% of men).
**Don't:** more than three semantic colors in one popup ("when many UI elements are colorful, the user's attention will be pulled in multiple directions" [HIG:status_changes]); color as the sole differentiator of row states.

### P9 — Empty, loading, stale states
**Do:** every empty cause gets its own labeled placeholder: icon + headline + one-line how-to-fix; PlaceholderMessage upstream for *both* list-empty and service-unavailable [SRC:plasma-nm matrix; SRC:notifications L642–669; SRC:digital-clock L376–386; GNOME placeholders, S]. Loading is a distinct state ("Looking for Wi-Fi networks" + spinner prolonged to humanMoment [SRC:plasma-nm Toolbar.qml]). Staleness: refresh on open (plasma-nm rescans on expand; notifications mark-read on open [SRC: both]), keep timers running only while visible, and **stamp provenance when data can be older than the session** — no platform does this; our `● AS OF hh:mm:ss` / `◐ STALE` (V8) is fleet-original (nearest kin: GNOME clock/weather popovers show per-item timestamps, unverified). 
**Don't:** blank areas; a single generic "Empty" for all causes; spinners with no text for >1 s waits; live-updating values whose fetch age differs from render age without a stamp.

### P10 — Settings: instant-apply vs explicit OK
**Evidence:** KDE's control contract: Switch = instant apply, CheckBox = applies on OK/Apply [HIG:getting_input]; GNOME switches likewise; KCMs are instant-apply with reset.
**Do:** in-widget settings = instant-apply switches; anything text-entry (rename, API keys) = inline edit + explicit apply/undo; separate *widget config* (configure button in popup header — upstream slot [SRC:systemtray ExpandedRepresentation.qml]) from *data management* (in-popup).
**Don't:** OK/Cancel buttons inside a popup (popovers auto-close — Apple: "always save work when automatically closing" [APPLE:popovers]; unsaved modal state in a transient surface is lost work).

### P11 — Tooltips
**Do:** chip tooltip = level-2 summary (main + sub lines) [SRC:plasma-nm main.qml L39–53]; icon-only buttons must have ToolTips (every upstream ToolButton does [SRC:systemtray]); tooltip text doubles as Accessible.name [SRC:digital-clock main.qml L148].
**Don't:** important info hover-only (touch + accessibility [HIG:displaying_content, accessibility]); tooltips longer than a sentence (use "Details" collapsible).

### P12 — Keyboard navigation in popups
**Do:** full KeyNavigation web + focus-on-open to the most sensible control (clock → configure; plasma-nm → search) [SRC:systemtray; plasma-nm]; ↑/↓ list traversal; ←/→ tab/section switching; Ctrl+F search; Esc/Alt+← pops drill-down; active focus visibly distinct [HIG:accessibility; GNOME keyboard, S].
**Don't:** popups that trap or lose focus; relying on hover for focus (plasma-nm fights ExpandableListItem's hover-steals-focus — visible in source HACK comment [SRC:plasma-nm ConnectionItem.qml L226–235]).

### P13 — Chart layout: selector + one large chart vs N mini-cards
**Evidence:** KDE's own sensor widget = one sensor face per widget; compact shows the *same* chart small, full shows it large (identity of chip and popup) [SRC:plasma-workspace applets/systemmonitor]. HIG: grids only for visual content where scrolling is undesirable; tables for ≥3 comparable data points per row [HIG:displaying_content]. plasma-nm embeds a single traffic chart inside the row's expanded details, never per-row sparklines [SRC:plasma-nm ConnectionItem.qml].
**Do:** selector-tile strip + ONE large chart (V9); small multiples only if all are simultaneously comparable (then it's a table); sparkline in the *chip*, full chart in the *popup*, same series.
**Don't:** N cards each with its own mini-graph inside one popup (mini-graphs below ~60px can't be read; forces legend-level color decoding that fails P8's color-pairing rule).

---

## 5. Verdict map — external evidence vs V1–V10

Legend: **CONSISTENT** = matches platform norms · **REFINE** = right idea, adjust the rule · **NONSTANDARD** = no external precedent (keep deliberately) .

| # | Verdict | External verdict | Evidence |
|---|---------|------------------|----------|
| V1 | No tabs for the peer list; one long scrolling list, count-labeled sections, search | **CONSISTENT** — this is precisely plasma-nm's shape (flat ListView + ListSectionHeader + header SearchField) and the HIG's list-over-grid, tabs-only-for-peer-views rules | [S: plasma-nm ConnectionListPage.qml; HIG displaying_content] |
| V2 | Tabs ARE right for multi-section system dashboards | **CONSISTENT, with a ceiling** — HIG blesses tabs for "grouping settings or contextual toolview pages" and warns they "scale poorly beyond 4 or 5" on desktop; hide the bar at n=1 | [S: HIG displaying_content, layout_and_nav] |
| V3 | Primary readouts fit without scrolling; reference lists scroll with reserved lane + footer row actions | **CONSISTENT in principle** — "avoid making a popover too big — only big enough to display its contents" (Apple); upstream disables the horizontal scrollbar in popups and gives footers a dedicated heading; but *fit-vs-scroll thresholds and a reserved scrollbar lane* are fleet engineering rules with no platform wording | [S: APPLE popovers; plasma-nm ConnectionListPage.qml L50; systemtray footer; gap noted] |
| V4 | One unified proportional type scale per popup; spot-small text is a defect | **CONSISTENT in principle, custom in numbers** — GNOME: "minimize the number of font sizes and weights," no hardcoded sizes, heavier/darker = more important; KDE chip uses a strict 2-step ratio scale; KDE's own px type table was retired with the old HIG (typography now aliases into topic pages), so no external scale governs 960×640 — ours is legitimately fleet-owned. **Refine:** GNOME bans all-caps; our 11 px micro-caps survive in KDE practice (Kirigami uses Heading levels for the same job) — keep, but weight+letterspacing must carry the hierarchy, not size alone | [S: GNOME typography; digital-clock DigitalClock.qml; HIG alias check] |
| V5 | Full-cell click targets; chip width = measured widest content | **CONSISTENT — upstream norm** (clock compact rep: full-cell MouseArea, min-width = content width) plus WCAG 2.5.8's 24×24 floor | [S: DigitalClock.qml L147–155; A: WCAG 2.5.8] |
| V6 | List-first, count in title, add/search behind explicit button, inline row edit with hover-x + undo | **MOSTLY CONSISTENT; hover-x is a deviation** — add-actions-in-header and undo-for-every-removal are HIG rules; **but HIG says remove controls on rows should be "visible, rather than appearing on hover."** Refine: persistent-but-muted × that intensifies on hover, or hover-x only where rows are dense and reversible. Count-in-title remains a fleet extension (P4) | [S: HIG displaying_content, simple_by_default] |
| V7 | Armed confirmation, never modal dialogs | **NONSTANDARD but defensible** — every source kills the modal (dialogs-last-resort, click-through risk, no layering above popovers), but the shipped norm is *no confirmation at all* for connectivity actions (plasma-nm single-click disconnect). Armed-confirm = a valid implementation of HIG's "can't be triggered by a stray click" for high-blast-radius acts (VPN kill, process kill). Classify each destructive action: instantly-reversible → single click; blast-radius/slow-recovery → armed; anything-else → undo toast | [S: HIG getting_input, simple_by_default, plasma-nm ConnectionItem.qml; B: NN/g confirmation, proximity] |
| V8 | Footer provenance stamp `● AS OF hh:mm:ss` / `◐ STALE` | **NONSTANDARD — no external precedent found.** Platforms rely on refresh-on-open + notification recency instead (plasma-nm rescan-on-expand, notifications mark-read-on-open). Keep V8 as a fleet differentiator for monitoring widgets, but pair `◐ STALE` with an explicit refresh affordance so the state is actionable | [gap; nearest S: plasma-nm main.qml L154–161, notifications FullRepresentation.qml L53–61] |
| V9 | Selector-tile strip + one large chart | **CONSISTENT** — the systemmonitor face pattern (one chart identity across chip/popup), single embedded traffic chart in plasma-nm row details, HIG's grid/table selection rules | [S: systemmonitor Compact/FullRepresentation; plasma-nm ConnectionItem.qml; HIG displaying_content] |
| V10 | Explicit labeled empty/edge rows, never blank | **CONSISTENT — strongly** — PlaceholderMessage (icon + heading + explanation) is the universal upstream pattern, with per-cause variants (empty vs no-match vs service-down vs disabled); GNOME placeholders agree. Our `NO PEERS · TAILNET EMPTY` rows map 1:1 onto heading + descriptive text | [S: plasma-nm L93–158; notifications L642–669; GNOME placeholders] |

**Net:** V1, V2, V5, V9, V10 = industry-consistent (safe defaults for every future widget). V3, V4 = principle-consistent, fleet-owned numbers. V6 = keep with one refinement (visible-vs-hover remove buttons). V7, V8 = deliberately nonstandard — document them per-widget so they read as design intent, not inconsistency.

---

## 6. Source ledger (cited in this dossier)

**KDE HIG (develop.kde.org, topic pages; raw sources at invent.kde.org/documentation/develop-kde-org `content/hig/`) — tier S:**
1. https://develop.kde.org/hig/displaying_content/ (lists/grids, tabs, tree views, tooltips, "Show More", remove-button visibility, popup outlines)
2. https://develop.kde.org/hig/layout_and_nav/ (gridUnit=18px, spacing table, positioning, ≤5 nav destinations, menus)
3. https://develop.kde.org/hig/getting_input/ (dialog minimization, Switch=instant-apply vs CheckBox=OK, hover signaling, SearchField, sliders)
4. https://develop.kde.org/hig/status_changes/ (semantic colors, don't-rely-on-color, OSDs, system-tray-icons-last-resort; aliases /hig/style/color/, /hig/platform/tray/)
5. https://develop.kde.org/hig/text_and_labels/ (placeholders, ellipses, symbols/units)
6. https://develop.kde.org/hig/simple_by_default/ (safety: hide-destructive/confirm/trash, undo mandate, defaults)
7. https://develop.kde.org/hig/accessibility/ (keyboard-only/device-only/color-scheme/font-14 QA protocols)
7b. https://develop.kde.org/hig/powerful_when_needed/ (settings switch behaviors, not on/off toggles — cited §1.8)

**KDE shipped plasmoid source (invent.kde.org, master, 2026-11-04) — tier S:**
8. plasma-workspace `applets/digital-clock/main.qml` — https://invent.kde.org/plasma/plasma-workspace/-/blob/master/applets/digital-clock/main.qml
9. plasma-workspace `applets/digital-clock/DigitalClock.qml` — full-cell chip, measured width, ratio type scale, tnum
10. plasma-workspace `applets/digital-clock/CalendarView.qml` — two-pane popup, Heading-2 sections + inline action, PlaceholderMessage
11. plasma-workspace `applets/systemtray/qml/ExpandedRepresentation.qml` — canonical header (title/actions/configure/pin), master-detail, footer
12. plasma-workspace `applets/systemtray/qml/HiddenItemsView.qml` — 2-col grid, Highlight, a11y count description
13. plasma-workspace `applets/notifications/FullRepresentation.qml` — history list, per-cause empty states, mark-read-on-open
14. plasma-workspace `applets/systemmonitor/systemmonitor/package/contents/ui/CompactRepresentation.qml` (+ `FullRepresentation.qml`) — sensor-face chip/popup identity
15. plasma-nm `applet/main.qml` — chip tooltip, busy, middle-click, scan-on-expand — https://invent.kde.org/plasma/plasma-nm/-/blob/master/applet/main.qml
16. plasma-nm `applet/PopupDialog.qml` — header toolbar, StackView drill-down, Ctrl+F, lazy model
17. plasma-nm `applet/Toolbar.qml` — icon-only switches, SearchField, humanMoment BusyIndicator
18. plasma-nm `applet/ConnectionListPage.qml` — sectioned ListView, empty-state matrix, ↑→search
19. plasma-nm `applet/ConnectionItem.qml` — ExpandableListItem anatomy, single-click disconnect, inline password
20. plasma/powerdevil `applets/batterymonitor/main.qml` — chip "%1%", state strings
21. plasma/powerdevil `applets/batterymonitor/PopupDialog.qml` (+ `CompactRepresentation.qml`) — ScrollView row-list popup

**Apple HIG — tier S:**
22. https://developer.apple.com/design/human-interface-guidelines/popovers
23. https://developer.apple.com/design/human-interface-guidelines/the-menu-bar (successor of the retired "menu bar extras" page)
24. https://developer.apple.com/design/human-interface-guidelines/menus

**GNOME — tier S (HIG) / A (Shell blog):**
25. https://developer.gnome.org/hig/patterns/feedback/placeholders/ (source rst: gitlab.gnome.org/Teams/Websites/developer.gnome.org-hig)
26. https://developer.gnome.org/hig/guidelines/typography/
27. https://developer.gnome.org/hig/guidelines/keyboard/
28. https://developer.gnome.org/hig/patterns/feedback/dialogs/
29. https://developer.gnome.org/hig/patterns/containers/popovers/ (pattern exists; guidance is mockup-based)
30. https://blogs.gnome.org/shell-dev/2026/08/11/gnome-shell-design-dreams/ (quick-settings growth, calendar-popover re-split) — A

**Microsoft — tier A:**
31. https://learn.microsoft.com/en-us/windows/win32/uxguide/winenv-notification (legacy-but-principled notification-area guidance; overflow-by-default, status-worthiness test)

**Material 3 — tier S/A:**
32. https://m3.material.io/components/lists/guidelines

**W3C — tier A (normative standards):**
33. https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html (SC 2.5.8: 24×24 px)
34. https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html (SC 1.4.1)

**NN/g — tier B:**
35. https://www.nngroup.com/articles/fitts-law/
36. https://www.nngroup.com/articles/confirmation-dialog/
37. https://www.nngroup.com/articles/proximity-consequential-options/
38. https://www.nngroup.com/articles/progressive-disclosure/

**Gaps / unverified (flagged, not silently dropped):**
- Windows 11 Quick Settings: **no public design guidance exists** (§3.3) — behavior-level claims rest on product observation, not spec.
- V8 provenance stamps: no external precedent found anywhere; kept as fleet-original.
- Kirigami type-role px values: retired with the old HIG pages; current HIG has no px scale, so V4's numbers have no external arbiter.
- GNOME HIG popover/search/tabs pages are mockup-driven (thin text) — claims about them limited to what the rst states.
- KDE HIG has **no plasmoid-specific pages**; all widget-level norms above are derived from shipped source, not spec.
- Old KDE HIG listview/master-detail pattern pages (aliases verified in front-matter) now redirect; cited via their successor topics.

