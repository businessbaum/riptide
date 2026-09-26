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

    readonly property var hours: Array.from({ length: 24 }, (_, h) => {
        const t = (h < 10 ? "0" : "") + h + ":00";
        return { value: t, text: t };
    })
    readonly property var schedule: Store.get("notifications", "dnd_schedule", { enabled: false, from: "22:00", to: "07:00" })
    function setSchedule(change) {
        Store.set("notifications", "dnd_schedule", Object.assign({}, schedule, change));
    }

    Group {
        title: "Nicht stören"
        description: "Keine Banner und kein Ton, nur kritische Meldungen erscheinen. Alles landet weiterhin in der Mitteilungszentrale."
        SettingRow {
            first: true
            title: "Nicht stören"
            subtitle: "Von Hand an, bis du es wieder ausschaltest"
            Toggle {
                checked: Store.get("notifications", "do_not_disturb", false)
                onToggled: on => Store.set("notifications", "do_not_disturb", on)
            }
        }
        SettingRow {
            title: "Nach Zeitplan"
            subtitle: "Jeden Tag in dieser Zeit"
            Row {
                spacing: 8
                Choice {
                    visible: page.schedule.enabled
                    window: page.window
                    options: page.hours
                    current: page.schedule.from
                    onPicked: v => page.setSchedule({ from: v })
                }
                Text {
                    visible: page.schedule.enabled
                    anchors.verticalCenter: parent.verticalCenter
                    text: "bis"
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: Config.textSecondary
                }
                Choice {
                    visible: page.schedule.enabled
                    window: page.window
                    options: page.hours
                    current: page.schedule.to
                    onPicked: v => page.setSchedule({ to: v })
                }
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: page.schedule.enabled
                    onToggled: on => page.setSchedule({ enabled: on })
                }
            }
        }
        SettingRow {
            title: "Beim Teilen des Bildschirms"
            subtitle: "Niemand sieht deine Mitteilungen im Stream"
            Toggle {
                checked: Store.get("notifications", "dnd_when_sharing", true)
                onToggled: on => Store.set("notifications", "dnd_when_sharing", on)
            }
        }
        SettingRow {
            title: "Bei Apps im Vollbild"
            subtitle: "Spiele und Filme werden nicht unterbrochen"
            Toggle {
                checked: Store.get("notifications", "dnd_when_fullscreen", true)
                onToggled: on => Store.set("notifications", "dnd_when_fullscreen", on)
            }
        }
    }

    Group {
        title: "Ton"
        SettingRow {
            first: true
            title: "Mitteilungston"
            subtitle: "Beim Auswählen hörst du ihn"
            Choice {
                window: page.window
                options: NotificationSounds.list
                current: Store.get("notifications", "sound", "message")
                onPicked: v => {
                    Store.set("notifications", "sound", v);
                    NotificationSounds.play(v);
                }
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
                // our own senders (NotificationStore.systemApps): never asked, cannot be switched off
                readonly property bool system: ["System", "Bildschirmfoto"].includes(modelData.key)
                first: index === 0
                iconEntry: Apps.entryById(modelData.key) ?? null
                iconAppId: system ? "org.riptide.SystemSettings" : modelData.icon || modelData.key
                title: modelData.name
                subtitle: system ? "Meldungen des Systems, lassen sich nicht ausschalten"
                    : Privacy.state(modelData.key, "notifications") === "ask" ? "Fragt bei der nächsten Mitteilung"
                    : "Zuletzt " + Qt.formatDateTime(new Date(modelData.last), "dd.MM.yyyy, HH:mm")

                Row {
                    spacing: 12
                    // its own sound on or off (apps like Discord play their own)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Ton"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        color: Config.textSecondary
                    }
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Store.get("notifications", "app_sound", {})[row.modelData.key] ?? true
                        onToggled: on => Store.set("notifications", "app_sound",
                            Object.assign({}, Store.get("notifications", "app_sound", {}), { [row.modelData.key]: on }))
                    }
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
}
