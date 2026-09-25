import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Mitteilungen: "Nicht stören" and, for every app, whether and how it may notify.
// Whether: the permission "notifications" (Privacy.qml, also under Datenschutz &
// Sicherheit); how: the style in settings.json. The shell applies both at once
// (NotificationStore.qml). Apps appear here after their first notification (the shell
// keeps the list in ~/.local/state/macos/notification-apps.json).
Page {
    id: page
    title: "Mitteilungen"
    property var window

    property var senders: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/macos/notification-apps.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                page.senders = JSON.parse(text());
            } catch (e) {}
        }
    }
    readonly property var apps: Object.keys(senders)
        .map(key => Object.assign({ key }, senders[key]))
        .sort((a, b) => a.name.localeCompare(b.name))

    readonly property var modes: [
        { value: "banner", text: "Banner" },
        { value: "alert", text: "Hinweis" },
        { value: "quiet", text: "Nur Mitteilungszentrale" },
        { value: "off", text: "Aus" }
    ]
    function modeOf(app) {
        if (app !== "System" && Privacy.state(app, "notifications") === "no")
            return "off";
        const mode = Store.get("notifications", "apps", {})[app] ?? "banner";
        return mode === "off" ? "quiet" : mode;
    }
    function setMode(app, mode) {
        if (app !== "System")
            Privacy.set(app, "notifications", mode === "off" ? "no" : "yes");
        if (mode !== "off")
            Store.set("notifications", "apps", Object.assign({}, Store.get("notifications", "apps", {}), { [app]: mode }));
    }

    Group {
        SettingRow {
            first: true
            title: "Nicht stören"
            subtitle: "Keine Banner, nur kritische Meldungen erscheinen. Alles landet weiterhin in der Mitteilungszentrale."
            Toggle {
                checked: Store.get("notifications", "do_not_disturb", false)
                onToggled: on => Store.set("notifications", "do_not_disturb", on)
            }
        }
    }

    Group {
        title: "Mitteilungen von Apps"
        description: "Banner: erscheint kurz oben rechts. Hinweis: bleibt stehen, bis du es schließt. "
            + "Außer bei „Aus“ landet alles auch in der Mitteilungszentrale. "
            + "Eine App erscheint hier, sobald sie zum ersten Mal etwas schickt."

        Repeater {
            model: page.apps

            SettingRow {
                id: row
                required property var modelData
                required property int index
                readonly property bool system: modelData.key === "System"
                first: index === 0
                iconEntry: Apps.entryById(modelData.key) ?? null
                iconAppId: system ? "org.riptide.SystemSettings" : modelData.icon || modelData.key
                title: modelData.name
                subtitle: system ? "Meldungen des Systems, lassen sich nicht ausschalten"
                    : Privacy.state(modelData.key, "notifications") === "ask" ? "Fragt bei der nächsten Mitteilung"
                    : "Zuletzt " + Qt.formatDateTime(new Date(modelData.last), "dd.MM.yyyy, HH:mm")

                Choice {
                    window: page.window
                    options: row.system ? page.modes.filter(m => m.value !== "off") : page.modes
                    current: page.modeOf(row.modelData.key)
                    onPicked: v => page.setMode(row.modelData.key, v)
                }
            }
        }
    }
}
