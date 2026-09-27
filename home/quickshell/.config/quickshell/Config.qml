pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The single source of truth for the shell, read live from
//   ~/.config/macos/settings.json   user choices
//   ~/.config/macos/theme.json      design tokens for light and dark
// Both files are watched: saving either one updates every component at once.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/macos/"

    property var settings: ({})
    property var theme: ({})

    readonly property string mode: settings.appearance?.mode ?? "dark"
    readonly property bool dark: mode !== "light"
    readonly property var tokens: theme.modes?.[mode] ?? theme.modes?.dark ?? ({})

    // Fonts and shapes shared by both modes
    readonly property string fontSans: theme.font?.sans ?? "Inter"
    readonly property string fontMono: theme.font?.mono ?? "DejaVu Sans Mono"
    readonly property string fontSymbols: "Symbols Nerd Font"
    readonly property int radiusPanel: theme.radius?.panel ?? 18
    readonly property int radiusTile: theme.radius?.tile ?? 14
    readonly property int radiusControl: theme.radius?.control ?? 8
    // (Erscheinungsbild → Akzentfarbe wins over the theme's)
    readonly property color accent: col(settings.appearance?.accent ?? theme.accent, "#0a84ff")

    // Blur behind menu bar, dock and menus (Hyprland; off by default, see looks.lua).
    // Without blur the glass surfaces are made more opaque, so they stay calm.
    readonly property bool blur: settings.appearance?.blur === true
    function glassy(c, minAlpha) {
        return blur ? c : Qt.rgba(c.r, c.g, c.b, Math.max(c.a, minAlpha));
    }

    // Colours of the active mode
    readonly property color glass: glassy(col(tokens.glass, "#9428282e"), 0.88)
    readonly property color glassMenu: glassy(col(tokens.glass_menu, "#cc242428"), 0.95)
    readonly property color menubar: glassy(col(tokens.menubar, "#6b18181c"), 0.82)
    readonly property color border: col(tokens.border, "#24ffffff")
    readonly property color tile: col(tokens.tile, "#14ffffff")
    readonly property color hover: col(tokens.hover, "#1fffffff")
    readonly property color text: col(tokens.text, "#ffffff")
    readonly property color textSecondary: col(tokens.text_secondary, "#99ffffff")
    readonly property color windowBg: col(tokens.window_bg, "#1e1e1e")
    readonly property color sidebarBg: col(tokens.sidebar_bg, "#282828")
    readonly property color cardBg: col(tokens.card_bg, "#0fffffff")

    // Dock
    readonly property int dockSize: settings.dock?.size ?? 64
    readonly property var dockPinned: settings.dock?.pinned ?? []

    // Clock in the menu bar (Allgemein → Datum & Uhrzeit): weekday, date, 24 hours, seconds
    readonly property var clock: settings.clock ?? ({})
    readonly property bool clockSeconds: clock.seconds === true
    readonly property string clockFormat: {
        const h24 = clock.hours24 !== false;
        const day = [clock.weekday !== false ? "ddd" : "", clock.date !== false ? "d. MMM" : ""].filter(s => s).join(" ");
        const time = (h24 ? "HH:mm" : "h:mm") + (clockSeconds ? ":ss" : "") + (h24 ? "" : " AP");
        return (day ? day + "  " : "") + time;
    }

    // "rgba(40, 40, 46, 0.58)", "rgb(44, 44, 46)" or "#rrggbb" -> color
    function col(value, fallback) {
        if (!value)
            return fallback;
        const m = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/.exec(value);
        if (m)
            return Qt.rgba(m[1] / 255, m[2] / 255, m[3] / 255, m[4] === undefined ? 1 : parseFloat(m[4]));
        return value;
    }

    // Change settings: fn receives a copy, the result is saved and applied everywhere
    function updateSettings(fn) {
        const copy = JSON.parse(JSON.stringify(settings));
        fn(copy);
        settings = copy;
        settingsFile.setText(JSON.stringify(copy, null, 2) + "\n");
    }

    function parse(file, old) {
        try {
            return JSON.parse(file.text());
        } catch (e) {
            Notify.error("Einstellungen fehlerhaft", file.path.split("/").pop() + ": " + e.message);
            return old;
        }
    }

    FileView {
        id: settingsFile
        path: root.dir + "settings.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.settings = root.parse(this, root.settings);
            root.applyTheme(false);
        }
    }

    // Light/dark changed (or first start): regenerate the colour files of the apps
    // (GTK, Qt, kitty, … – see desktop-theme). Hyprland reads the JSON files itself.
    // Also for the pointer (theme and size): the generator applies it everywhere.
    property string appliedMode: ""
    function applyTheme(force) {
        const key = [mode, settings.mouse?.cursor_theme ?? "", settings.mouse?.cursor_size ?? "",
            settings.appearance?.accent ?? ""].join("|");
        if (!force && key === appliedMode)
            return;
        appliedMode = key;
        Quickshell.execDetached(["desktop-theme"]);
    }

    FileView {
        id: themeFile
        path: root.dir + "theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const first = Object.keys(root.theme).length === 0;
            root.theme = root.parse(this, root.theme);
            if (!first)
                root.applyTheme(true); // tokens edited → regenerate
        }
    }
}
