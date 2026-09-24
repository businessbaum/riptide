import QtQuick
import QtQuick.Layouts
import qs

// Available updates for the whole system (like "Softwareupdate" on a Mac).
// Arch updates everything together – single packages are never updated alone.
Flickable {
    id: root

    contentHeight: column.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

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

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Text {
                Layout.fillWidth: true
                text: Catalog.checkingUpdates ? "Suche nach Updates …"
                    : Catalog.updates.length === 0 ? "Dein System ist auf dem neuesten Stand."
                    : `${Catalog.updates.length} Updates verfügbar. Vorher wird automatisch ein Snapshot angelegt.`
                wrapMode: Text.Wrap
                font.family: Config.fontSans
                font.pixelSize: 13
                color: Config.textSecondary
            }
            DialogButton {
                visible: Catalog.updates.length === 0 && !Catalog.checkingUpdates
                implicitWidth: 120
                width: implicitWidth
                text: "Erneut prüfen"
                onClicked: Catalog.checkUpdates()
            }
            DialogButton {
                visible: Catalog.updates.length > 0
                implicitWidth: 160
                width: implicitWidth
                primary: true
                text: Catalog.busy?.action === "upgrade" ? "Wird aktualisiert …" : "Alle aktualisieren"
                onClicked: if (Catalog.busy === null) Catalog.run("upgrade", [], "Das System")
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
                            text: `${modelData.from}  →  ${modelData.to}`
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
