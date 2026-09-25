import QtQuick

// The frame of everything that pops up at the top right (Banners.qml), also used for the
// cards in the notification centre: glass surface, slides in, hides itself after
// `timeout` (hovering pauses), fades out; × in the top left corner while hovering.
// The formats build on it: StatusBanner.qml, NotificationCard.qml.
Glass {
    id: root

    property int timeout: 0      // ms until it hides by itself, 0 = stays
    property bool closable: true // × in the top left corner while hovering
    property bool animated: true // slide in, fade out (off inside lists)
    property real stamp: 0       // a new value shows it again and restarts the timer
    readonly property bool hovered: mouse.containsMouse || closeMouse.containsMouse
    default property alias items: slot.data

    signal clicked
    signal closeClicked
    signal gone // hidden (timer, click or leave()): remove it now

    function leave() {
        if (animated)
            leaving = true;
        else
            gone();
    }

    property bool entered: !animated
    property bool leaving: false
    Component.onCompleted: entered = true
    onStampChanged: {
        leaving = false;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: Math.max(1, root.timeout)
        running: root.timeout > 0 && root.entered && !root.leaving && !root.hovered
        onTriggered: root.leave()
    }

    opacity: entered && !leaving ? 1 : 0
    Behavior on opacity {
        enabled: root.animated
        NumberAnimation { duration: 200 }
    }
    onOpacityChanged: {
        if (leaving && opacity === 0)
            gone();
    }
    transform: Translate {
        x: root.entered && !root.leaving ? 0 : 24
        Behavior on x {
            enabled: root.animated
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
    }

    Item {
        id: slot
        anchors.fill: parent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }

    // × in the top left corner while hovering, like on a Mac
    Glass {
        visible: root.closable && root.hovered
        x: -6
        y: -6
        width: 20
        height: 20
        radius: 10

        Text {
            anchors.centerIn: parent
            text: ""
            font.family: Config.fontSymbols
            font.pixelSize: 10
            color: Config.text
        }
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.closeClicked()
        }
    }
}
