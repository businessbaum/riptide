import QtQuick

// A round toggle with title and status line, as in the macOS control centre.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string status: ""
    property bool on: false
    property bool available: true
    signal toggled

    implicitHeight: 44
    opacity: available ? 1 : 0.45

    Rectangle {
        id: circle
        width: 30
        height: 30
        radius: 15
        anchors.verticalCenter: parent.verticalCenter
        color: root.on ? Config.accent : Config.hover

        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: Config.fontSymbols
            font.pixelSize: 14
            color: root.on ? "white" : Config.text
        }
    }

    Column {
        anchors.left: circle.right
        anchors.leftMargin: 9
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: Config.text
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.status
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 11
            color: Config.textSecondary
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.available
        onClicked: root.toggled()
    }
}
