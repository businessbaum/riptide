import QtQuick
import Quickshell

// One app in the dock.
//   click:        running → bring its last window to the front, else start it
//                 (the icon bounces until the app shows a window)
//   right-click:  menu with "Neues Fenster", "Im Dock behalten"/"Aus dem Dock entfernen", "Beenden"
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
    readonly property string name: entry?.name ?? appId
    property bool launching: false

    width: size
    height: size

    onRunningChanged: if (running) launching = false

    function click() {
        if (running) {
            Apps.activate(windows[0].appId);
        } else if (entry && !launching) {
            launching = true;
            launchTimeout.restart();
            Apps.launch(entry);
        }
    }

    function togglePinned() {
        const id = Apps.plainId(entry.id) + ".desktop";
        Config.updateSettings(s => {
            s.dock = s.dock ?? {};
            const pinned = (s.dock.pinned ?? []).filter(p => Apps.plainId(p) !== Apps.plainId(entry.id));
            if (!root.pinned)
                pinned.push(id);
            s.dock.pinned = pinned;
        });
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
        keepOpenFor: [root.dockWindow]
        items: {
            const list = [];
            if (root.entry)
                list.push({ text: "Neues Fenster", action: () => { root.launching = !root.running; Apps.launchNew(root.entry); } });
            if (root.entry)
                list.push({ text: root.pinned ? "Aus dem Dock entfernen" : "Im Dock behalten", action: () => root.togglePinned() });
            if (root.running) {
                list.push({ separator: true });
                list.push({ text: "Beenden", action: () => Apps.quit(root.windows[0].appId) });
            }
            return list;
        }
    }
}
