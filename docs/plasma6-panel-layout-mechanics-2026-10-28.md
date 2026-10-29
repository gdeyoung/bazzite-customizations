Underlying Layout Engine: KDE Plasma panels use standard QtQuick horizontal or vertical layouts (RowLayout / ColumnLayout). Spacing and expansion are dictated entirely by Layout.fillWidth, Layout.preferredWidth, and widget sizing contracts.The Spacer Primitive (org.kde.plasma.panelspacer): Spacers operate in two distinct modes: Expanding (expanding=true), which acts as an elastic spring claiming all leftover space; and Fixed (expanding=false, with a defined pixel length), which acts as static padding.The Left-Center-Right Architecture: True three-zone layouts (Left launcher/menu, Center clock/taskbar, Right status/tray) are formed by sandwiching center elements between two expanding spacers: [Left Zone] -> [Expanding Spacer 1] -> [Center Zone] -> [Expanding Spacer 2] -> [Right Zone].The Task Manager Caveat: Default Task Managers have Layout.fillWidth: true enabled by default, which competes with spacers. For a centered or spaced layout, you must either constrain the task manager, use an Icons-Only Task Manager, or adjust its alignment settings.Full Automation: The entire panel layout, spacer distribution, and widget order can be programmatically constructed via the Plasma Desktop Scripting API or scripted directly in ~/.config/plasma-org.kde.plasma.desktop-appletsrc.1. How Panel Layout Works Under the HoodIn KDE Plasma 6, a panel is a Containment (Plasma::Containment). Inside the containment, all loaded Plasmoids are arranged in a layout container that evaluates their QtQuick layout properties:Static Elements: Widgets like the Application Launcher (Kickoff), Digital Clock, or standalone status icons declare fixed or content-dependent preferred widths (Layout.fillWidth: false).Greedy Elements: Widgets that declare Layout.fillWidth: true attempt to expand and consume all unallocated space along the panel's primary axis.Competing Expansion: When multiple elements have Layout.fillWidth: true (e.g., two expanding spacers and a traditional window taskbar), Plasma divides the remaining empty space among them according to their layout constraints.2. Panel Spacers (org.kde.plasma.panelspacer)The panel spacer is a specialized native applet. It exposes two modes configurable via the UI in Panel Edit Mode or through config files:Plaintext               Panel Axis (Horizontal)
┌──────────────┬────────────────────────┬─────────────┐
│ Left Widgets │   Expanding Spacer     │ Right Tray  │
│ (Fixed Width)│  (Spring: fillWidth)   │(Fixed Width)│
└──────────────┴────────────────────────┴─────────────┘
Expanding Spacer (Flexible Spring)QML Behavior: Sets Layout.fillWidth: true.Config Value: expanding=true.Function: Pushes adjacent widgets apart. If you place one expanding spacer between your app launcher and your system tray, the launcher stays locked to the far left, and the tray is pinned to the far right.Fixed Spacer (Padding Block)QML Behavior: Sets Layout.fillWidth: false and explicitly binds Layout.preferredWidth: length.Config Values: expanding=false, length=<pixels> (e.g., length=32).Function: Creates a fixed visual buffer (e.g., separating distinct widget clusters like media controls from system monitors) without pushing elements to panel extremities.3. Engineering a Left - Center - Right LayoutTo achieve a modern bar layout (e.g., Omarchy/macOS style with Kickoff on the left, Clock/Window Title in the center, and Tray/Controls on the right):Plaintext┌──────────────┬──────────────────┬──────────────┬──────────────────┬──────────────┐
│  LEFT ZONE   │ EXPANDING SPACER │ CENTER ZONE  │ EXPANDING SPACER │  RIGHT ZONE  │
│ Launcher/Menu│      (Spring 1)  │ Clock / Title│      (Spring 2)  │ Tray / Audio │
└──────────────┴──────────────────┴──────────────┴──────────────────┴──────────────┘
The "Asymmetric Cluster" Trap & How to Fix ItBecause expanding spacers divide the remaining space equally:$$\text{Spacer Width} = \frac{\text{Total Panel Width} - (\text{Left Width} + \text{Center Width} + \text{Right Width})}{2}$$If the Left Zone (e.g., 180px) is smaller than the Right Zone (e.g., 340px for System Tray, Clock, and battery indicators), the Center Zone will be physically skewed to the left of your monitor's true geometric center.Solutions for True Screen Centering:Fixed Balancing Spacer: Add a fixed spacer on the lighter side whose width equals $\text{Right Zone Width} - \text{Left Zone Width}$.Icons-Only Task Manager Native Centering: If you are centering running applications, open the Icons-Only Task Manager Settings -> Appearance -> check Center task manager items.Plasma 6 Multi-Panel / Floating Dock Architecture: Rather than one monolithic panel, use Plasma 6's native panel properties:Left Panel: Alignment left, Width fit content.Center Dock: Alignment center, Width fit content (contains your centered apps or clock).Right Panel: Alignment right, Width fit content (contains system tray and quick settings).4. Configuration File Structure (desktop-appletsrc)KDE stores panel layouts in ~/.config/plasma-org.kde.plasma.desktop-appletsrc.Inside the file, look for the panel's containment section. Widget order is explicitly dictated by the AppletOrder semicolon-separated string:Ini, TOML[Containments][2]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=3
plugin=org.kde.panel

