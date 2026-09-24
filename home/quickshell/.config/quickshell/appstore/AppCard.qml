import QtQuick
import qs

// One app in a grid: icon, name, short description, Laden/Öffnen.
Rectangle {
    id: root

    required property var app
    signal open(var app)

    implicitHeight: 84
    radius: Config.radiusTile
    color: mouse.containsMouse ? Config.hover : "transparent"

    AppIcon {
        id: icon
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        size: 60
        source: Catalog.iconSource(root.app)
    }

    Column {
        anchors.left: icon.right
        anchors.leftMargin: 12
        anchors.right: button.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: root.app.name
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Config.text
        }
        Text {
            width: parent.width
            text: root.app.summary
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            font.family: Config.fontSans
            font.pixelSize: 11
            color: Config.textSecondary
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.open(root.app)
    }

    ActionButton {
        id: button
        app: root.app
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
    }
}
