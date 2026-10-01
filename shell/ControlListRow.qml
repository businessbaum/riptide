import QtQuick

// One row of a ControlList: a symbol (accent while active), the name, a detail below it
// ("Batterie 80 %"), and at the right either a state ("Verbinde …", ✓) or a button
// ("Verbinden", "Trennen"). `clicked` for the row, `buttonClicked` for the button.
Rectangle {
    id: root

    property string glyph: ""
    property bool active: false
    property string title: ""
    property string detail: ""
    property string status: ""      // text at the right (a symbol with statusIsGlyph)
    property bool statusIsGlyph: false
    property string button: ""      // a button at the right instead of the status
    property bool hoverable: true
    signal clicked
    signal buttonClicked

    width: parent?.width ?? 0
    height: detail !== "" ? 38 : 30
    radius: 7
    color: hoverable && rowMouse.containsMouse ? Config.hover : "transparent"

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
    Text {
        id: symbol
        x: 6
        width: 18
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        font.family: Config.fontSymbols
        font.pixelSize: 15
        color: root.active ? Config.accent : Config.text
    }
    Column {
        anchors.left: symbol.right
        anchors.leftMargin: 10
        anchors.right: trailing.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        Text {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 12
            font.weight: root.active ? Font.DemiBold : Font.Normal
            color: Config.text
        }
        Text {
            width: parent.width
            visible: root.detail !== ""
            text: root.detail
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 11
            color: Config.textSecondary
        }
    }
    Item {
        id: trailing
        anchors.right: parent.right
        anchors.rightMargin: root.button !== "" ? 4 : 8
        anchors.verticalCenter: parent.verticalCenter
        width: root.button !== "" ? pill.width : statusText.implicitWidth
        height: root.button !== "" ? pill.height : statusText.implicitHeight

        Text {
            id: statusText
            visible: root.button === ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.status
            font.family: root.statusIsGlyph ? Config.fontSymbols : Config.fontSans
            font.pixelSize: 11
            color: root.active ? Config.accent : Config.textSecondary
        }
        Rectangle {
            id: pill
            visible: root.button !== ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: pillText.implicitWidth + 20
            height: 22
            radius: 11
            color: pillMouse.containsMouse ? Config.hover : "transparent"
            border.color: Config.border
            Text {
                id: pillText
                anchors.centerIn: parent
                text: root.button
                font.family: Config.fontSans
                font.pixelSize: 11
                color: Config.text
            }
            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.buttonClicked()
            }
        }
    }
}
