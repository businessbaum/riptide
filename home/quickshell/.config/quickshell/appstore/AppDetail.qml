import QtQuick
import QtQuick.Layouts
import qs

// One app in detail: icon, name, developer, button, description and facts.
Flickable {
    id: root

    required property var app
    signal back

    readonly property bool installed: Catalog.isInstalled(app)

    contentHeight: column.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    FastScroll {
        view: root
    }

    ColumnLayout {
        id: column
        x: 24
        y: 12
        width: root.width - 48
        spacing: 18

        // Back
        Text {
            text: "‹  Zurück"
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.accent
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: root.back()
            }
        }

        RowLayout {
            spacing: 18
            AppIcon {
                size: 112
                source: Catalog.iconSource(root.app)
                appId: root.app.icon ?? ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: root.app.name
                    wrapMode: Text.Wrap
                    font.family: Config.fontSans
                    font.pixelSize: 24
                    font.weight: Font.Bold
                    color: Config.text
                }
                Text {
                    Layout.fillWidth: true
                    text: root.app.summary
                    wrapMode: Text.Wrap
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    color: Config.textSecondary
                }
                RowLayout {
                    Layout.topMargin: 8
                    spacing: 10
                    ActionButton {
                        app: root.app
                    }
                    // Remove (only apps installed on purpose, never system packages)
                    Text {
                        visible: root.installed && Catalog.canRemove(root.app) && Catalog.busy === null
                        text: "Entfernen"
                        font.family: Config.fontSans
                        font.pixelSize: 12
                        color: "#ff453a"
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            onClicked: Confirm.ask(`Möchtest du „${root.app.name}“ entfernen?`,
                                "Deine eigenen Dateien bleiben erhalten.", "Entfernen",
                                () => Catalog.run("remove", [root.app.pkg], root.app.name))
                        }
                    }
                }
            }
        }

        // Progress / result of the running operation
        Rectangle {
            Layout.fillWidth: true
            visible: (Catalog.busy !== null && Catalog.busy.pkgs.includes(root.app.pkg)) || Catalog.lastError !== ""
            implicitHeight: progress.implicitHeight + 20
            radius: 10
            color: Config.cardBg
            border.color: Config.border
            Text {
                id: progress
                x: 12
                y: 10
                width: parent.width - 24
                text: Catalog.lastError !== "" && Catalog.busy === null ? Catalog.lastError
                    : (Catalog.log[Catalog.log.length - 1] ?? "Warte auf das Passwort …")
                wrapMode: Text.Wrap
                font.family: Config.fontMono
                font.pixelSize: 11
                color: Catalog.lastError !== "" && Catalog.busy === null ? "#ff453a" : Config.textSecondary
            }
        }

        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.app.description
            wrapMode: Text.Wrap
            lineHeight: 1.2
            font.family: Config.fontSans
            font.pixelSize: 13
            color: Config.text
        }

        // Facts
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: facts.implicitHeight
            radius: 10
            color: Config.cardBg
            border.color: Config.border
            Column {
                id: facts
                width: parent.width
                Repeater {
                    model: [
                        ["Entwickler", root.app.developer],
                        ["Paket", root.app.pkg],
                        ["Quelle", "Arch Linux (offiziell, " + root.app.repo + ")"],
                        ["Lizenz", root.app.license],
                        ["Website", root.app.homepage]
                    ].filter(f => f[1])
                    Item {
                        required property var modelData
                        required property int index
                        width: facts.width
                        height: 36
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
                            text: modelData[0]
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.textSecondary
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.65
                            horizontalAlignment: Text.AlignRight
                            text: modelData[1]
                            elide: Text.ElideMiddle
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.text
                        }
                    }
                }
            }
        }
    }
}
