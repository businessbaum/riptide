pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Everything that pops up at the top right goes through here: short system messages and
// app notifications. All share one frame (Banner.qml); the format depends on the kind.
// BannerWindow.qml draws them, newest on top.
//
//   Banners.show({ key, glyph | icon, title, subtitle, value, timeout })
//       short system message (StatusBanner.qml), e.g. "AirPods Pro · Verbunden"
//       key      a new message with the same key replaces the one still showing
//       glyph    Nerd Font symbol in the round badge – or icon: icon name or file path
//       value    0…1 draws a ring on the right (e.g. battery); leave out for none
//       timeout  milliseconds on screen (hovering pauses), default 4000
//   Banners.update(key, { value: 0.5 })   change a banner that is showing, if it is
//   Banners.notify(notification, alert)   app notification (NotificationCard.qml); called by
//       NotificationStore after the app's rules (System Settings → Mitteilungen) allowed it
//
// System messages are not kept in the notification centre; notifications are.
// From a script: qs ipc call banners post "<title>" "<subtitle>" "<glyph>"
Singleton {
    id: root

    // an answer is being typed into a banner: its window takes the keyboard meanwhile
    property bool typing: false

    // Order on screen, newest first: { key, kind: "status" | "notification" }
    readonly property ListModel order: ListModel {}
    // key → everything about that banner
    property var entries: ({})
    property int counter: 0

    function indexOf(key) {
        for (let i = 0; i < order.count; i++) {
            if (order.get(i).key === key)
                return i;
        }
        return -1;
    }

    function put(entry) {
        entry.stamp = Date.now(); // a new stamp shows it again and restarts its timer
        entries = Object.assign({}, entries, { [entry.key]: entry });
        if (indexOf(entry.key) < 0)
            order.insert(0, { key: entry.key, kind: entry.kind });
    }

    function show(m) {
        put({
            key: m.key ?? `status-${counter++}`,
            kind: "status",
            glyph: m.glyph ?? "",
            icon: m.icon ?? "",
            title: m.title ?? "",
            subtitle: m.subtitle ?? "",
            value: m.value ?? -1,
            timeout: m.timeout ?? 4000
        });
    }

    function notify(n, alert) {
        const critical = n.urgency === NotificationUrgency.Critical;
        // "Nicht stören": only critical notifications appear (all land in the centre)
        if (NotificationStore.doNotDisturb && !critical)
            return;
        // The same message again (e.g. "Claude is waiting …") replaces the old banner
        for (const key in entries) {
            const o = entries[key].notification;
            if (o && o.appName === n.appName && o.summary === n.summary && o.body === n.body)
                remove(key);
        }
        put({
            key: `notification-${counter++}`,
            kind: "notification",
            notification: n,
            // "Hinweis" and critical ones stay until closed
            timeout: alert || critical ? 0 : n.expireTimeout > 0 ? n.expireTimeout : 5000
        });
    }

    function update(key, fields) {
        if (entries[key])
            entries = Object.assign({}, entries, { [key]: Object.assign({}, entries[key], fields) });
    }

    function remove(key) {
        const i = indexOf(key);
        if (i >= 0)
            order.remove(i);
        const rest = Object.assign({}, entries);
        delete rest[key];
        entries = rest;
    }

    IpcHandler {
        target: "banners"

        function post(title: string, subtitle: string, glyph: string): void {
            root.show({ title, subtitle, glyph });
        }
    }
}
