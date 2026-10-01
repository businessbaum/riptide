import QtQuick
import Quickshell
import Quickshell.Io

// "Sofort beenden", like on a Mac (⌥⌘⎋, Apple menu): the open apps; one that hangs is
// marked "reagiert nicht" (HyprDialogs.qml). "Sofort beenden" asks once more, then ends
// the app with all its processes (ForceQuit.quit).
//   Also:  qs ipc call forcequit open
Scope {
    IpcHandler {
        target: "forcequit"
        function open(): void {
            ForceQuit.show();
        }
    }

    LazyLoader {
        active: ForceQuit.open

        FloatingWindow {
            id: win

            // one row per app: its key (desktop entry or class), name and window classes
            readonly property var apps: {
                const byKey = {};
                for (const w of Apps.windows) {
                    const key = Apps.keyForAppId(w.appId);
                    byKey[key] = byKey[key] ?? { key, name: Apps.name(key), classes: [] };
                    if (!byKey[key].classes.includes(w.appId))
                        byKey[key].classes.push(w.appId);
                }
                return Object.values(byKey).sort((a, b) => a.name.localeCompare(b.name, "de"));
            }
            property string chosen: ""
            readonly property var chosenApp: apps.find(a => a.key === chosen) ?? null
            function hangs(app) {
                return app.classes.some(c => HyprDialogs.notResponding.includes(c));
            }

            function quitChosen() {
                const app = chosenApp;
                if (!app)
                    return;
                Confirm.request({
                    app: app.key,
                    title: `Möchtest du „${app.name}“ sofort beenden?`,
                    text: "Nicht gesicherte Änderungen gehen verloren.",
                    button: "Sofort beenden",
                    action: () => ForceQuit.quit(app.classes)
                });
            }

            title: "Sofort beenden"
            color: Config.windowBg
            implicitWidth: 440
            implicitHeight: 400
            minimumSize: Qt.size(implicitWidth, implicitHeight)
            maximumSize: Qt.size(implicitWidth, implicitHeight)
            onClosed: ForceQuit.open = false

            Text {
                id: intro
                x: 20
                y: 18
                width: parent.width - 40
                text: "Wenn eine App nicht reagiert, wähle sie aus und klicke auf „Sofort beenden“."
                wrapMode: Text.Wrap
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.text
            }

            Rectangle {
                id: box
                x: 20
                anchors.top: intro.bottom
                anchors.topMargin: 12
                anchors.bottom: footer.top
                anchors.bottomMargin: 14
                width: parent.width - 40
                radius: 8
                color: Config.cardBg
                border.color: Config.border
                clip: true

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.margins: 4
                    model: win.apps
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool chosen: win.chosen === modelData.key
                        width: list.width
                        height: 32
                        radius: 6
                        color: chosen ? Config.accent : "transparent"

                        AppIcon {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            size: 22
                            entry: Apps.entryById(row.modelData.key)
                            appId: row.modelData.classes[0]
                        }
                        Text {
                            x: 40
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 48
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: row.modelData.name + (win.hangs(row.modelData)
                                ? ` <font color="${row.chosen ? "white" : "#ff453a"}">(reagiert nicht)</font>` : "")
                            font.family: Config.fontSans
                            font.pixelSize: 13
                            color: row.chosen ? "white" : Config.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: win.chosen = row.modelData.key
                            onDoubleClicked: win.quitChosen()
                        }
                    }
                }
            }

            Item {
                id: footer
                x: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                width: parent.width - 40
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Auch mit ⌥⌘⎋ zu öffnen."
                    font.family: Config.fontSans
                    font.pixelSize: 11
                    color: Config.textSecondary
                }
                DialogButton {
                    anchors.right: parent.right
                    width: 130
                    primary: true
                    enabled: win.chosenApp !== null
                    opacity: enabled ? 1 : 0.5
                    text: "Sofort beenden"
                    onClicked: win.quitChosen()
                }
            }
        }
    }
}
