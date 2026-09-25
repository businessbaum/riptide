import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell.Io
import qs

Page {
    id: page
    title: "Bluetooth"

    // The adapter that is not switched off by rfkill (the TP-Link stick; the built-in
    // MediaTek one is blocked) – BlueZ' "default" may point at the blocked one
    readonly property var adapter: Bluetooth.adapters.values.find(a => a.state !== BluetoothAdapterState.Blocked) ?? Bluetooth.defaultAdapter

    // The real name; many devices nearby only send their address – those stay hidden
    // (like on a Mac) unless they are paired.
    function nameOf(d) {
        const isAddress = n => /^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(n ?? "");
        if (d.deviceName && !isAddress(d.deviceName))
            return d.deviceName;
        if (d.name && !isAddress(d.name))
            return d.name;
        return "";
    }
    readonly property var allDevices: adapter?.devices.values ?? []
    readonly property var devices: allDevices.filter(d => d.paired || nameOf(d) !== "")
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || nameOf(a).localeCompare(nameOf(b)))
    readonly property int hidden: allDevices.length - devices.length
    readonly property var paired: devices.filter(d => d.paired)
    readonly property var nearby: devices.filter(d => !d.paired)


    // Pairing needs an "agent" that confirms it; bluetoothctl brings one for the time of
    // the command ("NoInputNoOutput": no code to type, as with AirPods). Then trust + connect.
    property string pairing: ""        // address being paired
    property string pairResult: ""
    Process {
        id: pairProcess
        property string name: ""
        stdout: StdioCollector { id: pairOut }
        stderr: StdioCollector { id: pairErr }
        onExited: code => {
            const out = pairOut.text + "\n" + pairErr.text;
            let why = "";
            if (/Host is down|Page Timeout|ConnectionAttemptFailed|not available/i.test(out))
                why = "Das Gerät antwortet nicht. Ist es im Kopplungsmodus? Bei AirPods: Deckel auf, AirPods drin, Knopf hinten halten, bis das Licht weiß blinkt – dann sofort „Koppeln“.";
            else if (/AuthenticationFailed|AuthenticationCanceled|AuthenticationRejected/i.test(out))
                why = "Das Gerät hat die Kopplung abgelehnt. Bitte in den Kopplungsmodus bringen und erneut versuchen.";
            else if (/Timeout|timed out/i.test(out))
                why = "Zeitüberschreitung – bitte erneut versuchen, das Gerät dabei im Kopplungsmodus lassen.";
            else
                why = (out.match(/Failed to [^\n]*/) ?? [""])[0];
            page.pairResult = code === 0 ? `„${name}“ ist gekoppelt und verbunden.`
                                         : `Koppeln mit „${name}“ hat nicht geklappt. ${why}`;
            page.pairing = "";
        }
    }
    // Safety net: never stay at "Wird gekoppelt …"
    Timer {
        id: pairWatchdog
        interval: 60000
        onTriggered: if (pairProcess.running) pairProcess.signal(15)
    }
    function pair(d) {
        // Without "pairable" BlueZ only makes a temporary pairing (no stored key): the device
        // is forgotten as soon as it disconnects. Also set permanently (setup-bluetooth.sh).
        if (adapter)
            adapter.pairable = true;
        pairing = d.address;
        pairResult = "";
        pairProcess.name = nameOf(d);
        pairProcess.command = ["sh", "-c", "bluetoothctl pairable on >/dev/null; bluetoothctl --agent NoInputNoOutput --timeout 30 pair \"$1\" && bluetoothctl trust \"$1\" && bluetoothctl --timeout 15 connect \"$1\"", "sh", d.address];
        pairProcess.running = true;
        pairWatchdog.restart();
    }

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
        visible: page.pairResult !== ""
        Layout.fillWidth: true
        text: page.pairResult
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
        title: page.nameOf(modelData) || "Unbekanntes Gerät"
        subtitle: (page.pairing === modelData.address ? "Wird gekoppelt …"
                  : modelData.connected ? "Verbunden" : modelData.paired ? "Nicht verbunden" : "Neues Gerät")
                + (modelData.batteryAvailable ? ` · Batterie ${Math.round(modelData.battery * 100)} %` : "")

        RowLayout {
            spacing: 6
            DialogButton {
                Layout.preferredWidth: 96
                text: page.pairing === dev.modelData.address || dev.modelData.pairing ? "…"
                    : dev.modelData.connected ? "Trennen" : dev.modelData.paired ? "Verbinden" : "Koppeln"
                onClicked: {
                    const d = dev.modelData;
                    if (page.pairing !== "")
                        return;
                    if (d.connected) d.disconnect();
                    else if (d.paired) d.connect();
                    else page.pair(d);
                }
            }
            DialogButton {
                visible: dev.modelData.paired
                Layout.preferredWidth: 80
                text: "Entfernen"
                onClicked: {
                    const device = dev.modelData; // the list may rebuild while the dialog is open
                    Confirm.ask(`„${page.nameOf(device)}“ entfernen?`,
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
            visible: page.paired.length === 0
            Layout.margins: 12
            text: "Noch keine – oben „Neue Geräte suchen“ einschalten."
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
        Repeater {
            model: page.paired
            DeviceRow {}
        }
    }

    // New devices: only while searching
    Group {
        title: "Geräte in der Nähe"
        description: page.hidden > 0 ? `${page.hidden} weitere Geräte senden keinen Namen und sind ausgeblendet.` : ""
        visible: page.adapter?.discovering ?? false
        Text {
            visible: page.nearby.length === 0
            Layout.margins: 12
            text: "Suche läuft … Bei AirPods: Deckel auf, Knopf hinten halten, bis das Licht weiß blinkt."
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            font.family: Config.fontSans
            font.pixelSize: 12
            color: Config.textSecondary
        }
        Repeater {
            model: page.nearby
            DeviceRow {}
        }
    }
}
