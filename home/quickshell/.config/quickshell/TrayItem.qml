import QtQuick
import Quickshell
import Quickshell.Widgets

// Icon of an app running in the background (StatusNotifier / "tray"), in the menu bar.
//   click:        the app's main action (usually: show its window)
//   right-click:  the app's own menu, drawn in our menu style
Item {
    id: root

    required property var item  // SystemTrayItem
    property var barWindow

    implicitWidth: 26
    implicitHeight: parent ? parent.height : 30

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: 5
        color: mouse.containsMouse || menu.visible ? Config.hover : "transparent"
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: root.item.icon
        asynchronous: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: e => {
            if (e.button === Qt.RightButton || (e.button === Qt.LeftButton && root.item.onlyMenu)) {
                if (root.item.hasMenu)
                    menu.toggle();
            } else if (e.button === Qt.MiddleButton) {
                root.item.secondaryActivate();
            } else {
                root.item.activate();
            }
        }
        onWheel: e => root.item.scroll(e.angleDelta.y / 120, false)
    }

    // The app's menu entries (D-Bus menu), shown with our MenuPopup
    QsMenuOpener {
        id: opener
        menu: root.item.menu
    }

    MenuPopup {
        id: menu
        anchorItem: root
        keepOpenFor: root.barWindow ? [root.barWindow] : []
        items: opener.children.values.map(entry => entry.isSeparator ? { separator: true } : {
            text: entry.text.replace(/_(?=\S)/, "") + (entry.hasChildren ? "  ›" : ""), // drop mnemonic marks
            enabled: entry.enabled,
            action: () => {
                if (entry.hasChildren) {
                    // submenus: fall back to the app's own (native) menu
                    const pos = root.mapToItem(null, 0, root.height);
                    root.item.display(root.barWindow, pos.x, pos.y);
                } else {
                    entry.triggered();
                }
            }
        })
    }

    // Tooltip: the app's name
    Tooltip {
        visible: mouse.containsMouse && !menu.visible && text !== ""
        anchors.top: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.item.tooltipTitle || root.item.title || ""
    }
}
