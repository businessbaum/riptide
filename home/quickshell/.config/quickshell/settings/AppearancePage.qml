import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

Page {
    id: page
    title: "Erscheinungsbild"
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
                options: [{ value: "light", text: "Hell" }, { value: "dark", text: "Dunkel" }]
                current: Config.mode
                onPicked: v => Store.set("appearance", "mode", v)
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
