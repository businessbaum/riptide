import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// "Anmeldeobjekte", like on a Mac: apps that open at login (add, remove) and what starts
// in the background without a window (switches). Read and written by
// scripts/login-items.py; systemd reads it at login, so changes apply from the next.
Page {
    id: page
    title: "Anmeldeobjekte"
    property var window

    property var opened: []
    property var background: []
    property bool adding: false
    property string search: ""

    function load() {
        query.running = true;
    }
    Component.onCompleted: load()

    Process {
        id: query
        command: ["python3", Quickshell.shellPath("scripts/login-items.py"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    page.opened = r.open;
                    page.background = r.background;
                } catch (e) {
                    page.opened = [];
                    page.background = [];
                }
            }
        }
    }
    Process {
        id: change
        onExited: page.load()
    }
    function run(args) {
        change.command = ["python3", Quickshell.shellPath("scripts/login-items.py")].concat(args);
        change.running = true;
    }

    // Apps that can be added: shown in the launcher, not added yet, matching the search
    readonly property var candidates: {
        const q = search.trim().toLowerCase();
        const added = new Set(opened.map(o => o.id));
        return DesktopEntries.applications.values
            .filter(e => !e.noDisplay && !added.has(Apps.plainId(e.id)))
            .filter(e => q === "" || e.name.toLowerCase().includes(q))
            .sort((a, b) => a.name.localeCompare(b.name, "de"))
            .slice(0, 8);
    }

    Group {
        title: "Beim Anmelden öffnen"
        description: "Diese Apps öffnen sich, wenn du dich anmeldest."

        Repeater {
            model: page.opened
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                iconEntry: Apps.entryById(modelData.id)
                iconAppId: modelData.id
                title: Apps.entryById(modelData.id)?.name ?? modelData.name
                DialogButton {
                    implicitWidth: 90
                    width: implicitWidth
                    text: "Entfernen"
                    onClicked: page.run(["remove", modelData.id])
                }
            }
        }
        SettingRow {
            first: page.opened.length === 0
            glyph: "+"
            glyphColour: Config.accent
            title: page.adding ? "App auswählen" : "App hinzufügen …"
            link: !page.adding
            onClicked: {
                page.search = "";
                page.adding = true;
                searchField.forceActiveFocus();
            }
            DialogButton {
                visible: page.adding
                implicitWidth: 90
                width: implicitWidth
                text: "Fertig"
                onClicked: page.adding = false
            }
        }
        // the search and the first matches, while adding
        SettingRow {
            visible: page.adding
            title: ""
            Rectangle {
                width: 260
                height: 26
                radius: 6
                color: Config.tile
                border.color: Config.border
                TextInput {
                    id: searchField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: Config.text
                    clip: true
                    onTextChanged: page.search = text
                    Keys.onEscapePressed: page.adding = false
                    Text {
                        visible: searchField.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: "App suchen"
                        font: searchField.font
                        color: Config.textSecondary
                    }
                }
            }
        }
        Repeater {
            model: page.adding ? page.candidates : []
            SettingRow {
                required property var modelData
                iconEntry: modelData
                title: modelData.name
                link: true
                onClicked: {
                    page.run(["add", Apps.plainId(modelData.id)]);
                    page.adding = false;
                }
            }
        }
    }

    Group {
        title: "Im Hintergrund"
        description: page.background.length > 0
            ? "Dienste und Apps, die bei der Anmeldung ohne Fenster starten. Änderungen gelten ab der nächsten Anmeldung."
            : "Nichts startet zusätzlich im Hintergrund. Apps, die das möchten, fragen dich vorher."

        Repeater {
            model: page.background
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                iconAppId: modelData.icon
                title: modelData.name
                subtitle: modelData.kind === "system" ? (modelData.comment || "Systemdienst") : "App"
                Toggle {
                    checked: modelData.enabled
                    onToggled: on => page.run(["set", modelData.file, on ? "on" : "off"])
                }
            }
        }
    }
}
