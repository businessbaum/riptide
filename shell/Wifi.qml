pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// Wi-Fi for the control centre and System Settings → WLAN & Netzwerk: the networks around,
// joining one – a protected new one asks for its password in the system dialog (Confirm), a
// wrong password asks again – and what went wrong, as a notification.
// Searching costs power: it runs only while someone looks (watch(true) … watch(false)).
Singleton {
    id: root

    readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var current: device?.networks.values.find(n => n.connected) ?? null
    // one row per name, strongest first (hidden networks without a name are left out)
    readonly property var networks: {
        const byName = {};
        for (const n of device?.networks.values ?? []) {
            if (n.name === "")
                continue;
            const seen = byName[n.name];
            if (!seen || n.connected || (!seen.connected && n.signalStrength > seen.signalStrength))
                byName[n.name] = n;
        }
        const list = [];
        for (const name in byName)
            list.push(byName[name]);
        return list.sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength));
    }

    // Searching: on while at least one view is open. `searchedLong` tells "still looking" from
    // "nothing there" (the card needs a few seconds for the first results)
    property int watchers: 0
    property bool searchedLong: false
    function watch(on) {
        watchers = Math.max(0, watchers + (on ? 1 : -1));
    }
    readonly property bool searching: watchers > 0 && device !== null && Networking.wifiEnabled
    onSearchingChanged: {
        if (device)
            device.scannerEnabled = searching;
        searchedLong = false;
        if (searching)
            searchTimer.restart();
    }
    onDeviceChanged: if (device) device.scannerEnabled = searching
    Timer {
        id: searchTimer
        interval: 12000
        onTriggered: root.searchedLong = true
    }

    function isOpen(n) {
        return n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe;
    }
    // 0–4 bars, as MDI glyphs (wifi_strength_1 … 4, with a lock when protected)
    function glyph(n) {
        const bars = Math.max(1, Math.ceil((n?.signalStrength ?? 0) * 4));
        return String.fromCodePoint(0xf091f + 3 * (bars - 1) + (n && !isOpen(n) ? 2 : 0));
    }

    // the network we asked to join: a failure of this one asks for the password again
    property var joining: null

    function join(n) {
        if (!n || n.connected)
            return;
        if (n.known || isOpen(n)) {
            joining = n;
            n.connect();
        } else {
            askPassword(n, false);
        }
    }

    function askPassword(n, again) {
        Confirm.request({
            title: again ? `Das Passwort für „${n.name}“ war nicht richtig.` : `„${n.name}“ ist durch ein Passwort geschützt.`,
            text: again ? "Gib es noch einmal ein." : "Gib das Passwort des WLANs ein.",
            button: "Verbinden",
            input: { password: true, placeholder: "Passwort" },
            action: (checked, text) => {
                if (text === "")
                    return;
                joining = n;
                n.connectWithPsk(text);
            }
        });
    }

    Instantiator {
        model: root.device?.networks ?? null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) {
                const n = modelData;
                const ours = root.joining === n;
                if (ours)
                    root.joining = null;
                const password = reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiClientFailed
                    || reason === ConnectionFailReason.WifiAuthTimeout;
                if (ours && password && !root.isOpen(n))
                    root.askPassword(n, true);
                else if (ours)
                    Notify.error("WLAN", reason === ConnectionFailReason.WifiNetworkLost
                        ? `„${n.name}“ ist nicht mehr erreichbar.`
                        : `Keine Verbindung mit „${n.name}“.`);
            }
            function onConnectedChanged() {
                if (modelData.connected && root.joining === modelData)
                    root.joining = null;
            }
        }
    }
}
