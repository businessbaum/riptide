import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Confirmation dialog in the middle of the active screen. Enter confirms, Esc cancels.
PanelWindow {
    id: root

    visible: Confirm.open
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "confirm"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    implicitWidth: 300
    implicitHeight: box.implicitHeight

    onVisibleChanged: if (visible) box.forceActiveFocus()

    Glass {
        id: box
        anchors.fill: parent
        implicitHeight: content.implicitHeight + 36

        focus: true
        Keys.onReturnPressed: Confirm.answer(true)
        Keys.onEnterPressed: Confirm.answer(true)
        Keys.onEscapePressed: Confirm.answer(false)

        Column {
            id: content
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 12

            Text {
                width: parent.width
                text: Confirm.title
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: Config.fontSans
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Config.text
            }
            Text {
                width: parent.width
                text: Confirm.text
                visible: text !== ""
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: Config.fontSans
                font.pixelSize: 12
                color: Config.textSecondary
            }
            Row {
                width: parent.width
                spacing: 8

                DialogButton {
                    width: (parent.width - 8) / 2
                    text: "Abbrechen"
                    onClicked: Confirm.answer(false)
                }
                DialogButton {
                    width: (parent.width - 8) / 2
                    text: Confirm.button
                    primary: true
                    onClicked: Confirm.answer(true)
                }
            }
        }
    }
}
