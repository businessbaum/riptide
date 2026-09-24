pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification server and the history the notification centre shows.
//   Banners (Notifications.qml) use the live notifications.
//   The history keeps the last 50 – also across restarts and logins
//   (~/.local/state/macos/notifications.json) – until you remove them.
Singleton {
    id: root

    // "Nicht stören": no banners, notifications still land in the centre
    property bool doNotDisturb: false

    // [{ key, appName, summary, body, appIcon, image, urgency, time, live }] newest first;
    // `live` is the Notification object while the app still has it open (for its actions)
    property var history: []
    readonly property var all: history

    signal arrived(var notification)

    readonly property string file: Quickshell.env("HOME") + "/.local/state/macos/notifications.json"
    property int counter: 0

    function timeOf(entry) {
        return entry?.time ? new Date(entry.time) : new Date();
    }

    function add(n) {
        const entry = {
            key: `${Date.now()}-${counter++}`,
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
            key: h.key, appName: h.appName, summary: h.summary, body: h.body,
            appIcon: h.appIcon, image: h.image, urgency: h.urgency, time: h.time
        }))));
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
    IpcHandler {
        target: "notifications"
        function list(): string {
            return JSON.stringify(root.history.map(h => ({
                app: h.appName, summary: h.summary, body: h.body,
                time: Qt.formatDateTime(new Date(h.time), "dd.MM. HH:mm:ss")
            })), null, 1);
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
            n.tracked = true;
            root.add(n);
            root.arrived(n);
        }
    }
}
