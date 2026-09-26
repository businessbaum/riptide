pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Who is using the microphone, the camera or sees the screen right now – only while a
// stream really runs (an active PipeWire link). One place for the menu bar dots
// (PrivacyIndicator.qml) and "Nicht stören while sharing the screen" (NotificationStore).
Singleton {
    id: root

    // (state and properties are only known for what is tracked)
    PwObjectTracker {
        objects: {
            const list = [];
            for (const g of Pipewire.linkGroups.values)
                list.push(g, g.source, g.target);
            return list.filter(o => o);
        }
    }
    readonly property var active: Pipewire.linkGroups.values.filter(g => g.state === PwLinkState.Active && g.source && g.target)
    function classOf(node) {
        return node?.properties?.["media.class"] ?? "";
    }
    function appOf(node) {
        const p = node?.properties ?? {};
        const app = Privacy.appOfStream(node); // sandboxed apps: named by the service
        return (app && Apps.name(app)) || p["application.process.binary"] || p["application.name"] || node?.name || "?";
    }
    function usersOf(test) {
        const names = [];
        for (const g of active) {
            if (test(g.source, g.target) && !names.includes(appOf(g.target)))
                names.push(appOf(g.target));
        }
        return names;
    }
    readonly property var microphone: usersOf((s, t) => classOf(t) === "Stream/Input/Audio" && classOf(s).startsWith("Audio/Source"))
    readonly property var camera: usersOf((s, t) => classOf(t) === "Stream/Input/Video" && classOf(s) === "Video/Source" && !(s.name ?? "").startsWith("xdg-desktop-portal"))
    readonly property var screen: usersOf((s, t) => classOf(t) === "Stream/Input/Video" && (s.name ?? "").startsWith("xdg-desktop-portal"))
    readonly property bool sharingScreen: screen.length > 0
}
