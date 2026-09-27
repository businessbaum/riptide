pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Running apps and their windows, and the actions dock, menu bar and Spotlight share.
// Window logic (which window comes to the front, minimized windows) lives in
// Hyprland (modules/shell.lua); this side only asks for it.
Singleton {
    id: root

    // Helper windows that belong to another app: never in dock or ⌘Tab
    readonly property var helperPattern: /^(xdg-desktop-portal.*|hyprland-(dialog|run)|org\.quickshell)$/

    // All real app windows: [{ address, appId, title, toplevel }]
    readonly property var windows: {
        const list = [];
        for (const t of Hyprland.toplevels.values) {
            const appId = t.wayland?.appId ?? t.lastIpcObject?.class ?? "";
            if (appId === "" || helperPattern.test(appId))
                continue;
            list.push({ address: t.address, appId: appId, title: t.title, toplevel: t });
        }
        return list;
    }

    // Desktop entry id without ".desktop"
    function plainId(id) {
        return id.replace(/\.desktop$/, "");
    }

    function entryById(id) {
        return DesktopEntries.byId(plainId(id)) ?? DesktopEntries.byId(plainId(id) + ".desktop");
    }

    // The desktop entry an app window belongs to (may be null for apps without one)
    function entryForAppId(appId) {
        return DesktopEntries.heuristicLookup(appId);
    }

    // Stable key of an app: desktop entry id, else the window class
    function keyForAppId(appId) {
        const e = entryForAppId(appId);
        return e ? e.id : appId;
    }

    function windowsOf(key) {
        return windows.filter(w => keyForAppId(w.appId) === key);
    }

    function name(key) {
        const e = entryById(key) ?? entryForAppId(key);
        return e?.name ?? key;
    }

    readonly property string home: Quickshell.env("HOME")
    readonly property string genericIcon: "file://" + home + "/.local/share/icons/hicolor/scalable/apps/org.riptide.GenericApp.svg"

    function icon(entry, appId) {
        return iconCandidates(entry?.icon ?? appId ?? "")[0];
    }

    // Where an icon may be, best first. The icon theme is read once when the shell starts,
    // so apps installed later are looked up directly in the usual folders (AppIcon.qml
    // tries one after the other). The last one is the generic app icon.
    // Icons already found: name → URL (the generic icon if there was none). Filled by
    // AppIcon.qml; a plain object on purpose – new icons use it, shown ones stay as they are.
    // (Without it every icon on screen searched all folders again, e.g. each time the sound
    // menu rebuilt its list: hundreds of failed loads.)
    property var foundIcons: ({})
    function iconFound(name, url) {
        if (name)
            foundIcons[name] = url;
    }
    // an app was installed or removed: its icon may be there now
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root.foundIcons = {};
        }
    }

    function iconCandidates(name) {
        if (!name)
            return [genericIcon];
        if (foundIcons[name])
            return [foundIcons[name], genericIcon];
        if (name.startsWith("/"))
            return ["file://" + name, genericIcon];
        if (name.startsWith("file:") || name.startsWith("image:"))
            return [name, genericIcon];
        if (Quickshell.hasThemeIcon(name))
            return [Quickshell.iconPath(name), genericIcon];
        const list = [];
        const roots = [home + "/.local/share/flatpak/exports/share/icons/hicolor", "/var/lib/flatpak/exports/share/icons/hicolor",
                       home + "/.local/share/icons/hicolor", "/usr/share/icons/hicolor"];
        for (const r of roots) {
            list.push(`file://${r}/scalable/apps/${name}.svg`);
            for (const s of [512, 256, 128, 96, 64, 48])
                list.push(`file://${r}/${s}x${s}/apps/${name}.png`);
        }
        list.push(`file:///usr/share/pixmaps/${name}.svg`, `file:///usr/share/pixmaps/${name}.png`, genericIcon);
        return list;
    }

    // Pinned to the dock (settings.json → dock.pinned), for the dock and Launchpad
    function isPinned(entry) {
        return !!entry && Config.dockPinned.some(p => plainId(p) === plainId(entry.id));
    }
    function setPinned(entry, pinned) {
        Config.updateSettings(s => {
            s.dock = s.dock ?? {};
            const list = (s.dock.pinned ?? []).filter(p => plainId(p) !== plainId(entry.id));
            if (pinned)
                list.push(plainId(entry.id) + ".desktop");
            s.dock.pinned = list;
        });
    }

    // Apps started in the last seconds that have no window yet: key → start time
    property var starting: ({})
    // An app that shows a window has started: forget it, so it can be started again
    // right after that window is closed (else the next click only bounced)
    onWindowsChanged: {
        const done = Object.keys(starting).filter(k => windowsOf(entryById(k)?.id ?? k).length > 0);
        if (done.length === 0)
            return;
        const s = Object.assign({}, starting);
        for (const k of done)
            delete s[k];
        starting = s;
    }

    // Open an app like on a Mac: never a second copy. Already running → its window comes
    // to the front; just started (still bouncing) → nothing happens.
    function launch(entry) {
        const key = plainId(entry.id);
        const open = windowsOf(entryById(key)?.id ?? key);
        if (open.length > 0)
            return activate(open[0].appId);
        if (Date.now() - (starting[key] ?? 0) < 15000)
            return;
        const s = Object.assign({}, starting);
        s[key] = Date.now();
        starting = s;
        launchNew(entry);
    }

    // Start another instance on purpose (dock menu "Neues Fenster")
    function launchNew(entry) {
        Quickshell.execDetached(["uwsm", "app", "--", plainId(entry.id) + ".desktop"]);
    }

    // The app's own entries for its menu (desktop actions): "Neues privates Fenster" and
    // the like, and parts of an app merged into it (sandbox.json "part_of")
    function actionsOf(entry) {
        return (entry?.actions ?? []).filter(a => a.name).map(a => ({ id: a.id, name: a.name }));
    }
    function launchAction(entry, actionId) {
        Quickshell.execDetached(["uwsm", "app", "--", plainId(entry.id) + ".desktop:" + actionId]);
    }

    function isStarting(key) {
        return Date.now() - (starting[plainId(key)] ?? 0) < 15000 && windowsOf(key).length === 0;
    }

    function safe(appId) {
        return appId.replace(/[^A-Za-z0-9._-]/g, "");
    }

    // Bring the most recently used window of an app to the front (also from "minimized")
    function activate(appId) {
        Hyprland.dispatch(`macos.activate_app('${safe(appId)}')`);
    }

    // Dock click on a running app: in front → minimize it, else bring it to the front
    function toggle(appId) {
        Hyprland.dispatch(`macos.toggle_app('${safe(appId)}')`);
    }

    function quit(appId) {
        Hyprland.dispatch(`macos.quit_app('${safe(appId)}')`);
    }
}
