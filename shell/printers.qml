//@ pragma AppId org.riptide.Printers
//@ pragma IconTheme Adwaita
//@ pragma UseQApplication

// "Drucker": the print queue of a printer, like the macOS printer app – what waits and
// what prints, stop/go on for single jobs and the whole printer, the supplies.
// A separate Quickshell instance (own app id → own dock icon), data from
// scripts/printers.py.
//   Start:  scripts/printers-app.sh [printer]   (org.riptide.Printers.desktop)
//   Show a printer:  qs ipc -p ~/.config/quickshell/printers.qml call printers select <name>

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

FloatingWindow {
    id: window

    property var cups: ({ printers: [], default: "", running: true })
    property string chosen: ""
    readonly property var printer: cups.printers.find(p => p.name === chosen)
        ?? cups.printers.find(p => p.default) ?? cups.printers[0] ?? null
    property var jobs: []
    property string error: ""

    readonly property string script: Quickshell.shellPath("scripts/printers.py")
    function parse(text, fallback) {
        try {
            return JSON.parse(text);
        } catch (e) {
            return fallback;
        }
    }

    IpcHandler {
        target: "printers"
        function select(name: string): void {
            window.chosen = name;
            window.refresh();
        }
    }

    onClosed: Qt.quit()
    title: printer ? printer.info : "Drucker"
    implicitWidth: 600
    implicitHeight: 440
    minimumSize: Qt.size(460, 320)
    color: Config.windowBg

    function refresh() {
        if (!lister.running)
            lister.running = true;
    }
    Component.onCompleted: refresh()
    Timer {
        running: true
        repeat: true
        interval: 2000
        onTriggered: window.refresh()
    }
    Process {
        id: lister
        command: ["python3", window.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.cups = window.parse(text, window.cups);
                if (window.printer) {
                    jobLister.command = ["python3", window.script, "jobs", window.printer.name];
                    jobLister.running = true;
                } else {
                    window.jobs = [];
                }
            }
        }
    }
    Process {
        id: jobLister
        stdout: StdioCollector {
            onStreamFinished: window.jobs = window.parse(text, [])
        }
    }
    Process {
        id: change
        stdout: StdioCollector {
            onStreamFinished: {
                window.error = window.parse(text, {}).error ?? "";
                window.refresh();
            }
        }
    }
    function run(args) {
        change.command = ["python3", script].concat(args);
        change.running = true;
    }

    function jobState(j) {
        return j.state === "printing" ? (j.pages > 0 ? `Wird gedruckt – Seite ${j.pages}` : "Wird gedruckt …")
            : j.state === "held" ? "Angehalten"
            : j.state === "stopped" ? "Gestoppt"
            : "Wartet";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // the printer: name, state, stop/go on, settings
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle {
                width: 44
                height: 44
                radius: 10
                color: Config.tile
                border.color: Config.border
                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: Config.fontSymbols
                    font.pixelSize: 22
                    color: Config.text
                }
            }
            Column {
                Layout.fillWidth: true
                spacing: 2
                Choice {
                    visible: window.cups.printers.length > 1
                    window: window
                    options: window.cups.printers.map(p => ({ value: p.name, text: p.info }))
                    current: window.printer?.name ?? ""
                    onPicked: v => {
                        window.chosen = v;
                        window.jobs = [];
                        window.refresh();
                    }
                }
                Text {
                    visible: window.cups.printers.length <= 1
                    text: window.printer?.info ?? "Kein Drucker"
                    font.family: Config.fontSans
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: Config.text
                }
                Text {
                    text: !window.cups.running ? "Der Druckdienst läuft nicht."
                        : !window.printer ? "Füge einen Drucker in den Systemeinstellungen hinzu."
                        : window.printer.offline ? "Nicht erreichbar – ist der Drucker eingeschaltet?"
                        : window.printer.state === "stopped" ? "Angehalten – Aufträge warten, bis du fortsetzt."
                        : window.printer.state === "printing" ? "Druckt …" : "Bereit"
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: window.printer?.state === "stopped" || window.printer?.offline ? "#ff9f0a" : Config.textSecondary
                }
            }
            DialogButton {
                visible: window.printer !== null
                implicitWidth: 110
                width: implicitWidth
                text: window.printer?.state === "stopped" ? "Fortsetzen" : "Anhalten"
                onClicked: window.run([window.printer.state === "stopped" ? "resume" : "pause", window.printer.name])
            }
            DialogButton {
                implicitWidth: 124
                width: implicitWidth
                text: "Einstellungen …"
                onClicked: Quickshell.execDetached([Quickshell.shellPath("scripts/system-settings.sh"),
                    window.printer ? "printers/" + window.printer.name : "printers"])
            }
        }

        // supplies, small
        Flow {
            Layout.fillWidth: true
            visible: (window.printer?.supplies.length ?? 0) > 0
            spacing: 14
            Repeater {
                model: window.printer?.supplies ?? []
                Row {
                    required property var modelData
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 46
                        height: 6
                        radius: 3
                        color: Config.hover
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(100, modelData.level)) / 100
                            height: parent.height
                            radius: 3
                            color: "#" + modelData.colour
                        }
                    }
                    Text {
                        text: modelData.name
                        font.family: Config.fontSans
                        font.pixelSize: 11
                        color: Config.textSecondary
                    }
                }
            }
        }

        Text {
            visible: window.error !== ""
            Layout.fillWidth: true
            text: window.error
            wrapMode: Text.Wrap
            font.family: Config.fontSans
            font.pixelSize: 12
            color: "#ff453a"
        }

        // the queue
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 10
            color: Config.cardBg
            border.color: Config.border
            clip: true

            Text {
                visible: window.jobs.length === 0
                anchors.centerIn: parent
                text: "Keine Druckaufträge"
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.textSecondary
            }

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 4
                model: window.jobs
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 52

                    Rectangle {
                        visible: row.index > 0
                        x: 10
                        width: parent.width - 20
                        height: 1
                        color: Config.border
                    }
                    Text {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.state === "held" ? "" : "" // pause / document
                        font.family: Config.fontSymbols
                        font.pixelSize: 18
                        color: Config.textSecondary
                    }
                    Column {
                        x: 42
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 42 - 90
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideMiddle
                            text: row.modelData.name
                            font.family: Config.fontSans
                            font.pixelSize: 13
                            color: Config.text
                        }
                        Text {
                            text: window.jobState(row.modelData)
                                + (row.modelData.size > 0 ? " · " + (row.modelData.size >= 1024
                                    ? (row.modelData.size / 1024).toFixed(1).replace(".", ",") + " MB" : row.modelData.size + " KB") : "")
                            font.family: Config.fontSans
                            font.pixelSize: 11
                            color: Config.textSecondary
                        }
                    }
                    // hold / go on, cancel
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: [
                                { glyph: row.modelData.state === "held" ? "" : "",
                                  action: row.modelData.state === "held" ? "release" : "hold" },
                                { glyph: "", action: "cancel" }
                            ]
                            Rectangle {
                                required property var modelData
                                width: 30
                                height: 30
                                radius: 15
                                color: jobButton.containsMouse ? Config.hover : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.glyph
                                    font.family: Config.fontSymbols
                                    font.pixelSize: 13
                                    color: Config.text
                                }
                                MouseArea {
                                    id: jobButton
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: window.run([modelData.action, window.printer.name, String(row.modelData.id)])
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
