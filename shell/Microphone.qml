pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The microphone switched off for every app at once (the default input muted in
// PipeWire): from the control centre or the microphone key. A banner says it each time.
Singleton {
    id: root

    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: source?.audio !== undefined && source?.audio !== null
    readonly property bool muted: source?.audio?.muted ?? false

    PwObjectTracker {
        objects: [root.source]
    }

    function toggle() {
        if (available)
            source.audio.muted = !source.audio.muted;
    }

    // values while the source connects are not news
    property bool armed: false
    Timer {
        running: root.available
        interval: 2000
        onTriggered: root.armed = true
    }
    onMutedChanged: {
        if (!armed)
            return;
        Banners.show({
            key: "microphone",
            glyph: muted ? "\u{f036d}" : "\u{f036c}", // microphone off / on
            title: muted ? "Mikrofon aus" : "Mikrofon an",
            subtitle: muted ? "Keine App hört dich" : "Apps mit Erlaubnis hören dich wieder"
        });
    }
}
