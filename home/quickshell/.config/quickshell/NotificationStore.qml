pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification server, the rules per app and the history the notification centre shows.
//   Rules (System Settings → Mitteilungen, settings.json → notifications.apps.<app>):
//     "banner"  banner for a few seconds, then in the notification centre (default)
//     "alert"   "Hinweis": the banner stays until closed
//     "quiet"   only in the notification centre
//     "off"     not at all
//   Every app that sent something is remembered for that settings page
//   (~/.local/state/macos/notification-apps.json), also when it is not allowed.
//   Allowed notifications go to Banners.qml, which shows them.
//   The history keeps the last 50 – also across restarts and logins
//   (~/.local/state/macos/notifications.json) – until you remove them.
Singleton {
    id: root

    // "Nicht stören" (control centre, System Settings → Mitteilungen): only critical
    // notifications show a banner, all still land in the centre
    readonly property bool doNotDisturb: Config.settings.notifications?.do_not_disturb ?? false
    function setDoNotDisturb(on) {
        Config.updateSettings(s => {
            s.notifications = s.notifications ?? {};
            s.notifications.do_not_disturb = on;
        });
    }

    // Our own messages ("System": errors, warnings) can be quieter, never switched off
    readonly property string systemApp: "System"
    function modeOf(app) {
        const mode = Config.settings.notifications?.apps?.[app] ?? "banner";
        return app === systemApp && mode === "off" ? "banner" : mode;
    }

    // app key → { name, icon, last }
    property var senders: ({})

    // The desktop entry of the sending app, if it has one
    function entryOf(n) {
        for (const id of [n.desktopEntry, n.appIcon]) {
            if (id && !id.includes("/")) {
                const e = Apps.entryById(id);
                if (e)
                    return e;
            }
        }
        return n.appName ? Apps.entryForAppId(n.appName) : null;
    }

    // Remember the sender; returns its key (desktop entry id, else the app's name)
    function remember(n) {
        const entry = entryOf(n);
        const app = entry?.id ?? (n.appName || n.appIcon || "Unbekannt");
        senders = Object.assign({}, senders, {
            [app]: { name: entry?.name ?? (n.appName || app), icon: entry?.icon ?? n.appIcon ?? "", last: Date.now() }
        });
        sendersFile.setText(JSON.stringify(senders, null, 1) + "\n");
        return app;
    }

    function nameOf(n) {
        return n ? n.appName || senders[entryOf(n)?.id ?? ""]?.name || "" : "";
    }

    // [{ key, appName, summary, body, appIcon, image, urgency, time, live }] newest first;
    // `live` is the Notification object while the app still has it open (for its actions)
    property var history: []
    readonly property var all: history

    readonly property string file: Quickshell.env("HOME") + "/.local/state/macos/notifications.json"
    property int counter: 0

    function timeOf(entry) {
        return entry?.time ? new Date(entry.time) : new Date();
    }

    function add(n) {
        const entry = {
            key: `${Date.now()}-${counter++}`, id: n.id,
            appName: n.appName, summary: n.summary, body: n.body,
            appIcon: n.appIcon, image: n.image.startsWith("/") || n.image.startsWith("file:") ? n.image : "",
            urgency: n.urgency, time: Date.now(), live: n
        };
        // closed by the app or expired: the entry stays, only the link to the app goes
        n.closed.connect(() => entry.live = null);
        history = [entry].concat(history).slice(0, 50);
        save();
        return entry;
    }

    function remove(key) {
        const e = history.find(h => h.key === key);
        e?.live?.dismiss();
        history = history.filter(h => h.key !== key);
        save();
    }

    function clearAll() {
        for (const e of history)
            e.live?.dismiss();
        history = [];
        save();
    }

    function save() {
        storage.setText(JSON.stringify(history.map(h => ({
            key: h.key, id: h.id, appName: h.appName, summary: h.summary, body: h.body,
            appIcon: h.appIcon, image: h.image, urgency: h.urgency, time: h.time
        }))));
    }

    FileView {
        id: sendersFile
        path: Quickshell.env("HOME") + "/.local/state/macos/notification-apps.json"
        blockLoading: true
        atomicWrites: true
        onLoaded: {
            try {
                root.senders = Object.assign(JSON.parse(text()), root.senders);
            } catch (e) {}
        }
    }

    FileView {
        id: storage
        path: root.file
        blockLoading: true
        atomicWrites: true
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                if (Array.isArray(saved))
                    root.history = saved.map(h => Object.assign({ live: null }, h)).concat(root.history).slice(0, 50);
            } catch (e) {}
        }
    }

    // For troubleshooting:  qs ipc call notifications list
    //                       qs ipc call notifications remove <key>
    IpcHandler {
        target: "notifications"
        function list(): string {
            return JSON.stringify(root.history.map(h => ({
                key: h.key, app: h.appName, summary: h.summary, body: h.body,
                time: Qt.formatDateTime(new Date(h.time), "dd.MM. HH:mm:ss")
            })), null, 1);
        }
        function remove(key: string): void {
            root.remove(key);
        }
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            // After a reload of the shell the server hands over the notifications that
            // are still open once more: link them to their entry again, nothing new
            // (entries saved before ids were kept: same text is enough)
            const known = root.history.find(h => !h.live && (h.id === n.id || h.id === undefined)
                && h.appName === n.appName && h.summary === n.summary && h.body === n.body);
            if (known) {
                n.tracked = true;
                known.live = n;
                n.closed.connect(() => known.live = null);
                return;
            }
            const mode = root.modeOf(root.remember(n));
            if (mode === "off")
                return; // not tracked → discarded
            n.tracked = true;
            root.add(n);
            if (mode !== "quiet")
                Banners.notify(n, mode === "alert");
        }
    }
}
