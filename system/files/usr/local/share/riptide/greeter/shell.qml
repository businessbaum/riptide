import QtQuick
import Quickshell
import Quickshell.Wayland

// riptide's login window (greetd). Runs as the user "greeter" in its own Hyprland
// (hyprland.lua here), started by /usr/local/lib/riptide/greeter/start. Every screen shows
// the wallpaper and the time; the first one the person and the password (LoginScreen.qml,
// the login itself: Login.qml).
//
// Emergency ways in (all ask for the password):
//   - should this window not come up or break, a text login appears in its place
//   - ⌃⌥F2 here ends it and gives the text login (hyprland.lua)
//   - at power-on: hold the space bar → boot menu → "Notfallmodus" (no graphics at all)
ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool main: modelData === Quickshell.screens[0]

            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "#1b2a4a"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "riptide-greeter"
            WlrLayershell.keyboardFocus: main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            LoginScreen {
                id: screen
                anchors.fill: parent
                main: win.main
            }

            Component.onCompleted: {
                if (!main)
                    return;
                screen.focusField();
                // tells the start script that the login window came up
                Quickshell.execDetached(["touch", Login.stateDir + "/ready"]);
            }
        }
    }
}
