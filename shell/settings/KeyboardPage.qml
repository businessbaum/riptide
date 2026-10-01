import QtQuick
import QtQuick.Layouts
import qs
import "../shortcuts.js" as Shortcuts

Page {
    id: page
    title: "Tastatur"
    property var window

    Group {
        SettingRow {
            first: true
            title: "Tastaturbelegung"
            Choice {
                window: page.window
                options: [
                    { value: "de", text: "Deutsch" },
                    { value: "ch", text: "Deutsch (Schweiz)" },
                    { value: "at", text: "Deutsch (Österreich)" },
                    { value: "us", text: "Englisch (US)" },
                    { value: "gb", text: "Englisch (GB)" }
                ]
                current: Store.get("keyboard", "layout", "de")
                onPicked: v => Store.set("keyboard", "layout", v, true)
            }
        }
        SettingRow {
            title: "Mac-Kürzel mit ⌘"
            subtitle: "⌘C, ⌘V, ⌘Z … funktionieren in allen Programmen (⌘ = Windows-Taste)"
            Toggle {
                checked: Store.get("keyboard", "cmd_shortcuts", true)
                onToggled: on => Store.set("keyboard", "cmd_shortcuts", on, true)
            }
        }
    }

    Group {
        title: "Tastenwiederholung"
        SettingRow {
            first: true
            title: "Verzögerung bis zur Wiederholung"
            Slider {
                width: 260
                from: 150
                to: 1000
                stepSize: 50
                showValue: true
                unit: " ms"
                value: Store.get("keyboard", "repeat_delay", 600)
                onMoved: v => Store.set("keyboard", "repeat_delay", v, true)
            }
        }
        SettingRow {
            title: "Wiederholrate"
            Slider {
                width: 260
                from: 10
                to: 60
                stepSize: 5
                showValue: true
                unit: "/s"
                value: Store.get("keyboard", "repeat_rate", 25)
                onMoved: v => Store.set("keyboard", "repeat_rate", v, true)
            }
        }
    }

    // ---------------------------------------------------------------- shortcuts

    property string shortcutQuery: ""
    readonly property var shortcutGroups: Shortcuts.search(shortcutQuery)

    Group {
        title: "Tastaturkurzbefehle"
        description: "⌘ ist die Windows-Taste, ⌥ Alt, ⌃ Strg, ⇧ Umschalt."
        SettingRow {
            first: true
            title: ""
            Field {
                implicitWidth: 300
                placeholder: "Kurzbefehl suchen"
                input.onTextChanged: page.shortcutQuery = text
            }
        }
    }
    Repeater {
        model: page.shortcutGroups
        Group {
            id: shortcutGroup
            required property var modelData
            title: modelData.title
            Repeater {
                model: shortcutGroup.modelData.items
                SettingRow {
                    required property var modelData
                    required property int index
                    first: index === 0
                    title: modelData[1]
                    // the keys, like key caps
                    Rectangle {
                        width: keys.implicitWidth + 16
                        height: 24
                        radius: 6
                        color: Config.tile
                        border.color: Config.border
                        Text {
                            id: keys
                            anchors.centerIn: parent
                            text: modelData[0]
                            font.family: Config.fontSans
                            font.pixelSize: 12
                            color: Config.text
                        }
                    }
                }
            }
        }
    }
}
