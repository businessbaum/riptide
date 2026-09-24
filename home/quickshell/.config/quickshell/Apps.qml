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

    function icon(entry, appId) {
        return Quickshell.iconPath(entry?.icon ?? appId ?? "", "application-x-executable");
    }

    // Start an app through uwsm (own systemd scope, session environment)
    function launch(entry) {
        Quickshell.execDetached(["uwsm", "app", "--", plainId(entry.id) + ".desktop"]);
    }

    function safe(appId) {
        return appId.replace(/[^A-Za-z0-9._-]/g, "");
    }

    // Bring the most recently used window of an app to the front (also from "minimized")
    function activate(appId) {
        Hyprland.dispatch(`macos.activate_app('${safe(appId)}')`);
    }

    function quit(appId) {
        Hyprland.dispatch(`macos.quit_app('${safe(appId)}')`);
    }
}
