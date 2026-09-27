pragma Singleton

import QtQuick
import Quickshell

// Erscheinungsbild "Automatisch", like on a Mac: light by day, dark in the evening
// (settings.json appearance.auto, with appearance.light_from / dark_from in hours). It
// writes the mode that holds into appearance.mode – what the apps, Hyprland and
// desktop-theme read – so nothing else has to know about "automatic".
Singleton {
    id: root

    readonly property var appearance: Config.settings.appearance ?? ({})
    readonly property bool auto: appearance.auto === true
    readonly property real lightFrom: appearance.light_from ?? 7
    readonly property real darkFrom: appearance.dark_from ?? 19

    function wanted() {
        const d = new Date();
        const h = d.getHours() + d.getMinutes() / 60;
        return h >= lightFrom && h < darkFrom ? "light" : "dark";
    }
    function check() {
        if (!auto)
            return;
        const mode = wanted();
        if (Config.mode !== mode)
            Config.updateSettings(s => {
                s.appearance = s.appearance ?? {};
                s.appearance.mode = mode;
            });
    }
    onAutoChanged: check()
    onLightFromChanged: check()
    onDarkFromChanged: check()
    Component.onCompleted: check()
    Timer {
        running: root.auto
        repeat: true
        interval: 60 * 1000
        onTriggered: root.check()
    }
}
