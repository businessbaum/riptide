//@ pragma AppId org.riptide.SystemSettings
//@ pragma IconTheme Adwaita
//@ pragma UseQApplication

// "Systemeinstellungen": a separate Quickshell instance (own app id → own dock icon)
// that shares Config, Slider, Toggle … with the shell. Every change is written to
// settings.json at once, and the desktop follows immediately.
//   Start:  scripts/system-settings.sh   (org.riptide.SystemSettings.desktop)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.settings

FloatingWindow {
    id: window

    property string page: "appearance"

    // key, title, icon (Symbols Nerd Font), tile colour; null = separator like on a Mac
    readonly property var pages: [
        { key: "network", title: "WLAN & Netzwerk", icon: "", colour: "#0a84ff" },
        { key: "bluetooth", title: "Bluetooth", icon: "", colour: "#0a84ff" },
        { key: "sound", title: "Ton", icon: "", colour: "#ff375f" },
        null,
        { key: "general", title: "Allgemein", icon: "", colour: "#8e8e93" },
        { key: "appearance", title: "Erscheinungsbild", icon: "", colour: "#1c1c1e" },
        { key: "desktop", title: "Schreibtisch & Dock", icon: "", colour: "#1c1c1e" },
        { key: "displays", title: "Bildschirme", icon: "", colour: "#0a84ff" },
        null,
        { key: "mouse", title: "Maus", icon: "", colour: "#8e8e93" },
        { key: "keyboard", title: "Tastatur", icon: "", colour: "#8e8e93" }
    ]

    // Open a page from outside:  qs ipc -p ~/.config/quickshell/settings.qml call settings page sound
    IpcHandler {
        target: "settings"
        function page(key: string): void {
            if (window.pages.some(p => p?.key === key))
                window.page = key;
        }
    }

    title: "Systemeinstellungen"
    implicitWidth: 860
    implicitHeight: 600
    minimumSize: Qt.size(720, 420)
    color: Config.windowBg

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            color: Config.sidebarBg

            Column {
                x: 10
                y: 14
                width: parent.width - 20
                spacing: 2

                Repeater {
                    model: window.pages

                    Item {
                        id: entry
                        required property var modelData
                        width: parent.width
                        height: modelData ? 30 : 14

                        Rectangle {
                            visible: !entry.modelData
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            width: parent.width - 16
                            height: 1
                            color: Config.border
                        }

                        Rectangle {
                            visible: !!entry.modelData
                            anchors.fill: parent
                            radius: 6
                            color: entry.modelData?.key === window.page ? Config.accent
                                 : mouse.containsMouse ? Config.hover : "transparent"

                            Rectangle {
                                id: icon
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                radius: 5
                                color: entry.modelData?.colour ?? "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: entry.modelData?.icon ?? ""
                                    font.family: Config.fontSymbols
                                    font.pixelSize: 11
                                    color: "white"
                                }
                            }
                            Text {
                                anchors.left: icon.right
                                anchors.leftMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                text: entry.modelData?.title ?? ""
                                font.family: Config.fontSans
                                font.pixelSize: 13
                                color: entry.modelData?.key === window.page ? "white" : Config.text
                            }
                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: window.page = entry.modelData.key
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Config.border
        }

        // The page; created fresh on every switch (scanners etc. run only while visible)
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            source: {
                const files = {
                    network: "settings/NetworkPage.qml", bluetooth: "settings/BluetoothPage.qml",
                    sound: "settings/SoundPage.qml", general: "settings/GeneralPage.qml",
                    appearance: "settings/AppearancePage.qml", desktop: "settings/DesktopPage.qml",
                    displays: "settings/DisplaysPage.qml", mouse: "settings/MousePage.qml",
                    keyboard: "settings/KeyboardPage.qml"
                };
                return Quickshell.shellPath(files[window.page]);
            }
            onLoaded: if (item.hasOwnProperty("window")) item.window = window
        }
    }
}
