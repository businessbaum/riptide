pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Apps in the background (dock menu "In die Menüleiste ausblenden"): no window, still
// running – for their messages –, their icon in the menu bar instead of the dock
// (BackgroundItem.qml); from there "Öffnen" brings the window back and "Beenden" ends the
// app. Kept across logins: an app that was in the background when the session ended is
// reopened (Session.qml) and Hyprland puts its window straight onto the hidden desktop
// (hypr/modules/shell.lua). Started on purpose – dock, Spotlight, Launchpad – it leaves
// the background (Apps.launch).
//   ~/.local/state/macos/background.json   { app key: window class }
Singleton {
    id: root

    property var apps: ({})

    // the ones running now, for the menu bar: [{ key, appId, entry }]
    readonly property var running: {
        const list = [];
        for (const key in apps) {
            const windows = Apps.windowsOf(key);
            if (windows.length > 0)
                list.push({ key: key, appId: windows[0].appId, entry: Apps.entryById(key) ?? Apps.entryForAppId(windows[0].appId) });
        }
        return list;
    }

    function has(key) {
        return apps[key] !== undefined;
    }

    function save(next) {
        apps = next;
        file.setText(JSON.stringify(next) + "\n");
    }

    function enter(key, appId) {
        const next = Object.assign({}, apps);
        next[key] = appId;
        save(next);
        Hyprland.dispatch(`macos.to_background('${Apps.safe(appId)}')`);
    }

    function forget(key) {
        const next = Object.assign({}, apps);
        delete next[key];
        save(next);
    }

    // the window back onto the desktop, the icon back into the dock
    function leave(key) {
        if (!has(key))
            return;
        const appId = apps[key];
        forget(key);
        Hyprland.dispatch(`macos.from_background('${Apps.safe(appId)}')`);
    }

    function quit(key) {
        if (!has(key))
            return;
        const appId = apps[key];
        forget(key);
        Apps.quit(appId);
    }

    //   qs ipc call background enter <app key> <window class> | leave <key> | quit <key> | list
    IpcHandler {
        target: "background"
        function enter(key: string, appId: string): void {
            root.enter(key, appId);
        }
        function leave(key: string): void {
            root.leave(key);
        }
        function quit(key: string): void {
            root.quit(key);
        }
        function list(): string {
            return JSON.stringify(root.apps);
        }
    }

    // its window came to the desktop by itself (a click on one of its notifications)
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "custom" || !event.data.startsWith("background-left>>"))
                return;
            const appId = event.data.slice("background-left>>".length);
            for (const key in root.apps)
                if (root.apps[key] === appId)
                    root.forget(key);
        }
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.local/state/macos/background.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false // (no file yet: nothing in the background)
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (saved && typeof saved === "object" && !Array.isArray(saved))
                    root.apps = saved;
            } catch (e) {}
        }
    }
}
