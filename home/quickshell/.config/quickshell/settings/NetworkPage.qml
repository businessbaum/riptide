import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs

Page {
    id: page
    title: "WLAN & Netzwerk"

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var networks: (wifi?.networks.values ?? []).slice().sort((a, b) => b.signalStrength - a.signalStrength)
    property string asking: "" // network waiting for its password

    // Search for networks only while this page is open
    Component.onCompleted: if (wifi) wifi.scannerEnabled = true
    Component.onDestruction: if (wifi) wifi.scannerEnabled = false

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
            model: Networking.wifiEnabled ? page.networks : []
            SettingRow {
                id: net
                required property var modelData
                readonly property bool open: modelData.security === WifiSecurityType.Open
                title: modelData.name
                subtitle: `Signal ${Math.round(modelData.signalStrength * 100)} %` + (net.open ? "" : " · geschützt")
                         + (modelData.known ? " · bekannt" : "")

                Item {
                    implicitWidth: page.asking === modelData.name ? 250 : button.implicitWidth
                    implicitHeight: 28

                    DialogButton {
                        id: button
                        visible: page.asking !== net.modelData.name
                        implicitWidth: 100
                        width: implicitWidth
                        text: net.modelData.connected ? "Trennen" : net.modelData.stateChanging ? "…" : "Verbinden"
                        onClicked: {
                            if (net.modelData.connected)
                                net.modelData.disconnect();
                            else if (net.modelData.known || net.open)
                                net.modelData.connect();
                            else
                                page.asking = net.modelData.name;
                        }
                    }

                    // Password for a new network
                    Rectangle {
                        visible: page.asking === net.modelData.name
                        anchors.fill: parent
                        radius: 6
                        color: Config.tile
                        border.color: Config.accent
                        TextInput {
                            id: psk
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "●"
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.text
                            clip: true
                            focus: visible
                            Keys.onReturnPressed: {
                                net.modelData.connectWithPsk(text);
                                text = "";
                                page.asking = "";
                            }
                            Keys.onEscapePressed: page.asking = ""
                            Text {
                                visible: psk.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Passwort, dann Enter"
                                font: psk.font
                                color: Config.textSecondary
                            }
                        }
                    }
                }
            }
        }
    }
}
