pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications

// The notification server, the rules per app and the history the notification centre shows.
//   Permission (Privacy.qml, permission "notifications"): an app's first notification
//   asks "„App“ möchte dir Mitteilungen senden." and waits for the answer; without
//   permission nothing is shown or kept.
//   Style (System Settings → Mitteilungen, settings.json → notifications.apps.<app>):
//     "banner"  banner for a few seconds, then in the notification centre (default)
//     "alert"   "Hinweis": the banner stays until closed
//     "quiet"   only in the notification centre
//   Every app that sent something is remembered for that settings page
//   (~/.local/state/macos/notification-apps.json), also when it is not allowed.
//   Allowed notifications go to Banners.qml, which shows them.
//   The history keeps the last 50 – also across restarts and logins
//   (~/.local/state/macos/notifications.json) – until you remove them.
Singleton {
    id: root

    // "Nicht stören" (control centre, System Settings → Mitteilungen): only critical
    // notifications show a banner, all still land in the centre. On by hand, on a
    // schedule (notifications.dnd_schedule {enabled, from, to}, also across midnight),
    // while the screen is shared and while an app is in full screen (games, films) – each
    // automatic one can be switched off in the settings.
    readonly property var dndSettings: Config.settings.notifications ?? {}
    readonly property bool dndManual: dndSettings.do_not_disturb ?? false
    property date now: new Date()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
    function minutesOf(hhmm) {
        const [h, m] = String(hhmm ?? "0:0").split(":").map(Number);
        return (h || 0) * 60 + (m || 0);
    }
    readonly property bool dndScheduled: {
        const plan = dndSettings.dnd_schedule;
        if (!plan?.enabled)
            return false;
        const t = now.getHours() * 60 + now.getMinutes();
        const from = minutesOf(plan.from ?? "22:00"), to = minutesOf(plan.to ?? "07:00");
        return from <= to ? t >= from && t < to : t >= from || t < to;
    }
    readonly property bool dndSharing: (dndSettings.dnd_when_sharing ?? true) && MediaUse.sharingScreen
    readonly property bool dndFullscreen: (dndSettings.dnd_when_fullscreen ?? true) && (Hyprland.focusedWorkspace?.hasFullscreen ?? false)
    // switched off by hand while an automatic reason holds: off until that reason ends
    property bool autoPaused: false
    readonly property bool dndAutomatic: dndScheduled || dndSharing || dndFullscreen
    onDndAutomaticChanged: if (!dndAutomatic) autoPaused = false
    readonly property bool doNotDisturb: dndManual || (dndAutomatic && !autoPaused)
    // why, for the control centre and the menu bar
    readonly property string dndReason: dndManual ? "Ein"
        : !doNotDisturb ? "Aus"
        : dndSharing ? "Bildschirm wird geteilt"
        : dndFullscreen ? "Vollbild"
        : "Bis " + (dndSettings.dnd_schedule?.to ?? "07:00")
    function setDoNotDisturb(on) {
        if (!on && dndAutomatic)
            autoPaused = true;
        if (on)
            autoPaused = false;
        Config.updateSettings(s => {
            s.notifications = s.notifications ?? {};
            s.notifications.do_not_disturb = on && !dndAutomatic;
        });
    }

    // Our own messages (errors, warnings, screenshots) need no permission
    readonly property var systemApps: ["System", "Bildschirmfoto"]
    function isSystem(app) {
        return systemApps.includes(app);
    }
    function modeOf(app) {
        const mode = Config.settings.notifications?.apps?.[app] ?? "banner";
        return mode === "off" ? "quiet" : mode;
    }

    // app key → { name, icon, last }
    property var senders: ({})

    // The desktop entry of the sending app, if it has one
    // (sandboxed apps that notify through the portal – Discord: libnotify does so in a
    // sandbox – arrive with their sandbox id, e.g. org.riptide.sandbox.discord)
    function entryOf(n) {
        for (const raw of [n.desktopEntry, n.appIcon]) {
            const id = raw?.startsWith("org.riptide.sandbox.") ? raw.slice("org.riptide.sandbox.".length) : raw;
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

    function deliver(n, app) {
        const mode = modeOf(app);
        add(n, app);
        if (mode !== "quiet")
            Banners.notify(n, mode === "alert");
        if (mode !== "quiet" && (!doNotDisturb || n.urgency === NotificationUrgency.Critical))
            playSound(n, app);
    }

    // The notification sound (settings.json notifications.sound: a sound of the
    // freedesktop theme, or "none"), per app to switch off (notifications.app_sound):
    // apps like Discord play their own. A sound the app asks for comes first; one that
    // asks for none (suppress-sound) gets none.
    function soundOn(app) {
        return (dndSettings.app_sound ?? {})[app] ?? true;
    }
    function playSound(n, app) {
        const hints = n.hints ?? {};
        if (hints["suppress-sound"] || !soundOn(app))
            return;
        const asked = hints["sound-name"];
        NotificationSounds.play(asked && NotificationSounds.list.some(s => s.value === asked) ? asked : (dndSettings.sound ?? "message"));
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

    function add(n, app) {
        const entry = {
            key: `${Date.now()}-${counter++}`, id: n.id, app: app ?? "",
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

    // the app a history entry came from (for stacks in the centre)
    function groupOf(entry) {
        return entry.app || entry.appName || "?";
    }
    function removeGroup(group) {
        for (const e of history)
            if (groupOf(e) === group)
                e.live?.dismiss();
        history = history.filter(h => groupOf(h) !== group);
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
            key: h.key, id: h.id, app: h.app, appName: h.appName, summary: h.summary, body: h.body,
            appIcon: h.appIcon, image: h.image, urgency: h.urgency, time: h.time
        }))));
    }

    FileView {
        id: sendersFile
        path: Quickshell.env("HOME") + "/.local/state/macos/notification-apps.json"
        blockLoading: true
        atomicWrites: true
        // the file is the truth: entries removed from it stay removed (before, the next
        // notification wrote the old list back)
        watchChanges: true
        onFileChanged: reload()
        property bool read: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                // (the first time keep senders that came in before the file was read)
                root.senders = read ? saved : Object.assign(saved, root.senders);
                read = true;
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
            const app = root.remember(n);
            const permission = root.isSystem(app) ? "yes" : Privacy.state(app, "notifications");
            if (permission === "no")
                return; // not tracked → discarded
            n.tracked = true;
            if (permission === "yes") {
                root.deliver(n, app);
                return;
            }
            // First notification of this app: it waits for the answer
            let closed = false;
            n.closed.connect(() => closed = true);
            Privacy.request(app, "notifications", answer => {
                if (closed)
                    return;
                if (answer === "yes")
                    root.deliver(n, app);
                else
                    n.dismiss();
            });
        }
    }
}
