import QtQuick

// Rounded button as in macOS dialogs; `primary` is the blue default button.
Rectangle {
    id: root

    property string text: ""
    property bool primary: false
    signal clicked

    height: 28
    radius: Config.radiusControl
    color: primary ? Config.accent : (mouse.containsMouse ? Config.hover : Config.tile)
    opacity: mouse.pressed ? 0.8 : 1

    Text {
        anchors.centerIn: parent
        text: root.text
        font.family: Config.fontSans
        font.pixelSize: 13
        font.weight: root.primary ? Font.DemiBold : Font.Normal
        color: root.primary ? "white" : Config.text
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
