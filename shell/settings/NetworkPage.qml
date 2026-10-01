import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs

Page {
    id: page
    title: "WLAN & Netzwerk"

    readonly property var wifi: Wifi.device

    // Search for networks only while this page is open (Wifi.qml, shared with the control centre)
    Component.onCompleted: Wifi.watch(true)
    Component.onDestruction: Wifi.watch(false)

    function stateText(d) {
        return d.state === ConnectionState.Connected ? "Verbunden"
             : d.state === ConnectionState.Connecting ? "Verbinde …"
             : "Nicht verbunden";
    }

    Group {
        title: "Verbindungen"
        Repeater {
            model: Networking.devices.values
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData.type === DeviceType.Wifi ? "WLAN" : "Ethernet"
                subtitle: modelData.name
                Text {
                    text: page.stateText(modelData)
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    color: modelData.connected ? "#32d74b" : Config.textSecondary
                }
            }
        }
    }

    Group {
        title: "WLAN"
        visible: page.wifi !== null
        SettingRow {
            first: true
            title: "WLAN"
            subtitle: Networking.wifiHardwareEnabled ? "" : "Per Schalter am Gerät ausgeschaltet"
            Toggle {
                enabled: Networking.wifiHardwareEnabled
                checked: Networking.wifiEnabled
                onToggled: on => Networking.wifiEnabled = on
            }
        }
        Repeater {
            model: Networking.wifiEnabled ? Wifi.networks : []
            SettingRow {
                id: net
                required property var modelData
                glyph: Wifi.glyph(modelData)
                glyphColour: modelData.connected ? Config.accent : "#8e8e93"
                title: modelData.name
                subtitle: (modelData.connected ? "Verbunden" : modelData.stateChanging ? "Verbinde …" : `Signal ${Math.round(modelData.signalStrength * 100)} %`)
                         + (Wifi.isOpen(modelData) ? " · ungeschützt" : "") + (modelData.known && !modelData.connected ? " · bekannt" : "")
                Row {
                    spacing: 8
                    DialogButton {
                        visible: net.modelData.known && !net.modelData.connected
                        implicitWidth: 90
                        width: implicitWidth
                        text: "Ignorieren"
                        onClicked: {
                            const n = net.modelData;
                            Confirm.ask(`„${n.name}“ ignorieren?`, "Dein Computer verbindet sich nicht mehr von selbst damit und vergisst das Passwort.",
                                "Ignorieren", () => n.forget());
                        }
                    }
                    DialogButton {
                        implicitWidth: 100
                        width: implicitWidth
                        text: net.modelData.connected ? "Trennen" : net.modelData.stateChanging ? "…" : "Verbinden"
                        onClicked: net.modelData.connected ? net.modelData.disconnect() : Wifi.join(net.modelData)
                    }
                }
            }
        }
        SettingRow {
            visible: Networking.wifiEnabled && Wifi.networks.length === 0
            title: Wifi.searchedLong ? "Keine Netzwerke gefunden" : "Suche nach Netzwerken …"
            subtitle: Wifi.searchedLong ? "Ist die WLAN-Antenne hinten am Computer angeschraubt? Ohne sie findet die Karte nichts." : ""
        }
    }

    // ---------------------------------------------------------------- VPN (NetworkManager)

    property var vpns: [] // [{ name, uuid, active }]
    property string vpnError: ""
    Timer {
        running: true
        repeat: true
        interval: 3000
        onTriggered: if (!vpnReader.running) vpnReader.running = true
    }
    // "name:type:active:uuid" (nmcli escapes ":" in names as "\:")
    Process {
        id: vpnReader
        running: true
        command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE,UUID", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: page.vpns = text.split("\n").map(l => l.replace(/\\:/g, "\u0001").split(":").map(f => f.replace(/\u0001/g, ":")))
                .filter(f => f.length === 4 && (f[1] === "vpn" || f[1] === "wireguard"))
                .map(f => ({ name: f[0], active: f[2] === "yes", uuid: f[3] }))
        }
    }
    Process {
        id: vpnChange
        stderr: StdioCollector { id: vpnErr }
        onExited: code => {
            page.vpnError = code === 0 ? "" : (vpnErr.text.trim().split("\n").pop() || "Nicht geändert");
            vpnReader.running = true;
        }
    }
    function nm(args) {
        vpnError = "";
        vpnChange.command = ["nmcli"].concat(args);
        vpnChange.running = true;
    }

    Group {
        title: "VPN"
        description: page.vpnError !== "" ? page.vpnError
            : "Eine VPN-Verbindung leitet deinen Internetverkehr verschlüsselt über einen anderen Server."
        Repeater {
            model: page.vpns
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                glyph: "\u{f0582}"
                glyphColour: modelData.active ? "#30d158" : "#8e8e93"
                title: modelData.name
                subtitle: modelData.active ? "Verbunden" : "Nicht verbunden"
                Row {
                    spacing: 8
                    DialogButton {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 90
                        width: implicitWidth
                        text: "Entfernen …"
                        onClicked: {
                            const v = modelData;
                            Confirm.ask(`„${v.name}“ entfernen?`, "Die Verbindung und ihre Schlüssel werden gelöscht.", "Entfernen",
                                () => page.nm(["connection", "delete", "uuid", v.uuid]));
                        }
                    }
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: modelData.active
                        onToggled: on => page.nm(["connection", on ? "up" : "down", "uuid", modelData.uuid])
                    }
                }
            }
        }
        SettingRow {
            first: page.vpns.length === 0
            title: "WireGuard-Konfiguration importieren"
            subtitle: "Die .conf-Datei deines VPN-Anbieters, z. B. ~/Downloads/vpn.conf"
            Row {
                spacing: 8
                Field {
                    id: vpnFile
                    implicitWidth: 200
                    placeholder: "~/Downloads/vpn.conf"
                    onAccepted: vpnImport.clicked()
                }
                DialogButton {
                    id: vpnImport
                    implicitWidth: 100
                    width: implicitWidth
                    text: "Importieren"
                    onClicked: {
                        const path = vpnFile.text.trim().replace(/^~(?=\/)/, Quickshell.env("HOME"));
                        if (path === "")
                            return;
                        if (/\.ovpn$/i.test(path)) {
                            page.vpnError = "OpenVPN braucht das Paket networkmanager-openvpn (App Store).";
                            return;
                        }
                        page.nm(["connection", "import", "type", "wireguard", "file", path]);
                        vpnFile.text = "";
                    }
                }
            }
        }
    }
}
