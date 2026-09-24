pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification server and everything that shows notifications shares:
//   banners (Notifications.qml) and the notification centre (NotificationCenter.qml).
Singleton {
    id: root

    // "Nicht stören": no banners, notifications still land in the centre
    property bool doNotDisturb: false

    // Newest first
    readonly property var all: server.trackedNotifications.values.slice().reverse()

    signal arrived(var notification)

    // Arrival time per notification id (the server does not keep one)
    property var times: ({})
    function timeOf(n) {
        return times[n?.id] ?? new Date();
    }

    function clearAll() {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
    }

    // For troubleshooting:  qs ipc call notifications list
    IpcHandler {
        target: "notifications"
        function list(): string {
            return JSON.stringify(root.all.map(n => ({
                app: n.appName, summary: n.summary, body: n.body,
                time: Qt.formatTime(root.timeOf(n), "HH:mm:ss")
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
            root.times[n.id] = new Date();
            root.arrived(n);
        }
    }
}
