import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import Quickshell.Wayland

// Password dialog when an app needs administrator rights (polkit), like the macOS
// "… möchte Änderungen vornehmen" sheet. The shell registers itself as the session's
// polkit agent; the password goes straight to polkit and is never stored.
Scope {
    id: root

    readonly property var flow: agent.flow

    PolkitAgent {
        id: agent
    }

    PanelWindow {
        id: window

        visible: agent.isActive && root.flow !== null && !root.flow.isCompleted
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "polkit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 300
        implicitHeight: box.implicitHeight
        color: "transparent"

        onVisibleChanged: if (visible) {
            password.text = "";
            password.forceActiveFocus();
        }

        function submit() {
            if (root.flow?.isResponseRequired) {
                root.flow.submit(password.text);
                password.text = "";
            }
        }

        // Wrong password: shake like on a Mac
        Connections {
            target: root.flow
            function onAuthenticationFailed() {
                shake.restart();
                password.forceActiveFocus();
            }
        }

        Rectangle {
            id: box
            width: parent.width
            implicitHeight: content.implicitHeight + 40
            radius: Config.radiusPanel
            color: Config.glassMenu
            border.color: Config.border

            SequentialAnimation on x {
                id: shake
                running: false
                loops: 2
                NumberAnimation { to: -12; duration: 50 }
                NumberAnimation { to: 12; duration: 80 }
                NumberAnimation { to: 0; duration: 50 }
            }

            Column {
                id: content
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 12

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "" // lock
                    font.family: Config.fontSymbols
                    font.pixelSize: 34
                    color: Config.text
                }
                Text {
                    width: parent.width
                    text: root.flow?.message ?? ""
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Config.text
                }
                Text {
                    width: parent.width
                    text: "Gib dein Passwort ein, um dies zu erlauben."
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Config.fontSans
                    font.pixelSize: 11
                    color: Config.textSecondary
                }

                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 7
                    color: Config.tile
                    border.color: password.activeFocus ? Config.accent : Config.border
                    border.width: password.activeFocus ? 2 : 1

                    TextInput {
                        id: password
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        font.family: Config.fontSans
                        font.pixelSize: 13
                        color: Config.text
                        clip: true
                        enabled: root.flow?.isResponseRequired ?? false
                        Keys.onReturnPressed: window.submit()
                        Keys.onEnterPressed: window.submit()
                        Keys.onEscapePressed: root.flow?.cancelAuthenticationRequest()

                        Text {
                            visible: password.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Passwort"
                            font: password.font
                            color: Config.textSecondary
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.flow?.supplementaryMessage ?? ""
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Config.fontSans
                    font.pixelSize: 11
                    color: root.flow?.supplementaryIsError ? "#ff453a" : Config.textSecondary
                }

                Row {
                    width: parent.width
                    spacing: 8

                    DialogButton {
                        width: (parent.width - 8) / 2
                        text: "Abbrechen"
                        onClicked: root.flow?.cancelAuthenticationRequest()
                    }
                    DialogButton {
                        width: (parent.width - 8) / 2
                        text: "Erlauben"
                        primary: true
                        onClicked: window.submit()
                    }
                }
            }
        }
    }
}
