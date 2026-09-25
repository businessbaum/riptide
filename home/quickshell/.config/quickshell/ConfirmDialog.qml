import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The system's questions (Confirm.qml) in the middle of the active screen, with the
// app's icon when an app is asking. Enter confirms, Esc chooses the other button.
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
        // An app's request is never granted with Enter: pressed while typing, it would
        // give a permission by accident. Only a click grants it.
        Keys.onReturnPressed: if (!Confirm.current?.app) Confirm.answer(true)
        Keys.onEnterPressed: if (!Confirm.current?.app) Confirm.answer(true)
        Keys.onEscapePressed: Confirm.answer(false)

        Column {
            id: content
            x: 18
            y: 18
            width: parent.width - 36
            spacing: 12

            AppIcon {
                visible: Confirm.current?.app !== undefined
                anchors.horizontalCenter: parent.horizontalCenter
                size: 56
                entry: visible ? Apps.entryById(Confirm.current.app) : null
                appId: Confirm.current?.app ?? ""
            }
            Text {
                width: parent.width
                text: Confirm.current?.title ?? ""
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: Config.fontSans
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: Config.text
            }
            Text {
                width: parent.width
                text: Confirm.current?.text ?? ""
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
                    text: Confirm.current?.cancel ?? "Abbrechen"
                    onClicked: Confirm.answer(false)
                }
                DialogButton {
                    width: (parent.width - 8) / 2
                    text: Confirm.current?.button ?? ""
                    primary: true
                    onClicked: Confirm.answer(true)
                }
            }
        }
    }
}
