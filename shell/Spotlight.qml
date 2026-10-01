import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import "calc.js" as Calc
import "settings-index.js" as SettingsIndex

// ⌘Space, like Spotlight on a Mac: apps, a calculation or unit conversion ("12*7",
// "5 km in m" – Enter copies the result), System Settings pages ("WLAN", "Zeitzone") and
// files (the desktop's search index, localsearch).
//   ↑/↓ choose, Enter opens, Esc or a click outside closes.
// Opened by Hyprland via:  qs ipc call spotlight toggle
PanelWindow {
    id: root

    property string query: ""
    property int selected: 0

    readonly property var apps: {
        const q = query.trim().toLowerCase();
        if (q === "")
            return [];
        const scored = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay)
                continue;
            const name = e.name.toLowerCase();
            let score = 0;
            if (name.startsWith(q)) score = 100;
            else if (name.split(/[\s-]/).some(w => w.startsWith(q))) score = 80;
            else if (name.includes(q)) score = 60;
            else if ((e.genericName ?? "").toLowerCase().includes(q)) score = 40;
            else if ((e.keywords ?? "").toString().toLowerCase().includes(q)) score = 30;
            else if ((e.comment ?? "").toLowerCase().includes(q)) score = 10;
            if (score > 0)
                scored.push({ entry: e, score: score - name.length / 100 });
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.slice(0, 6).map(s => s.entry);
    }
    readonly property var calculation: Calc.evaluate(query) ?? Calc.convert(query)

    // files from the search index, a moment after typing stops
    property var files: []
    onQueryChanged: fileSearch.restart()
    Timer {
        id: fileSearch
        interval: 180
        onTriggered: {
            const words = root.query.trim().split(/\s+/).filter(w => w !== "");
            if (root.query.trim().length < 3 || root.calculation) {
                root.files = [];
                return;
            }
            finder.command = ["localsearch", "search", "-f", "--limit=6"].concat(words);
            finder.running = true;
        }
    }
    Process {
        id: finder
        stdout: StdioCollector {
            onStreamFinished: root.files = text.split("\n").filter(l => l.startsWith("file://"))
                .map(u => decodeURIComponent(u.slice(7)))
        }
    }
    function fileGlyph(path) {
        const ext = (path.match(/\.([a-z0-9]+)$/i)?.[1] ?? "").toLowerCase();
        if (ext === "") return "\u{f024b}"; // folder
        if (ext === "pdf") return "\u{f0226}";
        if (["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp", "tiff"].includes(ext)) return "\u{f021f}";
        if (["mp3", "flac", "ogg", "wav", "m4a", "opus"].includes(ext)) return "\u{f0223}";
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(ext)) return "\u{f022b}";
        if (["zip", "tar", "gz", "xz", "7z", "rar", "zst"].includes(ext)) return "\u{f0227}";
        if (["doc", "docx", "odt", "txt", "md", "rtf"].includes(ext)) return "\u{f0219}";
        if (["xls", "xlsx", "ods", "csv"].includes(ext)) return "\u{f021b}";
        return "\u{f0214}";
    }

    // Every row: a section header or a result { kind, title, subtitle, entry | glyph, colour, open() }
    readonly property var rows: {
        const list = [];
        const section = (title, items) => {
            if (items.length === 0)
                return;
            list.push({ header: title });
            for (const i of items)
                list.push(i);
        };
        if (calculation)
            section("Rechner", [{ kind: "calc", title: "= " + calculation.text, subtitle: query.trim() + "  ·  ⏎ kopiert das Ergebnis",
                glyph: "\u{f00ec}", colour: "#ff9f0a", value: calculation.text }]);
        section("Programme", apps.map(e => ({ kind: "app", title: e.name, subtitle: e.genericName ?? "", entry: e })));
        section("Systemeinstellungen", SettingsIndex.search(query).map(e => ({ kind: "setting", title: e.title,
            subtitle: "Systemeinstellungen", glyph: "\uf013", colour: "#8e8e93", page: e.page })));
        section("Dateien", (calculation ? [] : files).map(f => ({ kind: "file", title: f.split("/").pop(),
            subtitle: f.replace(Quickshell.env("HOME"), "~").replace(/\/[^/]*$/, ""), glyph: fileGlyph(f), colour: "#0a84ff", path: f })));
        return list;
    }
    readonly property var picks: rows.map((r, i) => r.header ? -1 : i).filter(i => i >= 0)
    readonly property int current: picks.length > 0 ? picks[Math.min(selected, picks.length - 1)] : -1

    function open(row) {
        if (!row)
            return;
        hide();
        if (row.kind === "app")
            Apps.launch(row.entry);
        else if (row.kind === "calc") {
            Quickshell.execDetached(["wl-copy", row.value]);
            Banners.show({ key: "spotlight-copy", glyph: "\u{f00ec}", title: row.value, subtitle: "In die Zwischenablage kopiert" });
        } else if (row.kind === "setting")
            Quickshell.execDetached([Quickshell.shellPath("scripts/system-settings.sh"), row.page]);
        else if (row.kind === "file")
            Quickshell.execDetached(["xdg-open", row.path]);
    }

    function show() {
        query = "";
        selected = 0;
        visible = true;
        grab.active = true;
        input.forceActiveFocus();
    }
    function hide() {
        grab.active = false;
        visible = false;
    }

    IpcHandler {
        target: "spotlight"
        function toggle(): void {
            root.visible ? root.hide() : root.show();
        }
    }

    HyprlandFocusGrab {
        id: grab
        windows: [root]
        onCleared: root.hide()
    }

    visible: false
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "spotlight"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    margins.top: Math.round((screen?.height ?? 1440) * 0.22)
    implicitWidth: 680
    implicitHeight: panel.height
    color: "transparent"

    Glass {
        id: panel
        width: parent.width
        height: 56 + (root.rows.length > 0 ? list.height + 9 : 0)

        // Search field
        Item {
            id: field
            width: parent.width
            height: 56

            Text {
                id: glass
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: "" // magnifying glass
                font.family: Config.fontSymbols
                font.pixelSize: 20
                color: Config.textSecondary
            }

            TextInput {
                id: input
                anchors.left: glass.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.fontSans
                font.pixelSize: 24
                color: Config.text
                selectionColor: Config.accent
                clip: true
                onTextChanged: {
                    root.query = text;
                    root.selected = 0;
                }
                Keys.onEscapePressed: root.hide()
                Keys.onReturnPressed: root.open(root.rows[root.current])
                Keys.onEnterPressed: root.open(root.rows[root.current])
                Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
                Keys.onDownPressed: root.selected = Math.min(root.picks.length - 1, root.selected + 1)
                Keys.onTabPressed: root.selected = (root.selected + 1) % Math.max(1, root.picks.length)

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Spotlight-Suche"
                    font: input.font
                    color: Config.textSecondary
                }
            }
        }

        Rectangle {
            visible: root.rows.length > 0
            anchors.top: field.bottom
            width: parent.width
            height: 1
            color: Config.border
        }

        Column {
            id: list
            anchors.top: field.bottom
            anchors.topMargin: 5
            x: 6
            width: parent.width - 12

            Repeater {
                model: root.rows

                Item {
                    id: result
                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === root.current
                    width: list.width
                    height: modelData.header ? 24 : 40

                    // section header
                    Text {
                        visible: result.modelData.header !== undefined
                        x: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        text: result.modelData.header ?? ""
                        font.family: Config.fontSans
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Config.textSecondary
                    }

                    Rectangle {
                        visible: !result.modelData.header
                        anchors.fill: parent
                        radius: 8
                        color: result.chosen ? Config.accent : "transparent"

                        AppIcon {
                            id: resultIcon
                            visible: result.modelData.kind === "app"
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            size: 32
                            entry: result.modelData.kind === "app" ? result.modelData.entry : null
                        }
                        GlyphTile {
                            visible: result.modelData.kind !== "app"
                            anchors.centerIn: resultIcon
                            size: 26
                            glyph: result.modelData.glyph ?? ""
                            color: result.modelData.colour ?? "#8e8e93"
                        }
                        Text {
                            anchors.left: resultIcon.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: result.modelData.title
                                + (result.modelData.subtitle ? "  <font color='" + (result.chosen ? "#ccffffff" : Config.textSecondary) + "'>– " + result.modelData.subtitle + "</font>" : "")
                            textFormat: Text.StyledText
                            font.family: Config.fontSans
                            font.pixelSize: 15
                            color: result.chosen ? "white" : Config.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.selected = root.picks.indexOf(result.index)
                            onClicked: root.open(result.modelData)
                        }
                    }
                }
            }
        }
    }
}
