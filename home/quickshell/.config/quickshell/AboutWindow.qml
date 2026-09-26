import QtQuick
import Quickshell
import Quickshell.Io

// "Über diesen Computer", like on a Mac: a small window with a picture of the computer,
// its name and what it is made of; "Weitere Infos …" opens System Settings → Allgemein →
// Info (all of it, the name to change, the report to copy). Data: scripts/system-info.py.
//   Also:  qs ipc call about open   ("show" would be taken for qs ipc show)
Scope {
    IpcHandler {
        target: "about"
        function open(): void {
            About.show();
        }
    }

    LazyLoader {
        active: About.open

        FloatingWindow {
            id: win

            property var info: ({ name: "", system: "", rows: [] })
            function value(label) {
                return info.rows.find(r => r[0] === label)?.[1] ?? "";
            }
            // the short list; the rest is behind "Weitere Infos …"
            readonly property var shown: [
                ["Prozessor", value("Prozessor").replace(/ \(.*\)$/, "")],
                ["Grafik", value("Grafik").split(", ")[0].replace(/ \(.*\)$/, "")],
                ["Arbeitsspeicher", value("Arbeitsspeicher")],
                ["Laufwerk", value("Laufwerke").split(", ")[0].replace(/ \(.*\)$/, "")],
                ["System", info.system.replace(" · riptide", "") + (value("riptide") ? " · riptide " + value("riptide").split(" ")[0] : "")]
            ].filter(r => r[1] !== "")

            title: "Über diesen Computer"
            color: Config.windowBg
            implicitWidth: 360
            implicitHeight: content.implicitHeight + 56
            minimumSize: Qt.size(implicitWidth, implicitHeight)
            maximumSize: Qt.size(implicitWidth, implicitHeight)
            onClosed: About.open = false

            Process {
                running: true
                command: ["python3", Quickshell.shellPath("scripts/system-info.py")]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            win.info = JSON.parse(text);
                        } catch (e) {}
                    }
                }
            }

            Column {
                id: content
                anchors.horizontalCenter: parent.horizontalCenter
                y: 28
                width: parent.width - 40
                spacing: 4

                ComputerPicture {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 150
                }
                Item {
                    width: 1
                    height: 14
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.info.name
                    font.family: Config.fontSans
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: Config.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: win.value("Computer")
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: Config.textSecondary
                }
                Item {
                    width: 1
                    height: 14
                }

                // label | value, meeting in the middle, as on a Mac
                Repeater {
                    model: win.shown
                    Row {
                        required property var modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Text {
                            width: 104
                            horizontalAlignment: Text.AlignRight
                            text: modelData[0]
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.text
                        }
                        Text {
                            width: content.width - 112
                            text: modelData[1]
                            wrapMode: Text.Wrap
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.textSecondary
                        }
                    }
                }

                Item {
                    width: 1
                    height: 18
                }
                DialogButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 150
                    text: "Weitere Infos …"
                    onClicked: {
                        Quickshell.execDetached([Quickshell.shellPath("scripts/system-settings.sh"), "general/about"]);
                        win.visible = false;
                        About.open = false;
                    }
                }
            }
        }
    }
}
