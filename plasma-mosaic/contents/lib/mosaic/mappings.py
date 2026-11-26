"""Offline exact-desktop-ID mappings; URLs are evidence, never runtime fetches.

Only app-specific roots belong here: not dconf, GTK, KDE, a browser's parent
namespace, user documents, or other shared stores. The scanner must still
exclude overlapping roots from confident accounting. These are default paths;
custom profiles and portable installations are not discovered by these rules.
"""

# Baseline mappings retained without broadening their ownership claims.
RULES = {
    "com.microsoft.VSCode": {"config": ["Code"], "home": [".vscode"]},
    "dev.zed.Zed": {"config": ["zed"], "data": ["zed"], "cache": ["zed"]},
    "chromium": {"config": ["chromium"], "cache": ["chromium"]},
    "zen": {"config": ["zen"], "cache": ["zen"], "home": [".zen"]},
    "firefox": {"home": [".mozilla/firefox"], "cache": ["mozilla/firefox"]},
    "google-chrome": {"config": ["google-chrome"], "cache": ["google-chrome"]},
    "brave-browser": {"config": ["BraveSoftware/Brave-Browser"], "cache": ["BraveSoftware/Brave-Browser"]},
    "1password": {"config": ["1Password"]},
    "signal": {"config": ["Signal"]},
    "postman": {"config": ["Postman"]},
    "antigravity": {"config": ["Antigravity"], "home": [".antigravity"]},
    "proton-mail": {"config": ["Proton Mail"]},
    "proton.vpn.app.gtk": {"config": ["Proton/VPN"], "cache": ["Proton/VPN"]},
    "obsidian": {"config": ["obsidian"]},
    "typora": {"config": ["Typora"]},
    "spotify": {"config": ["spotify"], "cache": ["spotify"]},
    "org.telegram.desktop": {"data": ["TelegramDesktop"]},
    "onlyoffice-desktopeditors": {"config": ["onlyoffice"], "data": ["onlyoffice"]},
    "com.obsproject.Studio": {"config": ["obs-studio"]},
    "org.kde.kdenlive": {"config": ["kdenliverc"], "data": ["kdenlive"], "cache": ["kdenlive"]},
    "org.gnome.Nautilus": {"config": ["nautilus"], "data": ["nautilus"]},
    "com.github.xournalpp.xournalpp": {"config": ["xournalpp"], "cache": ["xournalpp"]},
    "com.github.PintaProject.Pinta": {"config": ["Pinta"]},
    "steam": {"data": ["Steam"]},
    "Alacritty": {"config": ["alacritty"]},
    "foot": {"config": ["foot"]},
    "mpv": {"config": ["mpv"]},
    "imv": {"config": ["imv"]},
    "nvim": {category: ["nvim"] for category in ("config", "cache", "data", "state")},
    # Installed desktop metadata confirms these three IDs. Upstream sources
    # below document the app-specific paths, including htop's state migration.
    "btop": {"config": ["btop"]},
    "htop": {"config": ["htop"], "state": ["htop"]},
    "com.github.johnfactotum.Foliate": {
        "config": ["com.github.johnfactotum.Foliate"],
        "data": ["com.github.johnfactotum.Foliate"],
    },
    # Desktop IDs: upstream release/freedesktop/blender.desktop,
    # GNOME/gimp desktop/gimp.desktop.in.in, videolan/vlc share/vlc.desktop.in,
    # Inkscape org.inkscape.Inkscape.appdata.xml.in's desktop-id, and
    # Thunderbird mail/installer/linux/app/debian/thunderbird.desktop.in.
    "blender": {"config": ["blender"], "cache": ["blender"]},
    "gimp": {"config": ["GIMP"]},
    "vlc": {"config": ["vlc"]},
    "org.inkscape.Inkscape": {"config": ["inkscape"]},
    "thunderbird": {"home": [".thunderbird"]},
}

# Empty means this round did not independently establish an upstream citation
# for a preserved baseline rule. Never manufacture a source for those rules.
SOURCES = dict.fromkeys(RULES, "")
SOURCES.update({
    "btop": "https://github.com/aristocratos/btop/blob/main/README.md#themes",
    "htop": "https://github.com/htop-dev/htop/blob/main/htop.1.in",
    "com.github.johnfactotum.Foliate": "https://github.com/johnfactotum/foliate/blob/gtk4/docs/faq.md",
    "blender": "https://docs.blender.org/manual/en/latest/advanced/blender_directory_layout.html",
    "gimp": "https://www.gimp.org/tutorials/GIMPProfile/",
    "vlc": "https://www.videolan.org/support/faq.html#Config",
    "org.inkscape.Inkscape": "https://wiki.inkscape.org/wiki/Environment_variables",
    "thunderbird": "https://support.mozilla.org/en-US/kb/profiles-where-thunderbird-stores-user-data",
})
