import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// "Aktive Ecken", like on a Mac: the pointer in a corner of a screen starts what was
// chosen for it (System Settings → Schreibtisch & Dock; settings.json desktop.hot_corners:
// { tl, tr, bl, br }). Each corner is a 2×2 pixel surface; the pointer has to stay a
// moment, and nothing happens while an app is in full screen (games).
Scope {
    id: root

    readonly property var corners: Config.settings.desktop?.hot_corners ?? ({})

    function run(action) {
        if (action === "mission")
            Quickshell.execDetached(["qs", "ipc", "call", "mission", "all"]);
        else if (action === "app")
            Quickshell.execDetached(["qs", "ipc", "call", "mission", "app"]);
        else if (action === "desktop")
            Hyprland.dispatch("macos.show_desktop()");
        else if (action === "launchpad")
            Quickshell.execDetached(["qs", "ipc", "call", "launchpad", "toggle"]);
        else if (action === "notifications")
            Quickshell.execDetached(["qs", "ipc", "call", "menubar-" + (Hyprland.focusedMonitor?.name ?? ""), "notificationCenter"]);
        else if (action === "lock")
            Lock.lock();
        else if (action === "sleep")
            Session.sleep();
        else if (action === "screens-off")
            Hyprland.dispatch("hl.dsp.dpms({ action = \"off\" })");
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Repeater {
                model: [
                    { key: "tl", top: true, left: true },
                    { key: "tr", top: true, left: false },
                    { key: "bl", top: false, left: true },
                    { key: "br", top: false, left: false }
                ]

                PanelWindow {
                    id: corner
                    required property var modelData
                    readonly property string action: root.corners[modelData.key] ?? "none"

                    screen: perScreen.modelData
                    visible: action !== "none"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "hotcorner"
                    exclusionMode: ExclusionMode.Ignore
                    anchors.top: modelData.top
                    anchors.bottom: !modelData.top
                    anchors.left: modelData.left
                    anchors.right: !modelData.left
                    implicitWidth: 2
                    implicitHeight: 2
                    color: "transparent"

                    HoverHandler {
                        onHoveredChanged: hovered ? dwell.restart() : dwell.stop()
                    }
                    Timer {
                        id: dwell
                        interval: 150
                        onTriggered: {
                            if (!Hyprland.focusedWorkspace?.hasFullscreen)
                                root.run(corner.action);
                        }
                    }
                }
            }
        }
    }
}
