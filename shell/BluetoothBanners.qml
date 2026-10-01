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
                        glyph: BtDevices.glyph(modelData),
                        title: BtDevices.nameOf(modelData) || modelData.name,
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