[Containments][2][General]
# Left -> Spacer -> Center -> Spacer -> Right
AppletOrder=10;11;12;13;14

# --- Left Widget: Application Launcher ---
[Containments][2][Applets][10]
immutability=1
plugin=org.kde.plasma.kickoff

# --- Spring 1: Left-to-Center Spacer ---
[Containments][2][Applets][11]
immutability=1
plugin=org.kde.plasma.panelspacer
[Containments][2][Applets][11][Configuration][General]
expanding=true

# --- Center Widget: Digital Clock ---
[Containments][2][Applets][12]
immutability=1
plugin=org.kde.plasma.digitalclock

# --- Spring 2: Center-to-Right Spacer ---
[Containments][2][Applets][13]
immutability=1
plugin=org.kde.plasma.panelspacer
[Containments][2][Applets][13][Configuration][General]
expanding=true

# --- Right Widget: System Tray ---
[Containments][2][Applets][14]
immutability=1
plugin=org.kde.plasma.systemtray
5. Automated Setup via Plasma Scripting APIYou can programmatically instantiate and configure this exact layout using the Plasma Desktop Scripting API.You can run this snippet in plasma-interactive-console --plasma or deploy it in a look-and-feel package:JavaScript// Remove existing top/bottom panels if re-provisioning
var allPanels = panels();
for (var i = 0; i < allPanels.length; ++i) {
    if (allPanels[i].location === "top" || allPanels[i].location === "bottom") {
        allPanels[i].remove();
    }
}

// 1. Create Top Bar Panel
var panel = new Panel();
panel.location = "top";
panel.height = 36;
panel.lengthMode = "fill"; // Full screen width in Plasma 6

// 2. Add Left Cluster
panel.addWidget("org.kde.plasma.kickoff");
panel.addWidget("org.kde.plasma.appmenu"); // Global Menu

// 3. Add Left-to-Center Spring Spacer
var spacerLeft = panel.addWidget("org.kde.plasma.panelspacer");
spacerLeft.currentConfigGroup = ["Configuration", "General"];
spacerLeft.writeConfig("expanding", "true");

// 4. Add Center Cluster
var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", "false");

// 5. Add Center-to-Right Spring Spacer
var spacerRight = panel.addWidget("org.kde.plasma.panelspacer");
spacerRight.currentConfigGroup = ["Configuration", "General"];
spacerRight.writeConfig("expanding", "true");

// 6. Add Right Cluster
panel.addWidget("org.kde.plasma.systemtray");

// Force configuration sync
panel.reloadConfig();
6. Rules for Custom Plasmoids in PanelsWhen your coding agent generates custom status or launcher Plasmoids, it must respect these layout contracts so it doesn't break panel spacers:Avoid Blanket Layout.fillWidth: true:Never set Layout.fillWidth: true on your custom widget unless you explicitly intend for it to act as an expanding spacer.Define Clamped Sizing on PlasmoidItem:QMLPlasmoidItem {
    id: root
    compactRepresentation: MouseArea {
        // Provide fixed or content-derived bounds
        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
        Layout.maximumWidth: Kirigami.Units.gridUnit * 6
        Layout.fillWidth: false // Crucial: lets spacers handle expansion
    }
}
Respect Orientation:Query Plasmoid.formFactor or plasmoid.location. If the panel is vertical (PlasmaCore.Types.Vertical), horizontal spacers rotate to act along Layout.fillHeight. Use Kirigami.Units.gridUnit rather than hardcoded pixel dimensions so the widget scales smoothly across HiDPI panels.ReferencesPlasma Desktop Scripting API Documentation: Methods and properties for Panel, Containment, and configuration groups.KDE UserBase Panels Guide: Manual UI operations, alignment toggles, and panel controller workflows.Plasma Widget Layout API: Best practices for sizing and representation constraints inside panel containments.