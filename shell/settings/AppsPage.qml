import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Every installed app with a launcher – from pacman, a release archive or our own – and removing it
// completely: the program, dependencies nothing else needs, and (chosen by you) its
// personal data folders, which go to the trash (so a mistake can be undone).
Page {
    id: page
    title: "Apps"
    property var window

    property var raw: []           // from apps-info.py
    // Rows, one per package / archive app / own app. Names and icons come from the launchers,
    // which are read in the background – depending on their list fills them in when ready.
    readonly property var apps: {
        const loaded = DesktopEntries.applications.values.length;
        const rows = {};
        for (const a of raw) {
            const key = a.source === "own" ? a.desktop : a.source + ":" + a.pkg;
            const e = Apps.entryById(a.desktop);
            const name = e?.name || a.pkg || a.desktop.replace(/\.desktop$/, "");
            if (!rows[key])
                rows[key] = Object.assign({ key: key, names: [], entry: e, hidden: e?.noDisplay ?? false }, a);
            rows[key].names.push(name);
            if (rows[key].hidden && e && !e.noDisplay) {
                rows[key].entry = e;
                rows[key].hidden = false;
                rows[key].names.unshift(rows[key].names.pop()); // visible launcher first
            }
        }
        return Object.values(rows).sort((x, y) => x.names[0].localeCompare(y.names[0], "de"));
    }
    property string query: ""
    property string removing: ""   // key of the row whose remove panel is open

    // Deep link "apps/<desktop id>" (Launchpad → Deinstallieren …): only that app, with its
    // remove panel open – the same removal as here, with its personal data
    property string selected: ""
    onSelectedChanged: openSelected()
    onAppsChanged: openSelected()
    function openSelected() {
        if (selected === "")
            return;
        const a = apps.find(r => Apps.plainId(r.desktop) === Apps.plainId(selected));
        if (!a)
            return; // not loaded yet
        selected = "";
        search.text = a.names[0];
        if (removable(a))
            openRemove(a);
    }
    property var leftovers: []     // [{ path, size, shared, chosen }]
    property string pendingTrash: ""

    function load() {
        list.running = true;
    }
    Component.onCompleted: load()

    function human(bytes) {
        if (!bytes)
            return "";
        const units = ["B", "KB", "MB", "GB"];
        let i = 0, v = bytes;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return v.toLocaleString(Qt.locale("de_DE"), "f", v < 10 && i > 0 ? 1 : 0) + " " + units[i];
    }

    Process {
        id: list
        command: ["python3", Quickshell.shellPath("scripts/apps-info.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.raw = JSON.parse(text);
                } catch (e) {
                    page.raw = [];
                }
            }
        }
    }

    function status(a) {
        if (a.source === "own")
            return "Eigene App (Teil dieses Desktops)";
        if (a.source === "archive")
            return `Offizielles Release (${a.pkg}) · ${page.human(a.size)}`;
        let s = `Arch-Paket ${a.pkg} · ${page.human(a.size)}`;
        if (a.protected)
            s += " · Teil des Systems";
        else if (!a.explicit)
            s += a.requiredBy.length ? ` · wird gebraucht von ${a.requiredBy.slice(0, 3).join(", ")}` : " · als Abhängigkeit installiert";
        return s;
    }
    function removable(a) {
        return a.source === "archive" || (a.source === "pacman" && a.explicit && !a.protected);
    }

    // Remove panel: find the app's personal data folders first
    Process {
        id: findLeftovers
        property var row
        stdout: StdioCollector {
            onStreamFinished: {
                let found = [];
                try {
                    found = JSON.parse(text);
                } catch (e) {}
                page.leftovers = found.map(f => Object.assign({ chosen: !f.shared }, f));
            }
        }
    }
    function openRemove(a) {
        removing = a.key;
        leftovers = [];
        findLeftovers.row = a;
        findLeftovers.command = ["python3", Quickshell.shellPath("scripts/apps-info.py"), "leftovers", a.desktop, a.pkg, a.names[0]];
        findLeftovers.running = true;
    }

    function removeCompletely(a) {
        const trash = leftovers.filter(l => l.chosen).map(l => l.path);
        removing = "";
        if (a.source === "archive") {
            archiveRemove.trash = trash;
            archiveRemove.command = [Config.bin + "archive-app", "remove", a.desktop.replace(/\.desktop$/, "")];
            archiveRemove.name = a.names[0];
            archiveRemove.running = true;
        } else {
            pendingTrash = JSON.stringify(trash);
            PackageAdmin.run("remove", [a.pkg], a.names[0]);
        }
    }

    function toTrash(paths) {
        if (paths.length > 0)
            Quickshell.execDetached(["gio", "trash", "--"].concat(paths));
    }

    // pacman removal finished → move the chosen folders to the trash, reload
    Connections {
        target: PackageAdmin
        function onFinished(action, ok) {
            if (action === "remove" && ok && page.pendingTrash !== "")
                page.toTrash(JSON.parse(page.pendingTrash));
            page.pendingTrash = "";
            page.load();
        }
    }
    // an app from a release archive (archive_apps.py): no password, it is this user's
    Process {
        id: archiveRemove
        property var trash: []
        property string name: ""
        onExited: code => {
            if (code === 0) {
                page.toTrash(trash);
                Notify.send(name, "wurde entfernt", false);
            } else {
                Notify.send(name, "Das Entfernen hat nicht geklappt.", true);
            }
            page.load();
        }
    }

    // Search
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8
        color: Config.tile
        border.color: search.activeFocus ? Config.accent : Config.border
        TextInput {
            id: search
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.text
            clip: true
            onTextChanged: page.query = text.toLowerCase()
            Text {
                visible: search.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: `${page.apps.length} Apps durchsuchen`
                font: search.font
                color: Config.textSecondary
            }
        }
    }

    Group {
        Repeater {
            model: page.apps.filter(a => page.query === "" || a.names.join(" ").toLowerCase().includes(page.query) || a.pkg.includes(page.query))

            ColumnLayout {
                id: row
                required property var modelData
                required property int index
                readonly property var app: modelData
                readonly property bool open: page.removing === app.key
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    visible: row.index > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    implicitHeight: 1
                    color: Config.border
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 8
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    spacing: 12

                    AppIcon {
                        size: 36
                        entry: row.app.entry
                        appId: row.app.desktop.replace(/\.desktop$/, "")
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: row.app.names[0] + (row.app.names.length > 1 ? `  (+${row.app.names.length - 1})` : "")
                                + (row.app.hidden ? "  · ausgeblendet" : "")
                            elide: Text.ElideRight
                            font.family: Config.fontSans
                            font.pixelSize: 13
                            color: Config.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: page.status(row.app)
                            elide: Text.ElideRight
                            font.family: Config.fontSans
                            font.pixelSize: 11
                            color: Config.textSecondary
                        }
                    }
                    DialogButton {
                        visible: page.removable(row.app)
                        implicitWidth: 100
                        width: implicitWidth
                        text: PackageAdmin.busy?.pkgs.includes(row.app.pkg) ? "Entfernt …" : "Entfernen"
                        onClicked: if (!PackageAdmin.busy) (row.open ? page.removing = "" : page.openRemove(row.app))
                    }
                }

                // Remove panel: what goes, which personal data goes to the trash
                Rectangle {
                    visible: row.open
                    Layout.fillWidth: true
                    Layout.margins: 10
                    Layout.topMargin: 0
                    implicitHeight: panel.implicitHeight + 24
                    radius: 8
                    color: Config.tile
                    border.color: Config.border

                    ColumnLayout {
                        id: panel
                        x: 12
                        y: 12
                        width: parent.width - 24
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: row.app.source === "archive"
                                ? `„${row.app.names[0]}“ wird entfernt.`
                                : `„${row.app.names[0]}“ wird entfernt, dazu alle Pakete, die nur dafür installiert wurden.`
                            wrapMode: Text.Wrap
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: page.leftovers.length === 0 ? "Keine persönlichen Daten dieser App gefunden."
                                : "Persönliche Daten – ausgewählte Ordner kommen in den Papierkorb:"
                            wrapMode: Text.Wrap
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.textSecondary
                        }
                        Repeater {
                            model: page.leftovers
                            RowLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 10
                                Toggle {
                                    checked: modelData.chosen
                                    onToggled: on => {
                                        const copy = page.leftovers.slice();
                                        copy[index] = Object.assign({}, copy[index], { chosen: on });
                                        page.leftovers = copy;
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.path.replace(Quickshell.env("HOME"), "~") + "  ·  " + page.human(modelData.size)
                                        + (modelData.shared ? "  –  Vorsicht: gehört evtl. auch zu einem anderen Programm" : "")
                                    elide: Text.ElideMiddle
                                    font.family: Config.fontSans
                                    font.pixelSize: 12
                                    color: modelData.shared ? "#ff9f0a" : Config.text
                                }
                            }
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 8
                            DialogButton {
                                implicitWidth: 100
                                width: implicitWidth
                                text: "Abbrechen"
                                onClicked: page.removing = ""
                            }
                            DialogButton {
                                implicitWidth: 150
                                width: implicitWidth
                                primary: true
                                text: "Restlos entfernen"
                                onClicked: page.removeCompletely(row.app)
                            }
                        }
                    }
                }
            }
        }
    }
}
