import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// riptide's login window (greetd). Runs as the user "greeter" in its own Hyprland
// (hyprland.lua here), started by /usr/local/lib/riptide/greeter/start. Every screen shows
// the wallpaper and the time; the first one the person and the password (LoginScreen.qml,
// the login itself: Login.qml). At boot and after a logout the session's own lock screen
// is the login instead – this one is for someone else, or when that did not start.
//
// Emergency ways in (all ask for the password):
//   - should this window not come up or break, a text login appears in its place
//   - ⌃⌥F2 here ends it and gives the text login (hyprland.lua)
//   - at power-on: F11 → the mainboard's boot menu → "riptide Notfallmodus" (no graphics)
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

            // the same window as the session's lock screen (installed from the shell's
            // LoginScreen.qml by setup-os.sh)
            LoginScreen {
                id: screen
                anchors.fill: parent
                main: win.main
                displayName: Login.displayName
                busy: Login.busy
                error: Login.error
                failures: Login.failures
                onSubmit: (name, password) => Login.login(name, password)
                onPower: action => Login.power(action)
                onEmergency: Hyprland.dispatch("hl.dsp.exit()")
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
