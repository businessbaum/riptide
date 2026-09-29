import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

Page {
    id: page
    title: "Erscheinungsbild"

    readonly property var hours: Array.from({ length: 24 }, (_, h) => ({ value: h, text: (h < 10 ? "0" : "") + h + ":00" }))
    // like macOS (its colours in dark mode)
    readonly property var accents: [
        { value: "#0a84ff", name: "Blau" }, { value: "#bf5af2", name: "Lila" }, { value: "#ff375f", name: "Rosa" },
        { value: "#ff453a", name: "Rot" }, { value: "#ff9f0a", name: "Orange" }, { value: "#ffd60a", name: "Gelb" },
        { value: "#32d74b", name: "Grün" }, { value: "#8e8e93", name: "Graphit" }
    ]
    property var window

    // Pictures in ~/Bilder/Hintergründe and the system's backgrounds
    property var images: []
    Process {
        running: true
        command: ["sh", "-c", "find \"$HOME/Bilder/Hintergründe\" /usr/share/backgrounds -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null | sort"]
        stdout: StdioCollector {
            onStreamFinished: page.images = text.split("\n").filter(l => l !== "")
        }
    }

    Group {
        title: "Darstellung"
        SettingRow {
            first: true
            title: "Modus"
            subtitle: "Gilt für Menüleiste, Dock, Fenster und alle Programme"
            Choice {
                window: page.window
                options: [{ value: "light", text: "Hell" }, { value: "dark", text: "Dunkel" }, { value: "auto", text: "Automatisch" }]
                current: Config.settings.appearance?.auto === true ? "auto" : Config.mode
                // (automatic: the shell switches the mode itself, AutoAppearance.qml)
                onPicked: v => Config.updateSettings(s => {
                    s.appearance = s.appearance ?? {};
                    s.appearance.auto = v === "auto";
                    if (v !== "auto")
                        s.appearance.mode = v;
                })
            }
        }
        SettingRow {
            visible: Config.settings.appearance?.auto === true
            title: "Hell ab"
            subtitle: "Danach dunkel ab der zweiten Uhrzeit"
            Row {
                spacing: 8
                Choice {
                    window: page.window
                    options: page.hours
                    current: Config.settings.appearance?.light_from ?? 7
                    onPicked: v => Store.set("appearance", "light_from", v)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "dunkel ab"
                    font.family: Config.fontSans
                    font.pixelSize: 12
                    color: Config.textSecondary
                }
                Choice {
                    window: page.window
                    options: page.hours
                    current: Config.settings.appearance?.dark_from ?? 19
                    onPicked: v => Store.set("appearance", "dark_from", v)
                }
            }
        }
        SettingRow {
            title: "Akzentfarbe"
            subtitle: page.accents.find(a => a.value === (Config.settings.appearance?.accent ?? "#0a84ff"))?.name ?? ""
            Row {
                spacing: 8
                Repeater {
                    model: page.accents
                    Rectangle {
                        required property var modelData
                        readonly property bool chosen: (Config.settings.appearance?.accent ?? "#0a84ff") === modelData.value
                        width: 20
                        height: 20
                        radius: 10
                        color: modelData.value
                        border.width: chosen ? 2 : 1
                        border.color: chosen ? Config.text : "#33000000"
                        Rectangle {
                            visible: parent.chosen
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            // blue is the theme's own: no override
                            onClicked: Config.updateSettings(s => {
                                s.appearance = s.appearance ?? {};
                                if (modelData.value === "#0a84ff")
                                    delete s.appearance.accent;
                                else
                                    s.appearance.accent = modelData.value;
                            })
                        }
                    }
                }
            }
        }
        SettingRow {
            title: "Transparenz der Menüleiste"
            subtitle: "Links deckend, rechts durchsichtig"
            Slider {
                width: 220
                from: 0
                to: 100
                stepSize: 5
                showValue: true
                unit: " %"
                value: Math.round((1 - Config.menubar.a) * 100)
                onMoved: v => Store.set("appearance", "menubar_opacity", Math.round(100 - v) / 100)
            }
        }
        SettingRow {
            title: "Menüs und Panels mit Unschärfe"
            subtitle: "Kontrollzentrum, Mitteilungen und die Menüs der Menüleiste zeigen den Hintergrund verschwommen – gut lesbar auch über hellen Fenstern"
            Toggle {
                checked: Config.frostedMenus
                onToggled: on => Store.set("appearance", "frosted_menus", on)
            }
        }
        SettingRow {
            title: "Glaseffekt von Hyprland (Menüleiste, Dock)"
            subtitle: "Derzeit mit NVIDIA fehlerhaft (Pixelblöcke) – nach Updates wieder ausprobieren."
            Toggle {
                checked: Config.blur
                onToggled: on => Store.set("appearance", "blur", on, true)
            }
        }
    }

    Group {
        title: "Schreibtischhintergrund"
        description: "Eigene Bilder in den Ordner Bilder/Hintergründe legen, sie erscheinen dann hier."

        GridLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            columns: 4
            columnSpacing: 10
            rowSpacing: 10

            Repeater {
                model: [""].concat(page.images)

                Rectangle {
                    id: tile
                    required property string modelData
                    readonly property bool selected: (Config.settings.appearance?.wallpaper ?? "") === modelData
                    Layout.preferredWidth: 128
                    Layout.preferredHeight: 80
                    radius: 8
                    color: "transparent"
                    border.color: selected ? Config.accent : Config.border
                    border.width: selected ? 3 : 1
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 6
                        visible: tile.modelData === ""
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Config.dark ? "#1b2a4a" : "#8fb3e6" }
                            GradientStop { position: 0.55; color: Config.dark ? "#3b2f63" : "#c4b2e8" }
                            GradientStop { position: 1.0; color: Config.dark ? "#5c2a4f" : "#f0c2d4" }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "Verlauf"
                            font.family: Config.fontSans
                            font.pixelSize: 11
                            color: "white"
                        }
                    }
                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        visible: tile.modelData !== ""
                        source: tile.modelData !== "" ? "file://" + tile.modelData : ""
                        sourceSize.width: 256
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Config.updateSettings(s => {
                            s.appearance = s.appearance ?? {};
                            if (tile.modelData === "")
                                delete s.appearance.wallpaper;
                            else
                                s.appearance.wallpaper = tile.modelData;
                        })
                    }
                }
            }
        }
    }
}
