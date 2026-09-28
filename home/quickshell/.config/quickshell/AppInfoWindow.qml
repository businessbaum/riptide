import QtQuick
import Quickshell
import Quickshell.Io

// "Über „App“", like on a Mac: the app's icon, name and version – and here also where it
// comes from and whether it runs in a sandbox. Data: scripts/app-info.py.
//   Also:  qs ipc call appinfo open <desktop id>
Scope {
    IpcHandler {
        target: "appinfo"
        function open(id: string): void {
            AppInfo.show(Apps.entryById(id));
        }
        function close(): void {
            AppInfo.entry = null;
        }
    }

    LazyLoader {
        active: AppInfo.entry !== null

        FloatingWindow {
            id: win

            readonly property var entry: AppInfo.entry
            property var info: null
            readonly property string sandbox: !info ? ""
                : info.sandbox === "riptide" ? "Ja – nur mit deinen Freigaben"
                : "Nein – Teil des Systems"
            readonly property var rows: !info ? [] : [
                ["Version", info.version],
                ["Paket", info.source === "riptide" ? "riptide" : info.package],
                ["Größe", info.size],
                ["Sandbox", sandbox]
            ].filter(r => r[1] !== "")

            title: "Über " + (entry?.name ?? "")
            color: Config.windowBg
            implicitWidth: 360
            implicitHeight: content.implicitHeight + 56
            minimumSize: Qt.size(implicitWidth, implicitHeight)
            maximumSize: Qt.size(implicitWidth, implicitHeight)
            onClosed: AppInfo.entry = null

            Process {
                running: win.entry !== null
                command: ["python3", Quickshell.shellPath("scripts/app-info.py"), Apps.plainId(win.entry?.id ?? "")]
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

                AppIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    entry: win.entry
                    size: 96
                }
                Item {
                    width: 1
                    height: 10
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: win.entry?.name ?? ""
                    font.family: Config.fontSans
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: Config.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: win.entry?.comment || win.info?.comment || ""
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
                    model: win.rows
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
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    DialogButton {
                        visible: (win.info?.url ?? "") !== ""
                        width: 130
                        text: "Webseite"
                        onClicked: Quickshell.execDetached(["xdg-open", win.info.url])
                    }
                    DialogButton {
                        visible: win.info !== null && win.info.source !== "riptide"
                        width: 130
                        text: "Deinstallieren …"
                        onClicked: {
                            Quickshell.execDetached([Quickshell.shellPath("scripts/system-settings.sh"), "apps/" + Apps.plainId(win.entry.id)]);
                            win.visible = false;
                            AppInfo.entry = null;
                        }
                    }
                }
            }
        }
    }
}
