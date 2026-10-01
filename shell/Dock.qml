import QtQuick
import Quickshell
import Quickshell.Wayland

// The dock at the bottom of every screen.
//   pinned apps (settings.json → dock.pinned), then running apps that are not pinned –
//   not those in the background (their icon is in the menu bar, Background.qml).
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
            if (seen[key] || Background.has(key))
                continue;
            seen[key] = true;
            running.push({ key: key, entry: Apps.entryForAppId(w.appId), pinned: false, appId: w.appId });
        }
        return running.length > 0 ? list.concat([{ separator: true }], running) : list;
    }

    // ---- Dragging icons (DockItem / LaunchpadTile report the mouse) ----
    //   sideways: reorder the pinned apps; a running app dropped among them gets pinned
    //   up out of the dock: unpin
    readonly property int slot: size + 4                  // icon + spacing
    readonly property var pinnedKeys: items.filter(i => i.pinned).map(i => i.key)
    property string dragKey: ""
    property real dragX: 0                                // mouse in dock window coordinates
    property real dragY: 0
    property real dragStartCenter: 0
    readonly property bool dragging: dragKey !== ""
    // (not `dragKey === key`: the separator has no key, and "" is also "nothing dragged" –
    // it was lifted out of the plate)
    function dragged(item) {
        return dragging && dragKey === (item.key ?? "");
    }
    readonly property int dragFrom: pinnedKeys.indexOf(dragKey)   // -1 = a running, unpinned app
    readonly property bool dragRemove: dragging && dragY < plate.y - 50
    readonly property var dragEntry: items.find(i => i.key === dragKey)?.entry ?? null
    // where the dragged icon would land among the pinned ones, -1 = not among them
    readonly property int dropIndex: {
        if (!dragging || dragRemove)
            return -1;
        const others = pinnedKeys.length - (dragFrom >= 0 ? 1 : 0);
        const i = Math.round((dragX - plate.x - padding - size / 2) / slot);
        if (dragFrom < 0 && (i > others || !dragEntry))
            return -1; // a running app dragged along the running ones: not pinned
        return Math.max(0, Math.min(others, i));
    }

    function startDrag(key, center) {
        dragKey = key;
        dragStartCenter = center;
    }
    function moveDrag(x, y) {
        dragX = x;
        dragY = y;
    }
    function endDrag() {
        const keys = pinnedKeys.filter(k => k !== dragKey);
        if (dropIndex >= 0)
            keys.splice(dropIndex, 0, dragKey);
        const changed = JSON.stringify(keys) !== JSON.stringify(pinnedKeys);
        dragKey = "";
        if (changed)
            Config.updateSettings(s => {
                s.dock = s.dock ?? {};
                s.dock.pinned = keys.map(k => k === "launchpad" ? k : Apps.plainId(k) + ".desktop");
            });
    }

    // How far an item moves sideways while something is dragged (animated in DockItem)
    function shiftFor(item) {
        if (!dragging)
            return 0;
        if (item.key === dragKey)
            return dragX - dragStartCenter;
        const pinnedNow = pinnedKeys.length;
        const pinnedAfter = pinnedNow - (dragFrom >= 0 ? 1 : 0) + (dropIndex >= 0 ? 1 : 0);
        if (!item.pinned) // separator and running apps follow the size of the pinned part
            return (pinnedAfter - pinnedNow) * slot;
        let j = pinnedKeys.indexOf(item.key);
        const natural = j;
        if (dragFrom >= 0 && j > dragFrom)
            j--;
        if (dropIndex >= 0 && j >= dropIndex)
            j++;
        return (j - natural) * slot;
    }

    // over an app in full screen: hidden, shown while the pointer is at the bottom edge
    FullscreenReveal {
        id: reveal
        screen: dock.screen
        edge: "bottom"
        hold: plateHover.hovered || dock.dragging || OpenMenus.count > 0
    }
    visible: reveal.shown
    WlrLayershell.layer: reveal.layer
    WlrLayershell.namespace: "dock"
    anchors.bottom: true
    implicitWidth: plate.width + 200
    implicitHeight: plateHeight + headroom + bottomGap
    exclusiveZone: plateHeight + bottomGap
    color: "transparent"

    // "Entfernen" above the dock while an icon is dragged out of it
    Tooltip {
        visible: dock.dragRemove
        x: Math.round(dock.dragX - width / 2)
        y: 4
        text: "Aus dem Dock entfernen"
    }

    // Only the plate takes clicks; the transparent rest lets them through to windows
    mask: Region {
        item: plate
    }

    Rectangle {
        id: plate
        HoverHandler {
            id: plateHover
        }
        x: Math.round((parent.width - width) / 2) // whole pixels keep the icons sharp
        anchors.bottom: parent.bottom
        // over a full-screen app it slides in from below and out again – by its margin, not
        // a transform: the click mask (mask: above) follows x/y/size only; after a slide by
        // transform it stayed where the plate had been and the dock took no clicks
        anchors.bottomMargin: dock.bottomGap - reveal.away * (dock.plateHeight + dock.bottomGap + 2)
        width: row.width + 2 * dock.padding
        height: dock.plateHeight
        radius: Config.radiusPanel + 4
        color: Config.glass
        border.color: Config.border
        border.width: 1

        Row {
            id: row
            x: dock.padding
            y: dock.padding
            spacing: 4

            Repeater {
                model: dock.items

                Loader {
                    id: slot
                    required property var modelData
                    sourceComponent: modelData.separator ? separator : modelData.launchpad ? launchpad : icon
                    z: dock.dragged(modelData) ? 1 : 0

                    // moves aside (or follows the mouse) while an icon is dragged
                    transform: Translate {
                        x: dock.shiftFor(slot.modelData)
                        y: dock.dragged(slot.modelData) ? Math.min(0, dock.dragY - plate.y - dock.padding - dock.size / 2) : 0
                        Behavior on x {
                            enabled: !dock.dragged(slot.modelData)
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }
                    }
                    opacity: dock.dragRemove && dock.dragged(modelData) ? 0.4 : 1

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
                            dockWindow: dock
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
