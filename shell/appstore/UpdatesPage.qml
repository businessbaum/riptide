import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// Available updates for the whole system (like "Softwareupdate" on a Mac).
// Arch updates everything together – single packages are never updated alone.
Flickable {
    id: root

    contentHeight: column.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    FastScroll {
        view: root
    }

    ColumnLayout {
        id: column
        x: 24
        y: 16
        width: root.width - 48
        spacing: 16

        Text {
            text: "Updates"
            font.family: Config.fontSans
            font.pixelSize: 22
            font.weight: Font.Bold
            color: Config.text
        }

        // An update is waiting for a restart or a new login
        Rectangle {
            Layout.fillWidth: true
            visible: Catalog.reboot || Catalog.relogin
            implicitHeight: waiting.implicitHeight + 24
            radius: 10
            color: Config.cardBg
            border.color: Config.border
            RowLayout {
                id: waiting
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: Catalog.reboot ? "<b>Neustart erforderlich</b><br>Einige Updates werden erst nach einem Neustart wirksam."
                        : "<b>Neu anmelden erforderlich</b><br>Hyprland wurde aktualisiert. Nach der nächsten Anmeldung läuft die neue Version."
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    color: Config.text
                }
                DialogButton {
                    implicitWidth: 130
                    width: implicitWidth
                    text: Catalog.reboot ? "Neu starten …" : "Abmelden …"
                    onClicked: Quickshell.execDetached(["qs", "ipc", "call", "session", "ask", Catalog.reboot ? "reboot" : "logout"])
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            readonly property int total: Catalog.updates.length
            Text {
                Layout.fillWidth: true
                text: Catalog.checkingUpdates ? "Suche nach Updates …"
                    : parent.total === 0 ? "Dein System ist auf dem neuesten Stand."
                    : `${parent.total} Updates verfügbar.` + (Catalog.updates.length > 0 ? " Vorher wird automatisch ein Snapshot angelegt." : "")
                wrapMode: Text.Wrap
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.textSecondary
            }
            DialogButton {
                visible: parent.total === 0 && !Catalog.checkingUpdates
                implicitWidth: 120
                width: implicitWidth
                text: "Erneut prüfen"
                onClicked: {
                    Catalog.checkUpdates();
                    Riptide.call("updates.check");
                }
            }
            DialogButton {
                visible: parent.total > 0
                implicitWidth: 160
                width: implicitWidth
                primary: true
                text: Catalog.busy?.action === "upgrade" ? "Wird aktualisiert …" : "Alle aktualisieren"
                onClicked: if (Catalog.busy === null) Catalog.updateAll()
            }
        }

        // Output while updating
        Rectangle {
            Layout.fillWidth: true
            visible: Catalog.busy?.action === "upgrade"
            implicitHeight: 160
            radius: 10
            color: Config.cardBg
            border.color: Config.border
            clip: true
            Text {
                anchors.fill: parent
                anchors.margins: 10
                verticalAlignment: Text.AlignBottom
                text: Catalog.log.slice(-9).join("\n") || "Warte auf das Passwort …"
                font.family: Config.fontMono
                font.pixelSize: 11
                color: Config.textSecondary
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: Catalog.updates.length > 0
            implicitHeight: list.implicitHeight
            radius: 10
            color: Config.cardBg
            border.color: Config.border
            Column {
                id: list
                width: parent.width
                Repeater {
                    // the system packages (apps from release archives update by themselves)
                    model: Catalog.updates
                    Item {
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 34
                        Rectangle {
                            visible: index > 0
                            x: 12
                            width: parent.width - 24
                            height: 1
                            color: Config.border
                        }
                        Text {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.pkg
                            font.family: Config.fontSans
                            font.pixelSize: 13
                            color: Config.text
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.from ? `${modelData.from}  →  ${modelData.to}` : modelData.to
                            font.family: Config.fontMono
                            font.pixelSize: 11
                            color: Config.textSecondary
                        }
                    }
                }
            }
        }
    }
}
