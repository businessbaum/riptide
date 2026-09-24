//@ pragma AppId org.riptide.AppStore
//@ pragma IconTheme Adwaita
//@ pragma UseQApplication

// "App Store": a separate Quickshell instance (own app id → own dock icon), built on the
// official Arch app catalog (appstream) and pacman. Installing and removing goes through
// /usr/local/sbin/appstore-helper (pkexec → our password dialog), official repos only.
//   Start:  scripts/app-store.sh   (org.riptide.AppStore.desktop)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.appstore

FloatingWindow {
    id: window

    property string page: "discover"
    property var detail: null     // app shown in detail, or null
    property string query: ""

    readonly property var pages: [
        { key: "discover", title: "Entdecken", icon: "" },
        { key: "installed", title: "Installiert", icon: "" },
        { key: "updates", title: "Updates", icon: "" },
        null
    ].concat(Catalog.categories.map(c => ({ key: "cat:" + c, title: c, icon: "" })))

    title: "App Store"
    implicitWidth: 1040
    implicitHeight: 700
    minimumSize: Qt.size(820, 480)
    color: Config.windowBg

    // Open a page from outside:  qs ipc -p ~/.config/quickshell/appstore.qml call appstore page updates
    IpcHandler {
        target: "appstore"
        function page(key: string): void {
            window.detail = null;
            window.query = "";
            window.page = key;
        }
        // show one app, e.g.  … call appstore app gimp
        function app(pkg: string): void {
            window.detail = Catalog.apps.find(a => a.pkg === pkg) ?? null;
        }
    }

    ConfirmDialog {}

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar: search and pages
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            color: Config.sidebarBg

            Column {
                x: 10
                y: 14
                width: parent.width - 20
                spacing: 2

                Rectangle {
                    width: parent.width
                    height: 30
                    radius: 8
                    color: Config.tile
                    border.color: search.activeFocus ? Config.accent : Config.border
                    TextInput {
                        id: search
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: Config.fontSans
                        font.pixelSize: 13
                        color: Config.text
                        clip: true
                        onTextChanged: {
                            window.query = text;
                            window.detail = null;
                        }
                        Keys.onEscapePressed: text = ""
                        Text {
                            visible: search.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Suchen"
                            font: search.font
                            color: Config.textSecondary
                        }
                    }
                }
                Item {
                    width: 1
                    height: 8
                }

                Repeater {
                    model: window.pages
                    Item {
                        id: entry
                        required property var modelData
                        readonly property bool selected: window.query === "" && entry.modelData?.key === window.page
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
                            color: entry.selected ? Config.accent : mouse.containsMouse ? Config.hover : "transparent"
                            Text {
                                id: glyph
                                x: 10
                                width: 18
                                anchors.verticalCenter: parent.verticalCenter
                                text: entry.modelData?.icon ?? ""
                                font.family: Config.fontSymbols
                                font.pixelSize: 12
                                color: entry.selected ? "white" : Config.accent
                            }
                            Text {
                                anchors.left: glyph.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: entry.modelData?.title ?? ""
                                font.family: Config.fontSans
                                font.pixelSize: 13
                                color: entry.selected ? "white" : Config.text
                            }
                            // number of updates
                            Rectangle {
                                visible: entry.modelData?.key === "updates" && Catalog.updates.length > 0
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(18, count.implicitWidth + 10)
                                height: 18
                                radius: 9
                                color: entry.selected ? "white" : Config.accent
                                Text {
                                    id: count
                                    anchors.centerIn: parent
                                    text: Catalog.updates.length
                                    font.family: Config.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: entry.selected ? Config.accent : "white"
                                }
                            }
                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    search.text = "";
                                    window.detail = null;
                                    window.page = entry.modelData.key;
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

        // Content
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Loader {
                anchors.fill: parent
                active: window.detail !== null
                sourceComponent: AppDetail {
                    app: window.detail
                    onBack: window.detail = null
                }
            }

            UpdatesPage {
                anchors.fill: parent
                visible: window.detail === null && window.query === "" && window.page === "updates"
            }

            AppGrid {
                anchors.fill: parent
                visible: window.detail === null && !(window.query === "" && window.page === "updates")
                onOpen: app => window.detail = app
                title: window.query !== "" ? `Suche: „${window.query}“`
                     : window.page === "discover" ? "Entdecken"
                     : window.page === "installed" ? "Installiert"
                     : window.page.slice(4)
                subtitle: window.query !== "" ? ""
                        : window.page === "discover" ? "Beliebte Apps aus den offiziellen Arch-Paketquellen"
                        : window.page === "installed" ? "Apps auf diesem Computer"
                        : ""
                apps: window.query !== "" ? Catalog.search(window.query)
                    : window.page === "discover" ? Catalog.featured
                    : window.page === "installed" ? Catalog.apps.filter(a => Catalog.isInstalled(a))
                    : Catalog.apps.filter(a => a.categories.includes(window.page.slice(4)))
                empty: window.page === "installed" ? "Noch keine Apps aus dem Katalog installiert." : "Keine Apps gefunden."
            }
        }
    }
}
