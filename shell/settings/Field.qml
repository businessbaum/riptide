import QtQuick
import qs

// A text field of a settings row: rounded, with a grey hint while empty.
// `accepted(text)` on Return; Escape gives up (`cancelled`).
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder: ""
    property alias input: input
    signal accepted(string text)
    signal cancelled

    implicitWidth: 260
    implicitHeight: 26
    radius: 6
    color: Config.tile
    border.color: input.activeFocus ? Config.accent : Config.border

    function edit() {
        input.forceActiveFocus();
        input.selectAll();
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: TextInput.AlignVCenter
        font.family: Config.fontSans
        font.pixelSize: 12
        color: Config.text
        selectionColor: Config.accent
        selectedTextColor: "white"
        selectByMouse: true
        clip: true
        onAccepted: root.accepted(text)
        Keys.onEscapePressed: root.cancelled()

        Text {
            visible: input.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder
            font: input.font
            color: Config.textSecondary
        }
    }
}
