pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// The main screen ("Hauptbildschirm", System Settings → Bildschirme): the lock screen shows
// the password field there, the other screens what was chosen for them (LockInfo.qml).
// Kept as Hyprland's description – maker, model, serial number – because the connector
// names change between starts (DP-2/DP-3 once, DP-1/DP-2 now). Nothing chosen, or that
// screen is not connected: the screen with the pointer, as before.
Singleton {
    readonly property string description: Config.settings.displays?.main ?? ""
    readonly property string chosen: Hyprland.monitors.values.find(m => m.description === description)?.name ?? ""
    readonly property string name: chosen || (Hyprland.focusedMonitor?.name ?? "")
}
