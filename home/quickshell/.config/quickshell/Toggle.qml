import QtQuick

// macOS switch. `toggled(bool)` fires on click; `checked` follows the outside value.
Rectangle {
    id: root

    property bool checked: false
    signal toggled(bool on)

    width: 38
    height: 22
    radius: 11
    color: checked ? Config.accent : Config.hover
    border.color: Config.border
    opacity: enabled ? 1 : 0.4
    Behavior on color {
        ColorAnimation { duration: 120 }
    }

    Rectangle {
        width: 18
        height: 18
        radius: 9
        y: 2
        x: root.checked ? root.width - width - 2 : 2
        color: "white"
        Behavior on x {
            NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
