import QtQuick
import Quickshell

// One screen of the login window, like on a Mac: the wallpaper, date and time; on the
// main screen also the person, the password field and at the bottom sleep, restart,
// shut down. Enter logs in; Esc empties the field (or goes back from "Anderer Benutzer").
Item {
    id: root

    property bool main: true
    readonly property string fontSans: "Inter"
    readonly property string fontSymbols: "Symbols Nerd Font"

    function focusField() {
        if (Login.other && nameInput.text === "")
            nameInput.forceActiveFocus();
        else
            passwordInput.forceActiveFocus();
    }

    // the wallpaper of riptide (dark)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1b2a4a" }
            GradientStop { position: 0.55; color: "#3b2f63" }
            GradientStop { position: 1.0; color: "#5c2a4f" }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.1
        spacing: 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.date.toLocaleDateString(Qt.locale("de_DE"), "dddd, d. MMMM")
            font.family: root.fontSans
            font.pixelSize: 24
            font.weight: Font.DemiBold
            color: "#e6ffffff"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            font.family: root.fontSans
            font.pixelSize: 112
            font.weight: Font.Bold
            color: "#f2ffffff"
        }
    }

    // the person and the password (below the middle, never down on the buttons)
    Column {
        visible: root.main
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.min(parent.height * 0.56, powerRow.y - implicitHeight - 48)
        spacing: 12

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96
            height: 96
            radius: 48
            gradient: Gradient {
                GradientStop { position: 0; color: "#a1a1a6" }
                GradientStop { position: 1; color: "#6e6e73" }
            }
            border.color: "#40ffffff"
            Text {
                anchors.centerIn: parent
                visible: !Login.other
                text: Login.displayName.charAt(0).toUpperCase()
                font.family: root.fontSans
                font.pixelSize: 42
                font.weight: Font.DemiBold
                color: "white"
            }
            Text {
                anchors.centerIn: parent
                visible: Login.other
                text: "" // person
                font.family: root.fontSymbols
                font.pixelSize: 40
                color: "white"
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Login.displayName
            font.family: root.fontSans
            font.pixelSize: 18
            font.weight: Font.DemiBold
            color: "white"
        }

        // "Anderer Benutzer": the name first
        Field {
            id: nameField
            visible: Login.other
            anchors.horizontalCenter: parent.horizontalCenter
            placeholder: "Name"
            TextInput {
                id: nameInput
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                font.family: root.fontSans
                font.pixelSize: 14
                color: "white"
                clip: true
                enabled: !Login.busy
                onTextChanged: Login.otherName = text
                onAccepted: passwordInput.forceActiveFocus()
                Keys.onEscapePressed: root.back()
            }
            empty: nameInput.text === ""
        }

        Field {
            id: passwordField
            anchors.horizontalCenter: parent.horizontalCenter
            placeholder: "Passwort eingeben"
            empty: passwordInput.text === ""
            TextInput {
                id: passwordInput
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 40
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                font.family: root.fontSans
                font.pixelSize: 14
                font.letterSpacing: 2
                color: "white"
                clip: true
                enabled: !Login.busy
                focus: true
                onAccepted: root.submit()
                Keys.onEscapePressed: text === "" ? root.back() : text = ""
            }
            // → : log in
            Rectangle {
                visible: !passwordField.empty || Login.busy
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: 13
                color: goMouse.containsMouse ? "#59ffffff" : "#33ffffff"
                Text {
                    anchors.centerIn: parent
                    text: Login.busy ? "" : "" // spinner / arrow
                    font.family: root.fontSymbols
                    font.pixelSize: 12
                    color: "white"
                    RotationAnimator on rotation {
                        running: Login.busy
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }
                MouseArea {
                    id: goMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.submit()
                }
            }

            // wrong password: the field shakes, like on a Mac
            SequentialAnimation {
                id: shake
                loops: 1
                NumberAnimation { target: passwordField; property: "anchors.horizontalCenterOffset"; to: -14; duration: 50 }
                NumberAnimation { target: passwordField; property: "anchors.horizontalCenterOffset"; to: 14; duration: 80 }
                NumberAnimation { target: passwordField; property: "anchors.horizontalCenterOffset"; to: -10; duration: 80 }
                NumberAnimation { target: passwordField; property: "anchors.horizontalCenterOffset"; to: 6; duration: 70 }
                NumberAnimation { target: passwordField; property: "anchors.horizontalCenterOffset"; to: 0; duration: 60 }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 18
            text: Login.error
            font.family: root.fontSans
            font.pixelSize: 13
            color: "#ffd6d6"
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Login.other ? "Zurück" : "Anderer Benutzer …"
            font.family: root.fontSans
            font.pixelSize: 13
            color: otherMouse.containsMouse ? "white" : "#b3ffffff"
            MouseArea {
                id: otherMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: Login.other ? root.back() : root.chooseOther()
            }
        }
    }

    // sleep, restart, shut down
    Row {
        id: powerRow
        visible: root.main
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48
        spacing: 44
        Repeater {
            model: [
                { glyph: "", text: "Ruhezustand", action: "suspend" },
                { glyph: "", text: "Neustart", action: "reboot" },
                { glyph: "", text: "Ausschalten", action: "poweroff" }
            ]
            Column {
                required property var modelData
                spacing: 8
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44
                    height: 44
                    radius: 22
                    color: powerMouse.containsMouse ? "#4dffffff" : "#26ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        font.family: root.fontSymbols
                        font.pixelSize: 18
                        color: "white"
                    }
                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Login.power(modelData.action)
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.text
                    font.family: root.fontSans
                    font.pixelSize: 12
                    color: "#d9ffffff"
                }
            }
        }
    }

    function submit() {
        if (Login.busy || passwordInput.text === "")
            return;
        if (Login.other && Login.otherName.trim() === "")
            return nameInput.forceActiveFocus();
        Login.login(passwordInput.text);
    }
    function chooseOther() {
        Login.error = "";
        Login.other = true;
        passwordInput.text = "";
        nameInput.forceActiveFocus();
    }
    function back() {
        Login.error = "";
        Login.other = false;
        nameInput.text = "";
        passwordInput.text = "";
        passwordInput.forceActiveFocus();
    }

    Connections {
        target: Login
        function onFailuresChanged() {
            passwordInput.text = "";
            shake.restart();
            passwordInput.forceActiveFocus();
        }
    }

    // a rounded, frosted field with a grey hint while empty
    component Field: Rectangle {
        property string placeholder: ""
        property bool empty: true
        width: 260
        height: 36
        radius: 18
        color: "#33ffffff"
        border.color: "#40ffffff"
        Text {
            visible: parent.empty
            anchors.verticalCenter: parent.verticalCenter
            x: 14
            text: parent.placeholder
            font.family: root.fontSans
            font.pixelSize: 14
            color: "#b3ffffff"
        }
    }
}
