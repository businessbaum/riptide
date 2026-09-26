pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Everything the App Store knows and does:
//   apps       official desktop apps (appstore-catalog → ~/.cache/appstore/catalog.json)
//   installed  installed package names (pacman -Qq), explicit = installed on purpose (-Qqe)
//   updates    available updates (checkupdates: checks without touching the system)
//   run()      install / remove / upgrade through the root helper (pkexec → password dialog)
Singleton {
    id: root

    property var apps: []
    property var installed: ({})
    property var explicit: ({})
    property var updates: []          // [{ pkg, from, to }]
    property bool loading: true
    property bool checkingUpdates: false

    // The running install/remove/upgrade (PackageAdmin.qml, shared with System Settings)
    readonly property var busy: PackageAdmin.busy
    readonly property var log: PackageAdmin.log
    readonly property string lastError: PackageAdmin.lastError

    readonly property var categories: ["Audio & Video", "Büro", "Grafik & Foto", "Internet", "Spiele",
        "Entwicklung", "Bildung & Wissenschaft", "Werkzeuge", "System"]

    // A few well-known apps for the start page (shown if they are in the catalog)
    readonly property var featuredPkgs: ["spotify-launcher", "firefox", "thunderbird", "libreoffice-fresh", "gimp", "inkscape",
        "krita", "vlc", "obs-studio", "blender", "kdenlive", "audacity", "signal-desktop", "telegram-desktop",
        "keepassxc", "gnome-maps", "gnome-weather", "loupe", "papers", "shotwell", "rhythmbox"]
    readonly property var featured: featuredPkgs.map(p => apps.find(a => a.pkg === p)).filter(a => a)

    function isInstalled(app) {
        return installed[app.pkg] === true;
    }
    function canRemove(app) {
        return explicit[app.pkg] === true;
    }
    // Cached catalog icon (absolute path) – theme icon names go through AppIcon's lookup
    function iconSource(app) {
        return app?.icon?.startsWith("/") ? "file://" + app.icon : "";
    }
    function search(query) {
        const q = query.trim().toLowerCase();
        if (q === "")
            return [];
        const scored = [];
        for (const a of apps) {
            const name = a.name.toLowerCase();
            let s = name.startsWith(q) ? 100 : name.includes(q) ? 70 : a.pkg.includes(q) ? 50
                : a.keywords.toLowerCase().includes(q) ? 30 : a.summary.toLowerCase().includes(q) ? 20 : 0;
            if (s > 0)
                scored.push({ a: a, s: s });
        }
        return scored.sort((x, y) => y.s - x.s).slice(0, 120).map(x => x.a);
    }

    function refresh() {
        queryInstalled.running = true;
        queryExplicit.running = true;
    }
    function checkUpdates() {
        checkingUpdates = true;
        queryUpdates.running = true;
    }

    // action: "install" | "remove" | "upgrade"
    function run(action, pkgs, name) {
        PackageAdmin.run(action, pkgs, name);
    }

    Connections {
        target: PackageAdmin
        function onFinished(action, ok) {
            root.refresh();
            if (action === "upgrade") {
                root.checkUpdates();
                Riptide.call("updates.check");
                if (root.flatpakUpdates.length > 0)
                    flatpakUpdate.running = true;
            }
        }
    }

    // What the session service found in the background (updates.py): Flatpak apps with
    // updates, and whether a restart or a new login is waiting
    property var flatpakUpdates: []
    property bool reboot: false
    property bool relogin: false
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/macos/updates.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.flatpakUpdates = s.flatpaks ?? [];
                root.reboot = s.reboot === true;
                root.relogin = s.relogin === true;
            } catch (e) {}
        }
    }
    // Flatpak apps update without the administrator password (this user's apps)
    readonly property bool updatingFlatpaks: flatpakUpdate.running
    function updateAll() {
        if (updates.length > 0)
            run("upgrade", [], "Das System"); // the Flatpaks follow (onFinished)
        else if (flatpakUpdates.length > 0)
            flatpakUpdate.running = true;
    }
    Process {
        id: flatpakUpdate
        command: ["flatpak", "update", "-y", "--noninteractive"]
        onExited: Riptide.call("updates.check") // the service looks again: badge, notices
    }
    // (connected from the start: a call before the connection would get lost)
    readonly property bool linked: Riptide.ready

    Process {
        id: buildCatalog
        running: true
        command: ["appstore-catalog"]
        onExited: catalogFile.reload()
    }
    FileView {
        id: catalogFile
        path: Quickshell.env("HOME") + "/.cache/appstore/catalog.json"
        blockLoading: true
        onLoaded: {
            try {
                root.apps = JSON.parse(text());
            } catch (e) {
                root.apps = [];
            }
            root.loading = false;
        }
        onLoadFailed: root.loading = false
    }

    function toSet(text) {
        const set = {};
        for (const l of text.split("\n"))
            if (l !== "")
                set[l] = true;
        return set;
    }
    Process {
        id: queryInstalled
        running: true
        command: ["pacman", "-Qq"]
        stdout: StdioCollector {
            onStreamFinished: root.installed = root.toSet(text)
        }
    }
    Process {
        id: queryExplicit
        running: true
        command: ["pacman", "-Qqe"]
        stdout: StdioCollector {
            onStreamFinished: root.explicit = root.toSet(text)
        }
    }
    Process {
        id: queryUpdates
        running: true
        command: ["checkupdates", "--nocolor"]
        stdout: StdioCollector {
            // "firefox 150.0-1 -> 151.0-1"
            onStreamFinished: {
                root.updates = text.split("\n").filter(l => l.includes(" -> ")).map(l => {
                    const [pkg, from, , to] = l.split(" ");
                    return { pkg: pkg, from: from, to: to };
                });
                root.checkingUpdates = false;
            }
        }
    }

}
