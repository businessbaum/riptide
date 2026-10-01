import QtQuick

// Clickable text or symbol in the menu bar; highlighted while hovered or `active`.
Item {
    id: root

    property alias text: label.text
    property bool symbol: false
    property bool bold: false
    property bool active: false
    signal clicked
    signal rightClicked
    signal scrolled(int delta)

    implicitWidth: label.implicitWidth + 20
    implicitHeight: parent ? parent.height : 30

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: 5
        color: root.active || mouse.containsMouse ? Config.hover : "transparent"
    }

    Text {
        id: label
        anchors.centerIn: parent
        font.family: root.symbol ? Config.fontSymbols : Config.fontSans
        font.pixelSize: root.symbol ? 15 : 13
        font.weight: root.bold ? Font.Bold : Font.Medium
        color: Config.text
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: e => e.button === Qt.RightButton ? root.rightClicked() : root.clicked()
        onWheel: e => root.scrolled(e.angleDelta.y)
    }
}
