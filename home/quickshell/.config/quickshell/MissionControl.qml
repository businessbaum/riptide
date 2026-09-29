import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Mission Control and App Exposé, like on a Mac:
//   all  (⌃↑, ⌘ alone, hot corner)  every window of the desktop on each screen side by side, the
//                          desktops (Spaces) above – switch, or "+" for a new one
//   app  (⌃↓)              every window of the app in front, also minimized ones
// The windows glide from where they are into a grid while the desktop's picture comes up
// behind them (the real windows are hidden by it), and back when it closes; a click (or
// Enter) brings one to the front, Esc or a click on the free space closes. Pictures:
// screencopy of each window.
//   qs ipc call mission all | app
Scope {
    id: root

    property string mode: "" // "", "all", "app"
    property string appKey: ""
    property bool arranged: false // false: windows where they are, true: in the grid
    property bool closing: false  // gliding back before it goes

    function open(m) {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        const active = Hyprland.activeToplevel;
        appKey = Apps.keyForAppId(active?.wayland?.appId ?? active?.lastIpcObject?.class ?? "");
        if (m === "app" && appKey === "")
            return;
        hideLater.stop();
        closing = false;
        mode = m;
        arranged = false;
        glide.restart();
    }
    function close() {
        if (mode === "" || closing)
            return;
        closing = true;
        glide.stop();
        arranged = false; // back to where they are, then it goes
        hideLater.restart();
    }
    function toggle(m) {
        mode === m && !closing ? close() : open(m);
    }
    // the windows in place first – a moment for their pictures – then they glide
    Timer {
        id: glide
        interval: 90
        onTriggered: root.arranged = true
    }
    Timer {
        id: hideLater
        interval: Config.reduceMotion ? 0 : 280
        onTriggered: {
            root.mode = "";
            root.closing = false;
        }
    }
    function focus(w) {
        close();
        Hyprland.dispatch(`macos.focus_window('${w.address.replace(/[^0-9a-fx]/gi, "")}')`);
    }

    // ⌘ (the Windows key) tapped on its own – told by riptide-wm (window_buttons.cpp),
    // like three fingers up on a Mac's trackpad; tapped again it closes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom" && event.data === "super-tap" && !Lock.locked)
                root.toggle("all");
        }
    }

    IpcHandler {
        target: "mission"
        function all(): void {
            root.toggle("all");
        }
        function app(): void {
            root.toggle("app");
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            readonly property var monitor: Hyprland.monitors.values.find(m => m.name === modelData.name) ?? null
            readonly property bool focusedScreen: Hyprland.focusedMonitor?.name === modelData.name
            readonly property int monitorId: monitor?.id ?? -1

            // the windows shown on this screen
            readonly property var windows: {
                if (root.mode === "")
                    return [];
                return Apps.windows.filter(w => {
                    const o = w.toplevel.lastIpcObject ?? {};
                    const minimized = ["special:minimized", "special:hidden"].includes(o.workspace?.name ?? "");
                    if (root.mode === "app")
                        return Apps.keyForAppId(w.appId) === root.appKey
                            && (minimized ? panel.focusedScreen : o.monitor === panel.monitorId);
                    return o.monitor === panel.monitorId && o.workspace?.id === panel.monitor?.activeWorkspace?.id;
                });
            }
            // the desktops of this screen (normal ones)
            readonly property var desktops: Hyprland.workspaces.values
                .filter(ws => ws.id > 0 && (ws.lastIpcObject?.monitor ?? ws.monitor?.name) === modelData.name)
                .sort((a, b) => a.id - b.id)

            // the grid: as many columns as give the windows the most room
            readonly property rect area: Qt.rect(60, root.mode === "all" ? 170 : 90, width - 120, height - (root.mode === "all" ? 230 : 150))
            readonly property var layout: {
                const n = windows.length;
                if (n === 0)
                    return { cols: 1, cellW: 0, cellH: 0, scale: 0 };
                const gap = 40;
                let best = null;
                for (let cols = 1; cols <= n; cols++) {
                    const rows = Math.ceil(n / cols);
                    const cellW = (area.width - gap * (cols - 1)) / cols;
                    const cellH = (area.height - gap * (rows - 1)) / rows - 28; // room for the title
                    let scale = 0.8; // never full size: it is an overview
                    for (const w of windows) {
                        const s = w.toplevel.lastIpcObject?.size ?? [800, 600];
                        scale = Math.min(scale, cellW / s[0], cellH / s[1]);
                    }
                    if (!best || scale > best.scale)
                        best = { cols, rows, cellW, cellH, scale, gap };
                }
                return best;
            }

            screen: modelData
            visible: root.mode !== ""
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "missioncontrol"
            WlrLayershell.keyboardFocus: focusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"

            property int chosen: 0
            onVisibleChanged: {
                chosen = 0;
                if (visible && focusedScreen)
                    keys.forceActiveFocus();
            }

            // the desktop's own picture behind the windows, a little darker – the real
            // windows disappear under it while their pictures glide into the grid; a click
            // on it closes
            WallpaperImage {
                anchors.fill: parent
                opacity: root.arranged ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Config.reduceMotion ? 0 : 260; easing.type: Easing.OutCubic }
                }
            }
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: root.arranged ? 0.2 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Config.reduceMotion ? 0 : 260 }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Item {
                id: keys
                focus: true
                Keys.onEscapePressed: root.close()
                Keys.onReturnPressed: if (panel.windows[panel.chosen]) root.focus(panel.windows[panel.chosen])
                Keys.onRightPressed: panel.chosen = Math.min(panel.windows.length - 1, panel.chosen + 1)
                Keys.onLeftPressed: panel.chosen = Math.max(0, panel.chosen - 1)
                Keys.onDownPressed: panel.chosen = Math.min(panel.windows.length - 1, panel.chosen + panel.layout.cols)
                Keys.onUpPressed: panel.chosen = Math.max(0, panel.chosen - panel.layout.cols)
            }

            // Spaces: the desktops of this screen
            Row {
                visible: root.mode === "all"
                anchors.horizontalCenter: parent.horizontalCenter
                y: 34
                spacing: 18
                opacity: root.arranged ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 220 }
                }

                Repeater {
                    model: panel.desktops
                    Rectangle {
                        id: desk
                        required property var modelData
                        readonly property bool current: modelData.id === panel.monitor?.activeWorkspace?.id
                        width: 150
                        height: 90
                        radius: 10
                        color: deskMouse.containsMouse ? "#40ffffff" : "#26ffffff"
                        border.width: current ? 2 : 1
                        border.color: current ? Config.accent : "#40ffffff"
                        // the apps on it
                        Row {
                            anchors.centerIn: parent
                            spacing: -6
                            Repeater {
                                model: Apps.windows.filter(w => w.toplevel.lastIpcObject?.workspace?.id === desk.modelData.id).slice(0, 5)
                                AppIcon {
                                    required property var modelData
                                    size: 32
                                    entry: Apps.entryForAppId(modelData.appId)
                                    appId: modelData.appId
                                }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            anchors.topMargin: 6
                            text: "Schreibtisch " + desk.modelData.id
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: "white"
                        }
                        MouseArea {
                            id: deskMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Hyprland.dispatch(`hl.dsp.focus({ workspace = ${desk.modelData.id} })`);
                                Hyprland.refreshToplevels();
                            }
                        }
                    }
                }
                // a new desktop on this screen
                Rectangle {
                    width: 60
                    height: 90
                    radius: 10
                    color: addMouse.containsMouse ? "#40ffffff" : "#1affffff"
                    border.color: "#40ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.family: Config.fontSans
                        font.pixelSize: 28
                        color: "white"
                    }
                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Hyprland.dispatch(`hl.dsp.focus({ workspace = "emptynm" })`);
                            Hyprland.refreshWorkspaces();
                        }
                    }
                }
            }

            Text {
                visible: panel.windows.length === 0 && root.arranged
                anchors.centerIn: parent
                text: root.mode === "app" ? "Keine Fenster" : "Keine Fenster auf diesem Schreibtisch"
                font.family: Config.fontSans
                font.pixelSize: 16
                color: "#ccffffff"
            }

            // the windows
            Repeater {
                model: panel.windows

                Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property var o: modelData.toplevel.lastIpcObject ?? {}
                    readonly property real w0: o.size?.[0] ?? 800
                    readonly property real h0: o.size?.[1] ?? 600
                    // where it is on this screen now …
                    readonly property real x0: (o.at?.[0] ?? 0) - (panel.monitor?.x ?? 0)
                    readonly property real y0: (o.at?.[1] ?? 0) - (panel.monitor?.y ?? 0)
                    // … and its place in the grid
                    readonly property int col: index % panel.layout.cols
                    readonly property int row: Math.floor(index / panel.layout.cols)
                    readonly property int rowCount: Math.min(panel.layout.cols, panel.windows.length - row * panel.layout.cols)
                    readonly property real gw: w0 * panel.layout.scale
                    readonly property real gh: h0 * panel.layout.scale
                    readonly property real rowWidth: rowCount * panel.layout.cellW + (rowCount - 1) * panel.layout.gap
                    readonly property real gx: panel.area.x + (panel.area.width - rowWidth) / 2
                        + col * (panel.layout.cellW + panel.layout.gap) + (panel.layout.cellW - gw) / 2
                    readonly property real gy: panel.area.y + row * (panel.layout.cellH + 28 + panel.layout.gap)
                        + (panel.area.height - panel.layout.rows * (panel.layout.cellH + 28) - (panel.layout.rows - 1) * panel.layout.gap) / 2
                        + (panel.layout.cellH - gh) / 2
                    readonly property bool minimized: ["special:minimized", "special:hidden"].includes(o.workspace?.name ?? "")
                    readonly property bool hot: mouse.containsMouse || panel.chosen === index

                    x: root.arranged || minimized ? gx : x0
                    y: root.arranged || minimized ? gy : y0
                    width: root.arranged || minimized ? gw : w0
                    height: root.arranged || minimized ? gh : h0
                    Behavior on x { NumberAnimation { duration: Config.reduceMotion ? 0 : 260; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Config.reduceMotion ? 0 : 260; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: Config.reduceMotion ? 0 : 260; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: Config.reduceMotion ? 0 : 260; easing.type: Easing.OutCubic } }

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: 10
                        color: "#303036"
                        border.width: tile.hot ? 3 : 0
                        border.color: Config.accent
                        opacity: tile.minimized ? 0.7 : 1

                        ScreencopyView {
                            id: picture
                            anchors.fill: parent
                            live: false
                            captureSource: tile.modelData.toplevel.wayland ?? null
                            Component.onCompleted: captureFrame()
                            // sharp when small: drawn at twice its size in the grid, then scaled
                            // down smoothly – compared side by side (2026-09-29): mipmaps made
                            // the text soft, plain scaling grainy
                            layer.enabled: true
                            layer.smooth: true
                            layer.textureSize: Qt.size(Math.max(1, Math.round(tile.gw * 2)), Math.max(1, Math.round(tile.gh * 2)))
                            // asked before the capture is ready, it gets no picture: once more
                            Timer {
                                property int tries: 0
                                interval: 80
                                repeat: true
                                running: !picture.hasContent && tries < 12
                                onTriggered: {
                                    tries++;
                                    picture.captureFrame();
                                }
                            }
                        }
                        AppIcon {
                            visible: !picture.hasContent
                            anchors.centerIn: parent
                            size: Math.min(96, parent.width / 3)
                            entry: Apps.entryForAppId(tile.modelData.appId)
                            appId: tile.modelData.appId
                        }
                    }
                    // the app's icon on the window, its title below while hovered
                    AppIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.bottom
                        size: 44
                        opacity: root.arranged ? 1 : 0
                        entry: Apps.entryForAppId(tile.modelData.appId)
                        appId: tile.modelData.appId
                    }
                    Rectangle {
                        visible: tile.hot && root.arranged
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 26
                        width: Math.min(titleText.implicitWidth + 20, 360)
                        height: 24
                        radius: 12
                        color: "#cc1c1c1e"
                        Text {
                            id: titleText
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, 340)
                            elide: Text.ElideRight
                            text: tile.modelData.title || Apps.name(Apps.keyForAppId(tile.modelData.appId))
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: "white"
                        }
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: panel.chosen = tile.index
                        onClicked: root.focus(tile.modelData)
                    }
                }
            }
        }
    }
}
