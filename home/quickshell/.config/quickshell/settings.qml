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
    // Part of a page, e.g. "microphone" of "privacy/microphone" (pages with `selected`)
    property string subpage: ""

    // key, title, icon (Symbols Nerd Font; GlyphTile brings them to one size), tile colour;
    // null = separator like on a Mac
    readonly property var pages: [
        { key: "network", title: "WLAN & Netzwerk", icon: "", colour: "#0a84ff" },
        { key: "bluetooth", title: "Bluetooth", icon: "", colour: "#0a84ff" },
        { key: "sound", title: "Ton", icon: "", colour: "#ff375f" },
        { key: "notifications", title: "Mitteilungen", icon: "\uf0f3", colour: "#ff3b30" },
        { key: "privacy", title: "Datenschutz & Sicherheit", icon: "\u{f099d}", colour: "#0a84ff" },
        null,
        { key: "general", title: "Allgemein", icon: "", colour: "#8e8e93" },
        { key: "login", title: "Anmeldeobjekte", icon: "\u{f0342}", colour: "#8e8e93" },
        { key: "apps", title: "Apps", icon: "\u{f0570}", colour: "#0a84ff" },
        { key: "storage", title: "Speicher", icon: "\uf1c0", colour: "#8e8e93" },
        { key: "timemachine", title: "Time Machine", icon: "\u{f02da}", colour: "#30d158" },
        { key: "defaults", title: "Standard-Apps", icon: "\uf0c1", colour: "#30d158" },
        { key: "appearance", title: "Erscheinungsbild", icon: "", colour: "#1c1c1e" },
        { key: "accessibility", title: "Bedienungshilfen", icon: "\uf29a", colour: "#0a84ff" },
        { key: "desktop", title: "Schreibtisch & Dock", icon: "", colour: "#1c1c1e" },
        { key: "displays", title: "Bildschirme", icon: "", colour: "#0a84ff" },
        { key: "energy", title: "Energie", icon: "\u{f06a5}", colour: "#30d158" },
        null,
        { key: "mouse", title: "Maus", icon: "\u{f037d}", colour: "#8e8e93" },
        { key: "keyboard", title: "Tastatur", icon: "", colour: "#8e8e93" },
        { key: "printers", title: "Drucker & Scanner", icon: "\uf02f", colour: "#8e8e93" }
    ]

    // Open a page from outside:  qs ipc -p ~/.config/quickshell/settings.qml call settings page sound
    // or a part of it:                                                        … page privacy/microphone
    IpcHandler {
        target: "settings"
        function page(key: string): void {
            const parts = key.split("/");
            if (!window.pages.some(p => p?.key === parts[0]))
                return;
            window.subpage = parts[1] ?? "";
            if (window.page === parts[0] && pageLoader.item?.hasOwnProperty("selected"))
                pageLoader.item.selected = window.subpage;
            window.page = parts[0];
        }
    }

    ConfirmDialog {}

    // Closing the window ends the app (else the process stayed, windowless, forever) –
    // after a running package operation (uninstall, clean up), which quitting would break off
    onClosed: PackageAdmin.busy ? PackageAdmin.finished.connect(() => Qt.quit()) : Qt.quit()

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

            // (scrolls when the window is lower than the list of pages)
            Flickable {
                id: sidebar
                anchors.fill: parent
                contentHeight: pageList.implicitHeight + 28
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                FastScroll {
                    view: sidebar
                }

            Column {
                id: pageList
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

                            GlyphTile {
                                id: icon
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: entry.modelData?.icon ?? ""
                                color: entry.modelData?.colour ?? "transparent"
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
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Config.border
        }

        // The page; created fresh on every switch (scanners etc. run only while visible)
        Loader {
            id: pageLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            source: {
                const files = {
                    network: "settings/NetworkPage.qml", bluetooth: "settings/BluetoothPage.qml",
                    sound: "settings/SoundPage.qml", notifications: "settings/NotificationsPage.qml",
                    privacy: "settings/PrivacyPage.qml",
                    general: "settings/GeneralPage.qml", login: "settings/LoginItemsPage.qml",
                    apps: "settings/AppsPage.qml", storage: "settings/StoragePage.qml", timemachine: "settings/TimeMachinePage.qml",
                    defaults: "settings/DefaultAppsPage.qml",
                    appearance: "settings/AppearancePage.qml", accessibility: "settings/AccessibilityPage.qml", desktop: "settings/DesktopPage.qml",
                    displays: "settings/DisplaysPage.qml", energy: "settings/EnergyPage.qml", mouse: "settings/MousePage.qml",
                    keyboard: "settings/KeyboardPage.qml", printers: "settings/PrintersPage.qml"
                };
                return Quickshell.shellPath(files[window.page]);
            }
            onLoaded: {
                if (item.hasOwnProperty("window"))
                    item.window = window;
                if (item.hasOwnProperty("selected"))
                    item.selected = window.subpage;
            }
        }
    }
}
