import QtQuick
import Quickshell
import Quickshell.Bluetooth

// "AirPods Pro · Verbunden": a small banner at the top right when a Bluetooth device
// connects, like on a Mac – with its battery level if the device reports one.
// Lives at the top of the notification banners (Notifications.qml).
Rectangle {
    id: root

    property var device: null
    property bool shown: false
    // Devices that are already connected when the shell starts are not announced
    property bool ready: false

    function announce(dev) {
        device = dev;
        shown = true;
        hideTimer.restart();
    }

    // Nerd Font symbol for BlueZ's device type
    function glyph(dev) {
        const icon = dev?.icon ?? "";
        const name = dev?.name ?? "";
        if (icon === "audio-headphones" || icon === "audio-headset")
            return /airpods|buds/i.test(name) ? "\u{f184f}" : icon === "audio-headset" ? "\u{f02ce}" : "\u{f02cb}";
        return {
            "audio-card": "\u{f04c3}",
            "input-mouse": "\u{f037d}",
            "input-keyboard": "\u{f030c}",
            "input-gaming": "\u{f0297}",
            "input-tablet": "\u{f04f6}",
            "phone": "\u{f011c}",
            "computer": "\u{f0322}",
            "printer": "\u{f042a}"
        }[icon] ?? "\u{f00af}";
    }

    Variants {
        model: Bluetooth.devices.values

        Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() {
                if (modelData.connected && root.ready)
                    root.announce(modelData);
            }
        }
    }
    Timer {
        running: true
        interval: 3000
        onTriggered: root.ready = true
    }
    Timer {
        id: hideTimer
        interval: 4000
        running: root.shown && !mouse.containsMouse
        onTriggered: root.shown = false
    }

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 200 }
    }
    transform: Translate {
        x: root.shown ? 0 : 24
        Behavior on x {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }
    }

    implicitWidth: 300
    implicitHeight: 64
    radius: Config.radiusPanel
    color: Config.glassMenu
    border.color: Config.border

    Rectangle {
        id: badge
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        height: 40
        radius: 20
        color: Config.tile

        Text {
            anchors.centerIn: parent
            text: root.glyph(root.device)
            font.family: Config.fontSymbols
            font.pixelSize: 22
            color: Config.text
        }
    }

    Column {
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: battery.visible ? battery.left : parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: root.device?.name ?? ""
            elide: Text.ElideRight
            font.family: Config.fontSans
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Config.text
        }
        Text {
            text: "Verbunden"
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
    }

    ProgressRing {
        id: battery
        visible: root.device?.batteryAvailable ?? false
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        thickness: 3
        value: root.device?.battery ?? 0
        colour: value < 0.2 ? "#ff9f0a" : "#30d158"

        Text {
            anchors.centerIn: parent
            text: Math.round(battery.value * 100)
            font.family: Config.fontSans
            font.pixelSize: 10
            font.weight: Font.DemiBold
            color: Config.text
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.shown = false
    }
}
