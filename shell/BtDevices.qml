pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// Bluetooth in one place (os-plan "one service per system area"): the adapter in use, what
// a device is called, the known and the nearby devices, connecting, disconnecting and
// pairing. The control centre and System Settings → Bluetooth only show it. (System
// Settings is an instance of its own with its own copy; both see the same BlueZ.)
Singleton {
    id: root

    // The adapter that is not switched off by rfkill (the TP-Link stick; the built-in
    // MediaTek one is blocked) – BlueZ' "default" may point at the blocked one
    readonly property var adapter: Bluetooth.adapters.values.find(a => a.state !== BluetoothAdapterState.Blocked) ?? Bluetooth.defaultAdapter

    // The real name; many devices nearby only send their address – "" for those (they
    // stay hidden, like on a Mac, unless they are paired)
    function nameOf(d) {
        const isAddress = n => /^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$/i.test(n ?? "");
        if (d.deviceName && !isAddress(d.deviceName))
            return d.deviceName;
        if (d.name && !isAddress(d.name))
            return d.name;
        return "";
    }
    readonly property var all: adapter?.devices.values ?? []
    readonly property var devices: all.filter(d => d.paired || nameOf(d) !== "")
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || nameOf(a).localeCompare(nameOf(b)))
    readonly property int hidden: all.length - devices.length // nearby, but without a name
    readonly property var known: devices.filter(d => d.paired)  // paired once: BlueZ keeps them
    readonly property var nearby: devices.filter(d => !d.paired)

    function busy(d) {
        return pairing === d.address || d.pairing
            || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting;
    }

    // what a click on a device does: disconnect, connect, or pair a new one
    function toggle(d) {
        if (pairing !== "" || busy(d))
            return;
        if (d.connected)
            d.disconnect();
        else if (d.paired)
            d.connect();
        else
            pair(d);
    }

    // Pairing needs an "agent" that confirms it; bluetoothctl brings one for the time of
    // the command ("NoInputNoOutput": no code to type, as with AirPods). Then trust + connect.
    property string pairing: ""    // address being paired
    property string pairResult: "" // how the last pairing went, in words
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
            root.pairResult = code === 0 ? `„${name}“ ist gekoppelt und verbunden.`
                                         : `Koppeln mit „${name}“ hat nicht geklappt. ${why}`;
            root.pairing = "";
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

    // BlueZ' icon name ("audio-headphones", "input-mouse" …) → a symbol (Symbols Nerd Font);
    // AirPods and other earbuds get their own
    function glyph(d) {
        const icon = d?.icon ?? "";
        if (icon === "audio-headphones" || icon === "audio-headset")
            return /airpods|buds/i.test(nameOf(d)) ? "\u{f184f}" : icon === "audio-headset" ? "\u{f02ce}" : "\u{f02cb}";
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
}
