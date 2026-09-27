import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs

// Storage like on a Mac: how full the system disk is and what takes the space,
// plus buttons to free some (trash, package cache).
Page {
    id: page
    title: "Speicher"

    property var values: ({})       // key → bytes
    property var folders: []        // [{ label, bytes }]
    property bool measuring: true

    function measure() {
        values = {};
        folders = [];
        measuring = true;
        info.running = true;
    }
    Component.onCompleted: measure()

    Process {
        id: info
        command: [Quickshell.shellPath("scripts/storage-info.sh")]
        stdout: SplitParser {
            onRead: line => {
                const [key, bytes, label] = line.split("|");
                if (key === "done") {
                    page.measuring = false;
                } else if (key === "folder") {
                    page.folders = page.folders.concat([{ label: label, bytes: Number(bytes) }]);
                } else {
                    const v = Object.assign({}, page.values);
                    v[key] = Number(bytes);
                    page.values = v;
                }
            }
        }
    }

    Connections {
        target: PackageAdmin
        function onFinished(action, ok) {
            page.measure();
        }
    }

    function human(bytes) {
        if (bytes === undefined || isNaN(bytes))
            return "…";
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0, v = bytes;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return v.toLocaleString(Qt.locale("de_DE"), "f", v < 10 && i > 0 ? 1 : 0) + " " + units[i];
    }

    readonly property real total: values["disk.size"] ?? 0
    readonly property real used: values["disk.used"] ?? 0

    // Categories for the list (uncompressed sizes)
    readonly property var parts: {
        const folderSum = folders.reduce((s, f) => s + f.bytes, 0);
        const home = values.home ?? 0;
        const other = Math.max(0, home - folderSum - (values.flatpak ?? 0) - (values.cache ?? 0) - (values.trash ?? 0));
        return [
            { label: "Programme (pacman)", bytes: values.apps, colour: "#0a84ff" },
            { label: "Programme (Flatpak)", bytes: values.flatpak, colour: "#5e5ce6" },
            { label: "Dokumente, Bilder & Co.", bytes: folderSum, colour: "#ff9f0a" },
            { label: "Sonstiges im persönlichen Ordner", bytes: other, colour: "#30d158" },
            { label: "Zwischenspeicher der Apps", bytes: values.cache, colour: "#8e8e93" },
            { label: "Paket-Cache", bytes: values.pkgcache, colour: "#bf5af2" },
            { label: "Papierkorb", bytes: values.trash, colour: "#ff453a" }
        ].filter(p => p.bytes !== undefined);
    }
    readonly property real partsSum: parts.reduce((s, p) => s + (p.bytes || 0), 0)

    Group {
        title: "Systemfestplatte"
        description: "Dateien werden komprimiert gespeichert. Die Einzelwerte unten sind die unkomprimierten Größen, deshalb ist ihre Summe größer als der belegte Platz."

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 14
            spacing: 10

            Text {
                text: page.total > 0 ? `${page.human(page.used)} von ${page.human(page.total)} belegt – ${page.human(page.values["disk.free"])} frei`
                                     : "Wird gemessen …"
                font.family: Config.fontSans
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Config.text
            }

            // Bar: coloured by category (share of the uncompressed sum), grey = free
            ClippingRectangle { // rounds both ends, including the coloured part
                Layout.fillWidth: true
                implicitHeight: 22
                radius: 6
                color: Config.tile
                Row {
                    id: bar
                    readonly property real usedWidth: page.total > 0 ? parent.width * page.used / page.total : 0
                    height: parent.height
                    Repeater {
                        model: page.parts
                        Rectangle {
                            required property var modelData
                            height: bar.height
                            width: page.partsSum > 0 ? bar.usedWidth * (modelData.bytes || 0) / page.partsSum : 0
                            color: modelData.colour
                        }
                    }
                }
            }
        }
    }

    Group {
        title: "Was Platz belegt"
        Repeater {
            model: page.parts
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData.label
                RowLayout {
                    spacing: 10
                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: modelData.colour
                    }
                    Text {
                        text: page.human(modelData.bytes)
                        font.family: Config.fontSans
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                        color: Config.textSecondary
                    }
                }
            }
        }
        Text {
            visible: page.measuring
            Layout.margins: 12
            text: "Ordner werden gemessen …"
            font.family: Config.fontSans
            font.pixelSize: 11
            color: Config.textSecondary
        }
    }

    Group {
        title: "Platz freigeben"
        SettingRow {
            first: true
            title: "Papierkorb leeren"
            subtitle: page.human(page.values.trash ?? 0) + " im Papierkorb"
            DialogButton {
                implicitWidth: 110
                width: implicitWidth
                text: "Leeren"
                onClicked: Confirm.ask("Papierkorb endgültig leeren?", "Die Dateien lassen sich danach nicht wiederherstellen.", "Leeren", () => {
                    Quickshell.execDetached(["gio", "trash", "--empty"]);
                    SystemSounds.ui("trash-empty");
                    measureLater.restart();
                })
            }
        }
        SettingRow {
            title: "Papierkorb automatisch leeren"
            subtitle: "Objekte, die seit mehr als 30 Tagen im Papierkorb liegen, werden gelöscht"
            Toggle {
                checked: Store.get("storage", "empty_trash_after_30_days", false)
                onToggled: on => Store.set("storage", "empty_trash_after_30_days", on)
            }
        }
        SettingRow {
            title: "Paket-Cache aufräumen"
            subtitle: "Behält von jedem Paket nur die neueste Version (für eine schnelle Rückkehr), löscht alte und die deinstallierter Programme."
            DialogButton {
                implicitWidth: 110
                width: implicitWidth
                text: PackageAdmin.busy?.action === "clean-cache" ? "Läuft …" : "Aufräumen"
                onClicked: if (!PackageAdmin.busy) PackageAdmin.run("clean-cache", [], "Paket-Cache")
            }
        }
    }

    Timer {
        id: measureLater
        interval: 1500
        onTriggered: page.measure()
    }
}
