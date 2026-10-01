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

    onVisibleChanged: if (visible) focusLater.restart()
    // the field when there is one (a password), else the dialog itself for Enter and Esc
    Timer {
        id: focusLater
        interval: 0
        onTriggered: Confirm.current?.input ? field.forceActiveFocus() : box.forceActiveFocus()
    }
    Connections {
        target: Confirm
        function onCurrentChanged() {
            if (root.visible)
                focusLater.restart();
        }
    }

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
            // a choice that comes with the answer ("Fenster wieder öffnen")
            Row {
                visible: Confirm.current?.option !== undefined
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 4
                    color: Confirm.optionChecked ? Config.accent : Config.tile
                    border.color: Confirm.optionChecked ? Config.accent : Config.border
                    Text {
                        anchors.centerIn: parent
                        visible: Confirm.optionChecked
                        text: "\uf00c"
                        font.family: Config.fontSymbols
                        font.pixelSize: 10
                        color: "white"
                    }
                }
                Text {
                    width: Math.min(implicitWidth, content.width - 24)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Confirm.current?.option?.text ?? ""
                    wrapMode: Text.Wrap
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: Config.text
                }
                TapHandler {
                    onTapped: Confirm.optionChecked = !Confirm.optionChecked
                }
            }

            // a text field when the question needs one (Confirm.qml: input)
            Rectangle {
                visible: Confirm.current?.input !== undefined
                width: parent.width
                height: 28
                radius: 6
                color: Config.tile
                border.color: field.activeFocus ? Config.accent : Config.border
                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: Confirm.current?.input?.password ? TextInput.Password : TextInput.Normal
                    passwordCharacter: "●"
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    color: Config.text
                    selectionColor: Config.accent
                    selectedTextColor: "white"
                    clip: true
                    text: Confirm.inputText
                    onTextEdited: Confirm.inputText = text
                    Keys.onReturnPressed: if (!Confirm.current?.app) Confirm.answer(true)
                    Keys.onEnterPressed: if (!Confirm.current?.app) Confirm.answer(true)
                    Keys.onEscapePressed: Confirm.answer(false)
                    Text {
                        visible: field.text === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: Confirm.current?.input?.placeholder ?? ""
                        font: field.font
                        color: Config.textSecondary
                    }
                }
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
