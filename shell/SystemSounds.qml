pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Sound effects of the system, like on a Mac (System Settings → Ton → Toneffekte):
//   ui(name)       interface sounds – trash emptied, … (sound.ui_sounds, on by default)
//   volume()       a click when the volume keys change it (sound.volume_feedback, off)
// Sounds of the freedesktop theme (sound-theme-freedesktop), played with pw-play.
// Screenshots play theirs in hypr/scripts/screenshot.sh (same switch).
Singleton {
    id: root

    readonly property bool uiSounds: Config.settings.sound?.ui_sounds !== false
    readonly property bool volumeFeedback: Config.settings.sound?.volume_feedback === true

    function play(name) {
        Quickshell.execDetached(["pw-play", "--media-role=Notification", "/usr/share/sounds/freedesktop/stereo/" + name + ".oga"]);
    }
    function ui(name) {
        if (uiSounds)
            play(name);
    }
    // (not more than one click at a time while a key is held)
    property double lastClick: 0
    function volume() {
        if (!volumeFeedback || Date.now() - lastClick < 150)
            return;
        lastClick = Date.now();
        play("audio-volume-change");
    }

    // the volume keys (hypr/modules/keys.lua): qs ipc call sounds volume
    IpcHandler {
        target: "sounds"
        function volume(): void {
            root.volume();
        }
    }
}
