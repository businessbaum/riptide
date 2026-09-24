import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Wayland

// Panel for ⌘Tab (apps) and ⌥Tab (windows). All logic is in Hyprland
// (modules/switcher.lua); it sends "custom>>switcher>>show|seq|mode|index|monitor|addresses"
// and "…>>hide|seq|" and this panel only displays. Clicking an entry picks it.
Scope {
    id: root

    property bool shown: false
    property string mode: "apps"
    property int index: 1
    property string monitorName: ""
    property var entries: []   // [{ address, appId, title, entry }]
    property int lastSeq: 0

    function strip(address) {
        return address.replace(/^0x/, "");
    }

    function lookup(address) {
        const a = strip(address);
        const t = Hyprland.toplevels.values.find(t => strip(t.address) === a);
        const appId = t?.wayland?.appId ?? t?.lastIpcObject?.class ?? "";
        return { address: a, appId: appId, title: t?.title ?? "", entry: appId ? Apps.entryForAppId(appId) : null };
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "custom" || !event.data.startsWith("switcher>>"))
                return;
            const [action, seq, mode, index, monitor, addresses] = event.data.slice(10).split("|");
            if (Number(seq) < root.lastSeq)
                return; // arrived late
            root.lastSeq = Number(seq);
            if (action === "show") {
                root.mode = mode;
                root.index = Number(index);
                root.monitorName = monitor;
                root.entries = (addresses ?? "").split(",").filter(a => a !== "").map(root.lookup);
                root.shown = true;
            } else {
                root.shown = false;
            }
        }
    }

    PanelWindow {
        visible: root.shown && root.entries.length > 0
        screen: Quickshell.screens.find(s => s.name === root.monitorName) ?? null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "switcher"
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: Math.min((screen?.width ?? 2560) - 80, row.implicitWidth + 32)
        implicitHeight: row.implicitHeight + 32
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Config.radiusPanel + 6
            color: Config.glassMenu
            border.color: Config.border

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 8

                Repeater {
                    model: root.entries

                    Rectangle {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool selected: index + 1 === root.index

                        width: root.mode === "apps" ? 112 : 150
                        height: root.mode === "apps" ? 124 : 130
                        radius: Config.radiusTile
                        color: selected ? Config.hover : "transparent"
                        border.color: selected ? Config.border : "transparent"

                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            size: root.mode === "apps" ? 80 : 64
                            entry: cell.modelData.entry
                            appId: cell.modelData.appId
                        }
                        Text {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            x: 6
                            width: parent.width - 12
                            horizontalAlignment: Text.AlignHCenter
                            // ⌘Tab: app name under the selected icon; ⌥Tab: every window title
                            visible: root.mode === "windows" || cell.selected
                            text: root.mode === "apps" ? (cell.modelData.entry?.name ?? cell.modelData.appId) : cell.modelData.title
                            elide: Text.ElideRight
                            maximumLineCount: root.mode === "apps" ? 1 : 2
                            wrapMode: Text.Wrap
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Hyprland.dispatch(`macos.switcher_pick(${cell.index + 1})`)
                        }
                    }
                }
            }
        }
    }
}
