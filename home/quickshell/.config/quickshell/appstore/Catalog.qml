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

    // The running operation: { action, pkgs, name } or null; its output lines
    property var busy: null
    property var log: []
    property string lastError: ""

    readonly property var categories: ["Audio & Video", "Büro", "Grafik & Foto", "Internet", "Spiele",
        "Entwicklung", "Bildung & Wissenschaft", "Werkzeuge", "System"]

    // A few well-known apps for the start page (shown if they are in the catalog)
    readonly property var featuredPkgs: ["firefox", "thunderbird", "libreoffice-fresh", "gimp", "inkscape",
        "krita", "vlc", "obs-studio", "blender", "kdenlive", "audacity", "signal-desktop", "telegram-desktop",
        "keepassxc", "gnome-maps", "gnome-weather", "loupe", "papers", "shotwell", "rhythmbox"]
    readonly property var featured: featuredPkgs.map(p => apps.find(a => a.pkg === p)).filter(a => a)

    function isInstalled(app) {
        return installed[app.pkg] === true;
    }
    function canRemove(app) {
        return explicit[app.pkg] === true;
    }
    function iconSource(app) {
        if (!app?.icon)
            return Quickshell.iconPath("application-x-executable");
        return app.icon.startsWith("/") ? "file://" + app.icon : Quickshell.iconPath(app.icon, "application-x-executable");
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
        if (busy)
            return;
        busy = { action: action, pkgs: pkgs, name: name };
        log = [];
        lastError = "";
        helper.command = ["pkexec", "/usr/local/sbin/appstore-helper", action].concat(pkgs);
        helper.running = true;
    }

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

    Process {
        id: helper
        stdout: SplitParser {
            onRead: line => root.log = root.log.concat([line]).slice(-200)
        }
        stderr: SplitParser {
            onRead: line => {
                root.log = root.log.concat([line]).slice(-200);
                if (line.includes("failed retrieving file") || line.includes("404"))
                    root.lastError = "Die Paketliste ist veraltet – bitte zuerst unter „Updates“ alles aktualisieren.";
                else if (line.startsWith("FEHLER:") || line.startsWith("error:"))
                    root.lastError = line.replace(/^FEHLER: /, "");
            }
        }
        onExited: (code, status) => {
            const b = root.busy;
            root.busy = null;
            root.refresh();
            if (b.action === "upgrade")
                root.checkUpdates();
            if (code === 0) {
                const done = { install: "wurde installiert", remove: "wurde entfernt", upgrade: "ist auf dem neuesten Stand" }[b.action];
                Notify.send("App Store", `${b.name} ${done}.`, false);
            } else if (code === 126 || code === 127) {
                // pkexec: cancelled in the password dialog / not authorised
                root.lastError = "Abgebrochen.";
            } else {
                Notify.send("App Store", `${b.name}: ${root.lastError || "Das hat nicht geklappt."}`, true);
            }
        }
    }
}
