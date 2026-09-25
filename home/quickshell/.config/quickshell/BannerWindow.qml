import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Draws what Banners.qml shows: at the top right of the active screen, newest on top.
// Short system messages are narrow (StatusBanner.qml), notifications full width
// (NotificationCard.qml). Both hide themselves and then leave the list.
Scope {
    PanelWindow {
        visible: Banners.order.count > 0
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "notifications"
        anchors.top: true
        anchors.right: true
        margins.top: 8
        margins.right: 8
        implicitWidth: 368 // room for the × that overlaps the top left corner
        implicitHeight: Math.max(1, column.implicitHeight + 6)
        color: "transparent"

        Column {
            id: column
            x: 8
            y: 6
            width: parent.width - 8
            spacing: 8
            move: Transition {
                NumberAnimation { properties: "y"; duration: 200; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: Banners.order

                delegate: DelegateChooser {
                    role: "kind"

                    DelegateChoice {
                        roleValue: "status"

                        StatusBanner {
                            required property string key
                            readonly property var entry: Banners.entries[key] ?? ({})
                            x: column.width - width
                            glyph: entry.glyph ?? ""
                            icon: entry.icon ?? ""
                            title: entry.title ?? ""
                            subtitle: entry.subtitle ?? ""
                            value: entry.value ?? -1
                            timeout: entry.timeout ?? 4000
                            stamp: entry.stamp ?? 0
                            onGone: Banners.remove(key)
                        }
                    }
                    DelegateChoice {
                        roleValue: "notification"

                        NotificationCard {
                            required property string key
                            readonly property var entry: Banners.entries[key] ?? ({})
                            width: column.width
                            banner: true
                            n: entry.notification ?? null
                            timeout: entry.timeout ?? 5000
                            stamp: entry.stamp ?? 0
                            onGone: Banners.remove(key)
                        }
                    }
                }
            }
        }
    }
}
