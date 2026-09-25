import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Like on a Mac: "AirPods Pro · Verbunden" at the top right when a Bluetooth device
// connects, with its battery level if the device reports one (shown by Banners.qml).
Scope {
    id: root

    // Devices that are already connected when the shell starts are not announced
    property bool ready: false
    Timer {
        running: true
        interval: 3000
        onTriggered: root.ready = true
    }

    // Nerd Font symbol for BlueZ's device type
    function glyph(dev) {
        const icon = dev.icon ?? "";
        if (icon === "audio-headphones" || icon === "audio-headset")
            return /airpods|buds/i.test(dev.name) ? "\u{f184f}" : icon === "audio-headset" ? "\u{f02ce}" : "\u{f02cb}";
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

    function battery(dev) {
        return dev.batteryAvailable ? dev.battery : -1;
    }

    Variants {
        model: Bluetooth.devices.values

        Connections {
            required property var modelData
            readonly property string key: "bluetooth:" + modelData.address
            target: modelData

            function onConnectedChanged() {
                if (modelData.connected && root.ready)
                    Banners.show({
                        key: key,
                        glyph: root.glyph(modelData),
                        title: modelData.name,
                        subtitle: "Verbunden",
                        value: root.battery(modelData)
                    });
            }
            // The battery level often arrives a moment after connecting
            function onBatteryChanged() {
                Banners.update(key, { value: root.battery(modelData) });
            }
            function onBatteryAvailableChanged() {
                Banners.update(key, { value: root.battery(modelData) });
            }
        }
    }
}
