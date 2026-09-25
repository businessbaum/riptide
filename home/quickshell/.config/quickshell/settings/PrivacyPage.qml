import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Datenschutz & Sicherheit: every kind of permission (Mikrofon, Kamera, Ordner, …); one
// of them opens the list of apps with a switch each, like on a Mac. The decisions live in
// the system's permission store (Privacy.qml); apps without a decision ask on first use.
Page {
    id: page
    title: kind ? kind.label : "Datenschutz & Sicherheit"
    property var window

    property string selected: ""
    readonly property var kind: selected !== "" ? Privacy.kinds[selected] ?? null : null

    // System apps run without a sandbox (sandbox.json)
    property var systemPatterns: []
    FileView {
        path: Quickshell.env("HOME") + "/.config/macos/sandbox.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                page.systemPatterns = JSON.parse(text()).system_apps ?? [];
            } catch (e) {}
        }
    }
    function isSystem(id) {
        return systemPatterns.some(p => new RegExp("^" + p.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$").test(id));
    }
    function isFlatpak(entry) {
        return entry.execString.includes("flatpak run");
    }
    readonly property var visibleApps: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))
    // Terminal programs (nvtop …) run in the terminal, which is a system app
    readonly property var apps: visibleApps.filter(e => !isSystem(e.id) && !isFlatpak(e) && !e.runInTerminal)
    readonly property var systemApps: visibleApps.filter(e => isSystem(e.id) || e.runInTerminal)

    function allowedCount(key) {
        const n = apps.filter(e => Privacy.state(e.id, key) === "yes").length;
        return n === 0 ? "Keine App erlaubt" : n === 1 ? "1 App erlaubt" : `${n} Apps erlaubt`;
    }
    function howText(k) {
        const how = {
            prompt: "Apps fragen, wenn sie es zum ersten Mal brauchen.",
            portal: "Apps fragen über das System, wenn sie es brauchen.",
            switch: "Apps können hier nicht selbst fragen: Erlaube es nur, wenn eine App es braucht."
        }[k.how] ?? "";
        const files = ["desktop", "documents", "downloads", "pictures", "music", "videos"].includes(k.key)
            ? " Einzelne Dateien kann jede App trotzdem bekommen: Du wählst sie im Öffnen-Dialog aus." : "";
        const applies = k.applies === "restart" ? " Änderungen gelten ab dem nächsten Start der App." : "";
        return how + files + applies;
    }

    // ---------------------------------------------------------------- overview

    Group {
        visible: page.selected === ""
        description: "Apps laufen abgeschirmt und fragen, bevor sie etwas davon benutzen. "
            + "Hier siehst du, was jede App darf, und kannst es jederzeit ändern."

        Repeater {
            model: Privacy.kindList

            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                glyph: modelData.glyph
                glyphColour: modelData.colour
                title: modelData.label
                subtitle: page.allowedCount(modelData.key)
                link: true
                onClicked: page.selected = modelData.key
            }
        }
    }

    Group {
        visible: page.selected === ""
        title: "Ohne Abschirmung"
        description: "Systemprogramme laufen wie beim Mac ohne Sandbox und dürfen alles. "
            + "Das gilt auch für alles, was du im Terminal startest."

        Repeater {
            model: page.systemApps

            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                iconEntry: modelData
                title: modelData.name
            }
        }
    }

    // ---------------------------------------------------------------- one kind

    Text {
        visible: page.selected !== ""
        text: "\u{f0141} Datenschutz & Sicherheit"
        font.family: Config.fontSans
        font.pixelSize: 13
        color: back.containsMouse ? Config.text : Config.accent
        MouseArea {
            id: back
            anchors.fill: parent
            hoverEnabled: true
            onClicked: page.selected = ""
        }
    }

    Group {
        visible: page.selected !== ""
        description: page.kind ? page.howText(page.kind) : ""

        Repeater {
            model: page.selected !== "" ? page.apps : []

            SettingRow {
                id: row
                required property var modelData
                required property int index
                readonly property string state: Privacy.state(modelData.id, page.selected)
                first: index === 0
                iconEntry: modelData
                title: modelData.name
                subtitle: state === "ask" ? (page.kind?.how === "switch" ? "Nicht erlaubt" : "Noch nicht gefragt") : ""

                Toggle {
                    checked: row.state === "yes"
                    onToggled: on => Privacy.set(row.modelData.id, page.selected, on ? "yes" : "no")
                }
            }
        }
    }
}
