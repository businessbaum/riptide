import QtQuick
import Quickshell

// Pop-up button (like NSPopUpButton): shows the current option, click opens the list.
//   options: [{ value, text }], current: value; `picked(value)` on selection.
Rectangle {
    id: root

    property var options: []
    property var current
    property var window // (no longer used: a click anywhere outside the list closes it)
    signal picked(var value)

    readonly property var currentOption: options.find(o => o.value === current)

    implicitWidth: Math.max(120, label.implicitWidth + 40)
    height: 26
    radius: 6
    color: mouse.containsMouse ? Config.hover : Config.tile
    border.color: Config.border

    Text {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.currentOption?.text ?? String(root.current ?? "–")
        font.family: Config.fontSans
        font.pixelSize: 12
        color: Config.text
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: "" // up/down arrows
        font.family: Config.fontSymbols
        font.pixelSize: 10
        color: Config.textSecondary
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: menu.toggle()
    }

    MenuPopup {
        id: menu
        anchorItem: root
        items: root.options.map(o => ({
            text: (o.value === root.current ? "✓  " : "     ") + o.text,
            action: () => root.picked(o.value)
        }))
    }
}
