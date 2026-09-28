import QtQuick
import Quickshell

// riptide's login window, like on a Mac – one design wherever you log in:
//   the lock screen of the session (LockScreen.qml): at boot the session starts locked and
//     this is where you log in; unlocking leads straight into the desktop behind it
//   greetd's login screen (system/files/usr/local/share/riptide/greeter), for someone else
//     or when the session did not start – setup-os.sh installs this very file there
// It shows the backdrop (the wallpaper), date and time; on the main screen the person, the
// password field, "Anderer Benutzer …" and sleep / restart / shut down. What a password
// does is up to the one showing it (signals). ⌃⌥F2 is the emergency way out.
Item {
    id: root

    property bool main: true
    property Component backdrop: gradient      // what lies behind (the lock screen: your wallpaper)
    property string displayName: ""
    property bool busy: false
    property string error: ""
    property int failures: 0                   // the password field shakes when it changes
    property bool offerOther: true             // "Anderer Benutzer …"
    property bool typeOther: true              // … typed here (greeter) or elsewhere (switchUser)
    property bool offerPower: true             // sleep, restart, shut down
    property bool leaving: false               // logged in: the form fades, the backdrop stays
    property bool other: false
    property bool errorHidden: false           // (going back or on: the old message goes)
    // coming in (LockScreen.qml animates them): 0 → 1 brings the clock down from above and
    // then the person and the field up from below; the backdrop may zoom
    property real intro: 1
    property real backdropScale: 1
    readonly property real clockIn: Math.max(0, Math.min(1, intro * 1.6))
    readonly property real formIn: Math.max(0, Math.min(1, (intro - 0.35) / 0.65))
    // where the ripple of unlocking starts: the person on the main screen, else the middle
    function rippleOrigin() {
        return main ? avatar.mapToItem(root, avatar.width / 2, avatar.height / 2) : Qt.point(width / 2, height / 2);
    }
    onErrorChanged: errorHidden = false
    readonly property string fontSans: "Inter"
    readonly property string fontSymbols: "Symbols Nerd Font"

    signal submit(string name, string password) // name: "" = the person shown
    signal switchUser
    signal power(string action)
    signal emergency

    function focusField() {
        if (other && nameInput.text === "")
            nameInput.forceActiveFocus();
        else
            passwordInput.forceActiveFocus();
    }
    function clear() {
        passwordInput.text = "";
        focusField();
    }

    onFailuresChanged: {
        passwordInput.text = "";
        shake.restart();
        passwordInput.forceActiveFocus();
    }

    // ⌃⌥F2 (keys the fields do not use come up here): out of this, to the text login
    Keys.onPressed: event => {
        if (event.key === Qt.Key_F2 && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.AltModifier)) {
            event.accepted = true;
            root.emergency();
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.backdrop
        scale: root.backdropScale
    }
    Component {
        id: gradient
        Rectangle {
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1b2a4a" }
                GradientStop { position: 0.55; color: "#3b2f63" }
                GradientStop { position: 1.0; color: "#5c2a4f" }
            }
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // everything but the backdrop: fades out when logged in
    Item {
        anchors.fill: parent
        opacity: root.leaving ? 0 : 1
        Behavior on opacity {
            NumberAnimation { duration: 280; easing.type: Easing.InOutQuad }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.1
            spacing: 0
            opacity: root.clockIn
            transform: Translate { y: (1 - root.clockIn) * -40 }
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
            opacity: root.formIn
            transform: Translate { y: (1 - root.formIn) * 44 }

            Rectangle {
                id: avatar
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
                    visible: !root.other
                    text: root.displayName.charAt(0).toUpperCase()
                    font.family: root.fontSans
                    font.pixelSize: 42
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.other
                    text: "" // person
                    font.family: root.fontSymbols
                    font.pixelSize: 40
                    color: "white"
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.other ? "Anderer Benutzer" : root.displayName
                font.family: root.fontSans
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: "white"
            }

            // "Anderer Benutzer": the name first
            Field {
                visible: root.other
                anchors.horizontalCenter: parent.horizontalCenter
                placeholder: "Name"
                empty: nameInput.text === ""
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
                    enabled: !root.busy
                    onAccepted: passwordInput.forceActiveFocus()
                    Keys.onEscapePressed: root.back()
                }
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
                    enabled: !root.busy
                    focus: true
                    onAccepted: root.send()
                    Keys.onEscapePressed: text === "" ? root.back() : text = ""
                }
                // → : log in
                Rectangle {
                    visible: !passwordField.empty || root.busy
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 13
                    color: goMouse.containsMouse ? "#59ffffff" : "#33ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: root.busy ? "" : "" // spinner / arrow
                        font.family: root.fontSymbols
                        font.pixelSize: 12
                        color: "white"
                        RotationAnimator on rotation {
                            running: root.busy
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
                        onClicked: root.send()
                    }
                }

                // wrong password: the field shakes, like on a Mac
                SequentialAnimation {
                    id: shake
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
                text: root.errorHidden ? "" : root.error
                font.family: root.fontSans
                font.pixelSize: 13
                color: "#ffd6d6"
            }

            Text {
                visible: root.offerOther
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.other ? "Zurück" : "Anderer Benutzer …"
                font.family: root.fontSans
                font.pixelSize: 13
                color: otherMouse.containsMouse ? "white" : "#b3ffffff"
                MouseArea {
                    id: otherMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    onClicked: root.other ? root.back() : root.chooseOther()
                }
            }
        }

        // sleep, restart, shut down
        Row {
            id: powerRow
            visible: root.main && root.offerPower
            opacity: root.formIn
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
                            onClicked: root.power(modelData.action)
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
    }

    function send() {
        if (busy || passwordInput.text === "")
            return;
        if (other && nameInput.text.trim() === "")
            return nameInput.forceActiveFocus();
        submit(other ? nameInput.text.trim() : "", passwordInput.text);
    }
    function chooseOther() {
        errorHidden = true;
        if (!typeOther)
            return switchUser();
        other = true;
        passwordInput.text = "";
        nameInput.forceActiveFocus();
    }
    function back() {
        errorHidden = true;
        other = false;
        nameInput.text = "";
        passwordInput.text = "";
        passwordInput.forceActiveFocus();
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
