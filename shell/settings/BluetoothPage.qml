import QtQuick
import QtQuick.Layouts
import qs

Page {
    id: page
    title: "Bluetooth"

    // Everything Bluetooth lives in BtDevices.qml (shared with the control centre); this
    // page only shows it
    readonly property var adapter: BtDevices.adapter

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

    Text {
        visible: BtDevices.pairResult !== ""
        Layout.fillWidth: true
        text: BtDevices.pairResult
        wrapMode: Text.Wrap
        font.family: Config.fontSans
        font.pixelSize: 12
        color: Config.textSecondary
    }

    // One device row (used in both lists)
    component DeviceRow: SettingRow {
        id: dev
        required property var modelData
        required property int index
        first: index === 0
        title: BtDevices.nameOf(modelData) || "Unbekanntes Gerät"
        subtitle: (BtDevices.pairing === modelData.address ? "Wird gekoppelt …"
                  : modelData.connected ? "Verbunden" : modelData.paired ? "Nicht verbunden" : "Neues Gerät")
                + (modelData.batteryAvailable ? ` · Batterie ${Math.round(modelData.battery * 100)} %` : "")

        RowLayout {
            spacing: 6
            DialogButton {
                Layout.preferredWidth: 96
                text: BtDevices.busy(dev.modelData) ? "…"
                    : dev.modelData.connected ? "Trennen" : dev.modelData.paired ? "Verbinden" : "Koppeln"
                onClicked: BtDevices.toggle(dev.modelData)
            }
            DialogButton {
                visible: dev.modelData.paired
                Layout.preferredWidth: 80
                text: "Entfernen"
                onClicked: {
                    const device = dev.modelData; // the list may rebuild while the dialog is open
                    Confirm.ask(`„${BtDevices.nameOf(device)}“ entfernen?`,
                        "Danach muss es neu gekoppelt werden.", "Entfernen", () => device.forget());
                }
            }
        }
    }

    // Paired once → always listed here, no search needed (BlueZ keeps them)
    Group {
        title: "Meine Geräte"
        visible: page.adapter?.enabled ?? false
        Text {
            visible: BtDevices.known.length === 0
            Layout.margins: 12
            text: "Noch keine – oben „Neue Geräte suchen“ einschalten."
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
        Repeater {
            model: BtDevices.known
            DeviceRow {}
        }
    }

    // New devices: only while searching
    Group {
        title: "Geräte in der Nähe"
        description: BtDevices.hidden > 0 ? `${BtDevices.hidden} weitere Geräte senden keinen Namen und sind ausgeblendet.` : ""
        visible: page.adapter?.discovering ?? false
        Text {
            visible: BtDevices.nearby.length === 0
            Layout.margins: 12
            text: "Suche läuft … Bei AirPods: Deckel auf, Knopf hinten halten, bis das Licht weiß blinkt."
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
        Repeater {
            model: BtDevices.nearby
            DeviceRow {}
        }
    }
}
