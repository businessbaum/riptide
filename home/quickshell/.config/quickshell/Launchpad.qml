import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Launchpad: every app as a grid over the blurred, darkened desktop, like on a Mac.
// Opens from the dock (pinned item "launchpad") or  qs ipc call launchpad toggle.
//   Drag an app onto another: a folder forms; onto a folder: it joins. In an open folder
//   the name can be changed; an app dragged out of it leaves the folder.
//   Right click: open, keep in dock, leave the folder, uninstall (System Settings → Apps).
//   Esc, a click on the background or starting an app closes it.
// Folders are kept in settings.json → launchpad.folders: [{ name, apps: [desktop ids] }].
PanelWindow {
    id: root

    property string query: ""
    property real shown: 0 // 0 → 1 while opening (fade and zoom in), back while closing

    // ---------------------------------------------------------------- apps and folders

    readonly property var folders: Config.settings.launchpad?.folders ?? []
    readonly property var entries: DesktopEntries.applications.values.filter(e => !e.noDisplay)
    function entryOf(id) {
        return entries.find(e => Apps.plainId(e.id) === id) ?? null;
    }
    function nameOf(item) {
        return item.kind === "folder" ? item.name : item.entry.name;
    }
    readonly property var items: {
        const q = query.trim().toLowerCase();
        const app = e => ({ kind: "app", id: Apps.plainId(e.id), entry: e });
        let list;
        if (q !== "") { // searching looks into folders too
            list = entries.filter(e => e.name.toLowerCase().includes(q) || (e.genericName ?? "").toLowerCase().includes(q)).map(app);
        } else {
            const grouped = new Set();
            for (const f of folders)
                for (const a of f.apps)
                    grouped.add(a);
            list = folders.map((f, i) => ({ kind: "folder", index: i, name: f.name, entries: f.apps.map(entryOf).filter(e => e) }))
                .filter(f => f.entries.length > 0)
                .concat(entries.filter(e => !grouped.has(Apps.plainId(e.id))).map(app));
        }
        return list.sort((a, b) => nameOf(a).localeCompare(nameOf(b), "de"));
    }

    function changeFolders(change) {
        Config.updateSettings(s => {
            s.launchpad = s.launchpad ?? {};
            const list = JSON.parse(JSON.stringify(s.launchpad.folders ?? []));
            change(list);
            s.launchpad.folders = list.filter(f => f.apps.length > 0); // an empty folder goes
        });
    }
    function leaveFolders(list, id) {
        for (const f of list)
            f.apps = f.apps.filter(a => a !== id);
    }
    // A name for a new folder from what both apps are (their main category), else "Ordner"
    function folderName(a, b) {
        const names = [["AudioVideo", "Audio & Video"], ["Office", "Büro"], ["Graphics", "Grafik & Foto"],
                       ["Network", "Internet"], ["Game", "Spiele"], ["Development", "Entwicklung"],
                       ["Education", "Bildung"], ["Utility", "Werkzeuge"], ["System", "System"], ["Settings", "System"]];
        const cats = e => (e?.categories ?? "").split(";");
        const common = names.find(([key]) => cats(a).includes(key) && cats(b).includes(key));
        return common ? common[1] : "Ordner";
    }
    function makeFolder(targetId, id) {
        const name = folderName(entryOf(targetId), entryOf(id));
        changeFolders(list => {
            leaveFolders(list, id);
            leaveFolders(list, targetId);
            list.push({ name: name, apps: [targetId, id] });
        });
    }
    function joinFolder(index, id) {
        changeFolders(list => {
            leaveFolders(list, id);
            if (list[index])
                list[index].apps.push(id);
        });
    }
    function leaveFolder(id) {
        changeFolders(list => leaveFolders(list, id));
    }
    function renameFolder(index, name) {
        changeFolders(list => {
            if (list[index] && name.trim() !== "")
                list[index].name = name.trim();
        });
    }
    function dissolveFolder(index) {
        changeFolders(list => list.splice(index, 1));
    }

    // ---------------------------------------------------------------- open, close, start

    property int openFolder: -1 // index in `folders` of the folder shown on top
    readonly property var folder: openFolder >= 0 ? items.find(i => i.kind === "folder" && i.index === openFolder) ?? null : null
    onFolderChanged: if (openFolder >= 0 && !folder) openFolder = -1

    function show() {
        query = "";
        search.text = "";
        openFolder = -1;
        shown = 0;
        visible = true;
        backdrop.captureFrame(); // the desktop as it is now (this window is still transparent)
        appear.restart();
        search.forceActiveFocus();
    }
    function hide() {
        shown = 0;
        closing.restart();
    }
    function launch(entry) {
        hide();
        Apps.launch(entry);
    }
    function activate(item) {
        if (item.kind === "folder")
            openFolder = item.index;
        else
            launch(item.entry);
    }
    Timer {
        id: appear
        interval: 30 // one frame for the screenshot, then fade and zoom in
        onTriggered: root.shown = 1
    }
    Timer {
        id: closing
        interval: 170
        onTriggered: root.visible = false
    }
    Behavior on shown {
        NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
    }

    IpcHandler {
        target: "launchpad"
        function toggle(): void {
            root.visible && root.shown > 0 ? root.hide() : root.show();
        }
        // tests: open Launchpad with a folder open (index in launchpad.folders)
        function folder(index: int): void {
            root.show();
            root.openFolder = index;
        }
    }

    // ---------------------------------------------------------------- dragging

    property var dragItem: null
    property bool dragFromFolder: false
    property point dragAt
    property int targetIndex: -1 // index in `items` of the tile the app would join

    function startDrag(item, fromFolder, p) {
        dragItem = item;
        dragFromFolder = fromFolder;
        dragAt = p;
    }
    function moveDrag(p) {
        dragAt = p;
        targetIndex = -1;
        if (dragFromFolder && openFolder >= 0)
            return; // inside a folder only "out" means something
        const g = grid.mapFromItem(root.contentItem, p.x, p.y);
        const index = grid.indexAt(g.x + grid.contentX, g.y + grid.contentY);
        if (index < 0 || items[index] === undefined || items[index].id === dragItem.id)
            return;
        // only near the middle of an icon, so passing over it does nothing
        const cx = (index % grid.columns) * grid.cellWidth + grid.cellWidth / 2 - grid.contentX;
        const cy = Math.floor(index / grid.columns) * grid.cellHeight + 52 - grid.contentY;
        if (Math.hypot(g.x - cx, g.y - cy) < 52)
            targetIndex = index;
    }
    function endDrag() {
        const item = dragItem, target = targetIndex >= 0 ? items[targetIndex] : null;
        if (dragFromFolder && openFolder >= 0) {
            const inside = folderPanel.contains(folderPanel.mapFromItem(root.contentItem, dragAt.x, dragAt.y));
            if (!inside)
                leaveFolder(item.id);
        } else if (target && target.kind === "folder") {
            joinFolder(target.index, item.id);
        } else if (target && target.kind === "app") {
            makeFolder(target.id, item.id);
        }
        dragItem = null;
        targetIndex = -1;
    }

    // ---------------------------------------------------------------- right click

    property var menuItem: null
    function openMenu(item, at) {
        menuItem = item;
        menu.anchorItem = at;
        menu.open();
    }
    MenuPopup {
        id: menu
        keepOpenFor: [root]
        items: {
            const it = root.menuItem;
            if (!it)
                return [];
            if (it.kind === "folder")
                return [
                    { text: "Öffnen", action: () => root.openFolder = it.index },
                    { text: "Ordner auflösen", action: () => root.dissolveFolder(it.index) }
                ];
            const pinned = Apps.isPinned(it.entry);
            const list = [
                { text: "Öffnen", action: () => root.launch(it.entry) },
                { text: pinned ? "Aus dem Dock entfernen" : "Im Dock behalten", action: () => Apps.setPinned(it.entry, !pinned) }
            ];
            if (root.folders.some(f => f.apps.includes(it.id)))
                list.push({ text: "Aus dem Ordner entfernen", action: () => root.leaveFolder(it.id) });
            list.push({ separator: true });
            list.push({ text: "Deinstallieren …", action: () => {
                root.hide();
                Quickshell.execDetached([Quickshell.shellPath("scripts/system-settings.sh"), "apps/" + it.id]);
            } });
            return list;
        }
    }

    // ---------------------------------------------------------------- window

    visible: false
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "launchpad"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    // The desktop behind, blurred and darkened by us (the compositor's blur is off on NVIDIA)
    ScreencopyView {
        id: backdrop
        anchors.fill: parent
        captureSource: root.screen
        live: false
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: backdrop
        visible: backdrop.hasContent
        opacity: root.shown
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 64
        saturation: -0.2
        brightness: Config.dark ? -0.12 : 0.1
    }
    Rectangle {
        anchors.fill: parent
        opacity: root.shown
        color: Config.dark ? "#26000000" : "#26ffffff"
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.openFolder >= 0 ? root.openFolder = -1 : root.hide()
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: root.shown
        scale: 1.06 - 0.06 * root.shown
        Keys.onEscapePressed: root.openFolder >= 0 ? root.openFolder = -1 : root.hide()

        // Search field on top, like on a Mac
        Rectangle {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            y: 70
            width: 260
            height: 30
            radius: 8
            color: Config.tile
            border.color: Config.border

            Text {
                id: glass
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                font.family: Config.fontSymbols
                font.pixelSize: 12
                color: Config.textSecondary
            }
            TextInput {
                id: search
                anchors.left: glass.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.fontSans
                font.pixelSize: 14
                color: Config.text
                clip: true
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.openFolder >= 0 ? root.openFolder = -1 : root.hide()
                Keys.onReturnPressed: {
                    const first = root.items.find(i => i.kind === "app");
                    if (first)
                        root.launch(first.entry);
                }

                Text {
                    visible: search.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Suchen"
                    font: search.font
                    color: Config.textSecondary
                }
            }
        }

        GridView {
            id: grid
            anchors.top: field.bottom
            anchors.topMargin: 50
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 110
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property int columns: 7
            width: columns * cellWidth
            cellWidth: 170
            cellHeight: 150
            clip: true
            interactive: root.dragItem === null
            model: root.items
            opacity: root.openFolder >= 0 ? 0.35 : 1
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            FastScroll {
                view: grid
            }

            delegate: LaunchpadCell {
                required property var modelData
                required property int index
                width: grid.cellWidth
                height: grid.cellHeight
                item: modelData
                launchpad: root
                target: root.targetIndex === index
                lifted: root.dragItem !== null && root.dragItem === modelData
                onClicked: root.activate(modelData)
                onMenu: at => root.openMenu(modelData, at)
            }
        }

        // An open folder: its name (click to change) and its apps
        Glass {
            id: folderPanel
            visible: root.folder !== null
            anchors.centerIn: parent
            width: Math.min(4, root.folder?.entries.length ?? 1) * 170 + 40
            height: folderName.height + folderGrid.height + 60
            color: Config.dark ? "#d9303034" : "#e6f5f5f7"
            scale: visible ? 1 : 0.9
            Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            MouseArea {
                anchors.fill: parent // clicks on the panel stay in it
            }
            TextInput {
                id: folderName
                anchors.horizontalCenter: parent.horizontalCenter
                y: 20
                width: parent.width - 60
                horizontalAlignment: TextInput.AlignHCenter
                text: root.folder?.name ?? ""
                font.family: Config.fontSans
                font.pixelSize: 22
                font.weight: Font.DemiBold
                color: Config.text
                selectByMouse: true
                onEditingFinished: if (root.folder) root.renameFolder(root.folder.index, text)
                Keys.onEscapePressed: root.openFolder = -1
            }
            Grid {
                id: folderGrid
                anchors.horizontalCenter: parent.horizontalCenter
                y: folderName.y + folderName.height + 20
                columns: 4
                Repeater {
                    model: root.folder?.entries ?? []
                    LaunchpadCell {
                        required property var modelData
                        width: 170
                        height: 150
                        item: ({ kind: "app", id: Apps.plainId(modelData.id), entry: modelData })
                        launchpad: root
                        inFolder: true
                        lifted: root.dragItem !== null && root.dragItem.id === Apps.plainId(modelData.id)
                        onClicked: root.launch(modelData)
                        onMenu: at => root.openMenu(item, at)
                    }
                }
            }
        }
    }

    // The app being dragged, under the pointer
    AppIcon {
        visible: root.dragItem !== null
        x: root.dragAt.x - size / 2
        y: root.dragAt.y - size / 2
        size: 96
        entry: root.dragItem?.entry ?? null
        opacity: 0.9
    }
}
