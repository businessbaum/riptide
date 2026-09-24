import QtQuick
import Quickshell
import Quickshell.Wayland

// The dock at the bottom of every screen.
//   pinned apps (settings.json → dock.pinned), then running apps that are not pinned.
//   A dot marks running apps. The same app never appears twice.
// The window is taller than the plate: the transparent headroom above it holds the
// app name shown while hovering (Hyprland's snapping.lua knows this height: 40 px).
PanelWindow {
    id: dock

    readonly property int size: Config.dockSize
    readonly property int padding: 6
    readonly property int headroom: 40
    readonly property int bottomGap: 6
    readonly property int plateHeight: size + 2 * padding

    // [{ key, entry, pinned, appId }]
    readonly property var items: {
        // Desktop entries are read in the background after start; depending on the list
        // makes the dock fill itself as soon as they are there (not only when a window opens).
        const loaded = DesktopEntries.applications.values.length;
        const list = [];
        const seen = {};
        for (const id of Config.dockPinned) {
            if (id === "launchpad") {
                list.push({ key: "launchpad", entry: null, pinned: true, appId: "", launchpad: true });
                continue;
            }
            const entry = Apps.entryById(id);
            if (!entry || seen[entry.id])
                continue; // unknown or not installed
            seen[entry.id] = true;
            list.push({ key: entry.id, entry: entry, pinned: true, appId: "" });
        }
        const running = [];
        for (const w of Apps.windows) {
            const key = Apps.keyForAppId(w.appId);
            if (seen[key])
                continue;
            seen[key] = true;
            running.push({ key: key, entry: Apps.entryForAppId(w.appId), pinned: false, appId: w.appId });
        }
        return running.length > 0 ? list.concat([{ separator: true }], running) : list;
    }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "dock"
    anchors.bottom: true
    implicitWidth: plate.width + 200
    implicitHeight: plateHeight + headroom + bottomGap
    exclusiveZone: plateHeight + bottomGap
    color: "transparent"

    // Only the plate takes clicks; the transparent rest lets them through to windows
    mask: Region {
        item: plate
    }

    Rectangle {
        id: plate
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: dock.bottomGap
        width: row.width + 2 * dock.padding
        height: dock.plateHeight
        radius: Config.radiusPanel + 4
        color: Config.glass
        border.color: Config.border
        border.width: 1

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: dock.items

                Loader {
                    id: slot
                    required property var modelData
                    sourceComponent: modelData.separator ? separator : modelData.launchpad ? launchpad : icon

                    Component {
                        id: separator
                        Item {
                            width: 13
                            height: dock.size
                            Rectangle {
                                anchors.centerIn: parent
                                width: 1
                                height: parent.height - 12
                                color: Config.border
                            }
                        }
                    }

                    Component {
                        id: launchpad
                        LaunchpadTile {
                            size: dock.size
                        }
                    }

                    Component {
                        id: icon
                        DockItem {
                            dockWindow: dock
                            size: dock.size
                            key: slot.modelData.key
                            entry: slot.modelData.entry
                            pinned: slot.modelData.pinned
                            appId: slot.modelData.appId
                        }
                    }
                }
            }
        }
    }
}
