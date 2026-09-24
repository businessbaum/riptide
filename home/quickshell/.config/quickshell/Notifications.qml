import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland

// Banners in the top right of the active screen, like on a Mac.
//   Normal banners disappear after 5 s (hovering pauses), critical ones stay.
//   Click: run the notification's default action, otherwise just close it.
// Every notification also stays in the notification centre (click on the clock).
Scope {
    id: root

    ListModel {
        id: banners
    }

    Connections {
        target: NotificationStore
        function onArrived(n) {
            if (!NotificationStore.doNotDisturb || n.urgency === NotificationUrgency.Critical)
                banners.insert(0, { notification: n });
        }
    }

    function removeBanner(n) {
        for (let i = 0; i < banners.count; i++) {
            if (banners.get(i).notification === n) {
                banners.remove(i);
                return;
            }
        }
    }

    PanelWindow {
        id: window

        visible: banners.count > 0
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

            Repeater {
                model: banners

                NotificationCard {
                    required property var notification
                    width: column.width
                    n: notification
                    banner: true
                    onDone: root.removeBanner(notification)
                }
            }
        }
    }
}
