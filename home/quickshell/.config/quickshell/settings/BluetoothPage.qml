import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs

Page {
    id: page
    title: "Bluetooth"

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: (adapter?.devices.values ?? []).slice()
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))

    Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false

    Group {
        SettingRow {
            first: true
            title: "Bluetooth"
            subtitle: page.adapter ? "" : "Kein Bluetooth-Adapter gefunden"
            Toggle {
                enabled: page.adapter !== null
                checked: page.adapter?.enabled ?? false
                onToggled: on => page.adapter.enabled = on
            }
        }
        SettingRow {
            visible: page.adapter?.enabled ?? false
            title: "Neue Geräte suchen"
            subtitle: page.adapter?.discovering ? "Suche läuft …" : ""
            Toggle {
                checked: page.adapter?.discovering ?? false
                onToggled: on => page.adapter.discovering = on
            }
        }
    }

    Group {
        title: "Geräte"
        visible: (page.adapter?.enabled ?? false)
        Text {
            visible: page.devices.length === 0
            Layout.margins: 12
            text: "Noch keine – „Neue Geräte suchen“ findet welche."
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
        Repeater {
            model: page.devices
            SettingRow {
                id: dev
                required property var modelData
                required property int index
                first: index === 0
                title: modelData.name || modelData.address
                subtitle: (modelData.connected ? "Verbunden" : modelData.paired ? "Gekoppelt" : "Nicht gekoppelt")
                        + (modelData.batteryAvailable ? ` · Batterie ${Math.round(modelData.battery * 100)} %` : "")

                RowLayout {
                    spacing: 6
                    DialogButton {
                        Layout.preferredWidth: 96
                        text: dev.modelData.pairing ? "…" : dev.modelData.connected ? "Trennen"
                            : dev.modelData.paired ? "Verbinden" : "Koppeln"
                        onClicked: {
                            const d = dev.modelData;
                            if (d.connected) d.disconnect();
                            else if (d.paired) d.connect();
                            else { d.trusted = true; d.pair(); }
                        }
                    }
                    DialogButton {
                        visible: dev.modelData.paired
                        Layout.preferredWidth: 80
                        text: "Entfernen"
                        onClicked: dev.modelData.forget()
                    }
                }
            }
        }
    }
}
