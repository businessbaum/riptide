import QtQuick
import Quickshell

// One app in the dock.
//   click:        running → in front: minimize it, else bring its last window to the
//                 front; not running → start it (the icon bounces until it shows a window)
//   right-click:  menu with "Neues Fenster", "Im Dock behalten"/"Aus dem Dock entfernen",
//                 "In die Menüleiste ausblenden" (no window, still running, its icon in the
//                 menu bar – Background.qml) or "Einblenden" (hidden with ⌘H), "Beenden"
//   hover:        the app name above the icon
Item {
    id: root

    property var dockWindow
    property int size: 64
    property string key: ""
    property var entry: null
    property bool pinned: false
    property string appId: ""

    readonly property var windows: Apps.windowsOf(key)
    readonly property bool running: windows.length > 0
    // a window of it on a desktop – not only minimized or hidden ones
    // (workspace follows Hyprland's events; lastIpcObject only the last refresh)
    readonly property bool shown: windows.some(w => !(w.toplevel.workspace?.name ?? w.toplevel.lastIpcObject?.workspace?.name ?? "").startsWith("special:"))
    readonly property string name: entry?.name ?? appId
    property bool launching: false

    width: size
    height: size

    onRunningChanged: if (running) launching = false

    function click() {
        if (running) {
            Apps.toggle(windows[0].appId);
        } else if (entry && !launching) {
            launching = true;
            launchTimeout.restart();
            Apps.launch(entry);
        }
    }

    function togglePinned() {
        Apps.setPinned(entry, !root.pinned);
    }

    // Give up bouncing if the app never shows a window
    Timer {
        id: launchTimeout
        interval: 15000
        onTriggered: root.launching = false
    }

    AppIcon {
        id: image
        size: root.size
        entry: root.entry
        appId: root.appId
        opacity: mouse.pressed ? 0.7 : 1

        // Bouncing while the app starts, like on a Mac
        SequentialAnimation on y {
            running: root.launching
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { from: 0; to: -root.size * 0.35; duration: 280; easing.type: Easing.OutQuad }
            NumberAnimation { from: -root.size * 0.35; to: 0; duration: 280; easing.type: Easing.InQuad }
            PauseAnimation { duration: 80 }
        }
    }

    // Badge: new notifications since the app was last in front (NotificationStore), only
    // while the app is open (2026-09-30); on the App Store: the updates waiting
    // (Updates.qml), open or not
    Rectangle {
        readonly property int count: (root.running ? NotificationStore.badgeOf(root.key) : 0)
            + (Apps.plainId(root.key) === "org.riptide.AppStore" ? Updates.count : 0)
        visible: count > 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -2
        anchors.topMargin: -2
        width: Math.max(height, badgeText.implicitWidth + 10)
        height: Math.round(root.size * 0.34)
        radius: height / 2
        color: "#ff3b30"
        border.color: "#26000000"
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: parent.count > 99 ? "99+" : parent.count
            font.family: Config.fontSans
            font.pixelSize: Math.round(parent.height * 0.62)
            font.weight: Font.DemiBold
            color: "white"
        }
    }

    // Running indicator
    Rectangle {
        visible: root.running
        width: 4
        height: 4
        radius: 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 1
        color: Config.text
        opacity: 0.8
    }

    // App name above the icon while hovering
    Tooltip {
        visible: mouse.containsMouse && !menu.visible && !root.dockWindow.dragging
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 16
        text: root.name
    }

    // Click opens; pressing and moving drags the icon (Dock.qml: reorder, pin, unpin)
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point pressAt
        property bool dragged: false

        onPressed: e => {
            pressAt = Qt.point(e.x, e.y);
            dragged = false;
        }
        onPositionChanged: e => {
            if (!pressed || !(e.buttons & Qt.LeftButton))
                return;
            const p = mapToItem(root.dockWindow.contentItem, e.x, e.y);
            if (!dragged && Math.hypot(e.x - pressAt.x, e.y - pressAt.y) > 6) {
                dragged = true;
                root.dockWindow.startDrag(root.key, mapToItem(root.dockWindow.contentItem, root.width / 2, 0).x);
            }
            if (dragged)
                root.dockWindow.moveDrag(p.x, p.y);
        }
        onReleased: {
            if (dragged)
                root.dockWindow.endDrag();
        }
        onClicked: e => {
            if (dragged)
                return;
            e.button === Qt.RightButton ? menu.open() : root.click();
        }
    }

    MenuPopup {
        id: menu
        anchorItem: root
        anchorEdges: Edges.Top
        openTowards: Edges.Top
        offset: 18
        items: {
            const list = [];
            if (root.entry)
                list.push({ text: "Neues Fenster", action: () => { root.launching = !root.running; Apps.launchNew(root.entry); } });
            for (const a of Apps.actionsOf(root.entry))
                list.push({ text: a.name, action: () => Apps.launchAction(root.entry, a.id) });
            if (root.entry)
                list.push({ separator: true }, { text: root.pinned ? "Aus dem Dock entfernen" : "Im Dock behalten", action: () => root.togglePinned() });
            if (root.running) {
                list.push({ separator: true });
                if (root.shown)
                    list.push({ text: "In die Menüleiste ausblenden", action: () => Background.enter(root.key, root.windows[0].appId) });
                else
                    list.push({ text: "Einblenden", action: () => Apps.activate(root.windows[0].appId) });
                list.push({ text: "Beenden", action: () => Apps.quit(root.windows[0].appId) });
            }
            return list;
        }
    }
}
