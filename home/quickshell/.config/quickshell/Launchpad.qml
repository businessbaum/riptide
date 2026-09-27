import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Launchpad: every app as a grid over the blurred, darkened desktop, like on a Mac.
// Opens from the dock (pinned item "launchpad") or  qs ipc call launchpad toggle.
//   Drag an app onto another: a folder forms (in its place); onto a folder: it joins.
//   Drag between icons: it moves there, the others make room – the order is yours; new
//   apps are put in alphabetically once. In an open folder the name can be changed; an
//   app dragged out of it leaves the folder.
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
    // Where each app and folder is: the order you arranged (settings.json →
    // launchpad.order: "app:<id>" / "folder:<id>"). Something new is put in once at its
    // alphabetical place among the others and stays there; nothing is sorted again.
    readonly property var order: Config.settings.launchpad?.order ?? []
    function keyOf(item) {
        return item.kind === "folder" ? "folder:" + item.fid : "app:" + item.id;
    }
    readonly property var arranged: {
        const app = e => ({ kind: "app", id: Apps.plainId(e.id), entry: e });
        const grouped = new Set();
        for (const f of folders)
            for (const a of f.apps)
                grouped.add(a);
        const list = folders.map((f, i) => ({ kind: "folder", index: i, fid: f.id ?? f.name, name: f.name, entries: f.apps.map(entryOf).filter(e => e) }))
            .filter(f => f.entries.length > 0)
            .concat(entries.filter(e => !grouped.has(Apps.plainId(e.id))).map(app));
        const pos = new Map(order.map((k, i) => [k, i]));
        const placed = list.filter(it => pos.has(keyOf(it))).sort((a, b) => pos.get(keyOf(a)) - pos.get(keyOf(b)));
        const fresh = list.filter(it => !pos.has(keyOf(it))).sort((a, b) => nameOf(a).localeCompare(nameOf(b), "de"));
        for (const it of fresh) {
            const at = placed.findIndex(p => nameOf(p).localeCompare(nameOf(it), "de") > 0);
            placed.splice(at < 0 ? placed.length : at, 0, it);
        }
        return placed;
    }
    // new ones got their place: keep it from now on
    onArrangedChanged: if (arranged.some(it => !order.includes(keyOf(it)))) Qt.callLater(saveOrder)
    function saveOrder(keys) {
        const list = keys ?? arranged.map(keyOf);
        Config.updateSettings(s => {
            s.launchpad = s.launchpad ?? {};
            s.launchpad.order = list;
        });
    }
    readonly property var items: {
        const q = query.trim().toLowerCase();
        if (q === "")
            return arranged;
        // searching looks into folders too, alphabetically
        return entries.filter(e => e.name.toLowerCase().includes(q) || (e.genericName ?? "").toLowerCase().includes(q))
            .map(e => ({ kind: "app", id: Apps.plainId(e.id), entry: e }))
            .sort((a, b) => nameOf(a).localeCompare(nameOf(b), "de"));
    }

    function changeFolders(change) {
        Config.updateSettings(s => {
            s.launchpad = s.launchpad ?? {};
            const list = JSON.parse(JSON.stringify(s.launchpad.folders ?? []));
            const order = (s.launchpad.order ?? arranged.map(keyOf)).slice();
            change(list, order);
            for (const f of list)
                f.id = f.id ?? f.name; // (older folders had none; the name was their key)
            s.launchpad.folders = list.filter(f => f.apps.length > 0); // an empty folder goes
            s.launchpad.order = order;
        });
    }
    function newFolderId() {
        return "f" + Date.now().toString(36);
    }
    function replaceKey(order, key, keys) {
        const at = order.indexOf(key);
        if (at >= 0)
            order.splice(at, 1, ...keys);
    }
    function leaveFolders(list, id) {
        for (const f of list)
            f.apps = f.apps.filter(a => a !== id);
    }
    // A name for a new folder from what both apps are (their main category), else "Ordner"
    // (not "folderName": that is the id of the name field below, and an id hides a function)
    function nameForFolder(a, b) {
        const names = [["AudioVideo", "Audio & Video"], ["Office", "Büro"], ["Graphics", "Grafik & Foto"],
                       ["Network", "Internet"], ["Game", "Spiele"], ["Development", "Entwicklung"],
                       ["Education", "Bildung"], ["Utility", "Werkzeuge"], ["System", "System"], ["Settings", "System"]];
        const cats = e => {
            const c = e?.categories ?? [];
            return typeof c === "string" ? c.split(";") : Array.from(c); // a list in Quickshell
        };
        const common = names.find(([key]) => cats(a).includes(key) && cats(b).includes(key));
        return common ? common[1] : "Ordner";
    }
    // the new folder takes the place of the app it was dropped on
    function makeFolder(targetId, id) {
        const name = nameForFolder(entryOf(targetId), entryOf(id));
        const fid = newFolderId();
        changeFolders((list, order) => {
            leaveFolders(list, id);
            leaveFolders(list, targetId);
            list.push({ id: fid, name: name, apps: [targetId, id] });
            replaceKey(order, "app:" + targetId, ["folder:" + fid]);
            replaceKey(order, "app:" + id, []);
        });
    }
    function joinFolder(index, id) {
        changeFolders((list, order) => {
            leaveFolders(list, id);
            if (list[index])
                list[index].apps.push(id);
            replaceKey(order, "app:" + id, []);
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
    // its apps take the folder's place
    function dissolveFolder(index) {
        changeFolders((list, order) => {
            const f = list[index];
            if (!f)
                return;
            list.splice(index, 1);
            replaceKey(order, "folder:" + (f.id ?? f.name), f.apps.map(a => "app:" + a));
        });
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
    property int dragIndex: -1   // where the dragged tile was, while arranging
    property int dropIndex: -1   // where it would go: the tiles in between make room
    // Making room waits until the pointer rests between icons a moment, like on a Mac –
    // right away, icons slid away under the pointer and a folder could not be made
    property int pendingDrop: -1
    Timer {
        id: makeRoom
        interval: 200
        onTriggered: if (root.arranging) root.dropIndex = root.pendingDrop
    }

    // Arranging: the grid (not an open folder, not a search) in your own order
    readonly property bool arranging: dragIndex >= 0
    // Where tile i is shown while the others make room for the dragged one
    function visualIndex(i) {
        const d = dragIndex, h = dropIndex;
        if (d < 0 || h < 0 || i === d)
            return i;
        if (d < h && i > d && i <= h)
            return i - 1;
        if (h < d && i >= h && i < d)
            return i + 1;
        return i;
    }

    function startDrag(item, fromFolder, p) {
        dragItem = item;
        dragFromFolder = fromFolder;
        dragAt = p;
        dragIndex = fromFolder || query.trim() !== "" ? -1 : items.findIndex(i => keyOf(i) === keyOf(item));
        dropIndex = -1;
    }
    function moveDrag(p) {
        dragAt = p;
        targetIndex = -1;
        if (dragFromFolder && openFolder >= 0)
            return; // inside a folder only "out" means something
        const g = grid.mapFromItem(root.contentItem, p.x, p.y);
        const col = Math.floor(g.x / grid.cellWidth);
        const row = Math.floor((g.y + grid.contentY) / grid.cellHeight);
        if (col < 0 || col >= grid.columns || g.y < 0 || items.length === 0)
            return;
        const cell = Math.min(row * grid.columns + col, items.length - 1);
        // the tile shown in that cell now (others may have moved aside)
        const shown = items.findIndex((_, i) => visualIndex(i) === cell);
        const cx = col * grid.cellWidth + grid.cellWidth / 2;
        const cy = row * grid.cellHeight + 52 - grid.contentY;
        const ontoTile = shown >= 0 && shown !== dragIndex && keyOf(items[shown]) !== keyOf(dragItem)
            && Math.hypot(g.x - cx, g.y - cy) < 40;
        if (ontoTile && dragItem.kind === "app") {
            targetIndex = shown; // right onto an icon: a folder forms (or the app joins it)
            makeRoom.stop();
            pendingDrop = -1;
        } else if (arranging && !ontoTile && cell !== dropIndex && cell !== pendingDrop) {
            pendingDrop = cell;  // between icons: make room there, if the pointer stays
            makeRoom.restart();
        }
    }
    function endDrag() {
        const item = dragItem, target = targetIndex >= 0 ? items[targetIndex] : null;
        try {
            if (dragFromFolder && openFolder >= 0) {
                const inside = folderPanel.contains(folderPanel.mapFromItem(root.contentItem, dragAt.x, dragAt.y));
                if (!inside)
                    leaveFolder(item.id);
            } else if (target && target.kind === "folder") {
                joinFolder(target.index, item.id);
            } else if (target && target.kind === "app") {
                makeFolder(target.id, item.id);
            } else if (arranging && dropIndex >= 0 && dropIndex !== dragIndex) {
                const keys = arranged.map(keyOf);
                const [key] = keys.splice(dragIndex, 1);
                keys.splice(dropIndex, 0, key);
                saveOrder(keys);
            }
        } finally {
            // (always: an error must not leave the icon hanging under the pointer)
            dragItem = null;
            targetIndex = -1;
            dragIndex = -1;
            dropIndex = -1;
            pendingDrop = -1;
            makeRoom.stop();
        }
    }

    // ---------------------------------------------------------------- right click

    property var menuItem: null
    function openMenu(item, at) {
        // (closed first: an open menu does not move to a new anchor)
        menu.close();
        menuItem = item;
        menu.anchorItem = at;
        Qt.callLater(menu.open);
    }
    MenuPopup {
        id: menu
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
                // (by key: modelData of an array model is a copy, never the dragged object itself)
                lifted: root.dragItem !== null && root.keyOf(root.dragItem) === root.keyOf(modelData)
                // making room for the dragged tile
                readonly property int shownAt: root.visualIndex(index)
                offsetX: ((shownAt % grid.columns) - (index % grid.columns)) * grid.cellWidth
                offsetY: (Math.floor(shownAt / grid.columns) - Math.floor(index / grid.columns)) * grid.cellHeight
                onClicked: root.activate(modelData)
                onMenu: at => root.openMenu(modelData, at)
            }
        }

        // While a folder is open, a click anywhere around it closes it (the apps behind
        // it would otherwise take the click)
        MouseArea {
            anchors.fill: parent
            visible: root.folder !== null
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.openFolder = -1
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

    // While the menu is open, a click anywhere closes it – and still reaches what is under
    // it, so right-clicking another app opens that app's menu (the menu's focus grab
    // counts all of Launchpad as its own, so it would not close by itself)
    MouseArea {
        anchors.fill: parent
        z: 100
        visible: menu.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            menu.close();
            mouse.accepted = false;
        }
    }

    // The app or folder being dragged, under the pointer (its icon, without the name)
    LaunchpadCell {
        visible: root.dragItem !== null
        enabled: false
        showName: false
        width: 170
        height: 150
        x: root.dragAt.x - width / 2
        y: root.dragAt.y - 52 // (the icon's middle is 52 px below the tile's top)
        item: root.dragItem
        launchpad: root
        opacity: 0.9
    }
}
