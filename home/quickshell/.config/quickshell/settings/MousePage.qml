import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

Page {
    id: page
    title: "Maus"
    property var window

    Group {
        SettingRow {
            first: true
            title: "Natürliches Scrollen"
            subtitle: "Der Inhalt folgt der Bewegung wie auf einem Touchscreen"
            Toggle {
                checked: Store.get("mouse", "natural_scroll", false)
                onToggled: on => Store.set("mouse", "natural_scroll", on, true)
            }
        }
        SettingRow {
            title: "Zeigergeschwindigkeit"
            Slider {
                width: 260
                from: -100
                to: 100
                stepSize: 5
                showValue: true
                value: Math.round(Store.get("mouse", "speed", 0) * 100)
                onMoved: v => Store.set("mouse", "speed", v / 100, true)
            }
        }
        SettingRow {
            title: "Zeigergröße"
            Choice {
                window: page.window
                options: [{ value: 18, text: "Klein" }, { value: 22, text: "Normal" }, { value: 28, text: "Groß" }, { value: 36, text: "Sehr groß" }]
                current: Store.get("mouse", "cursor_size", 22)
                onPicked: v => {
                    Store.set("mouse", "cursor_size", v, true);
                    Quickshell.execDetached(["hyprctl", "setcursor", "Adwaita", String(v)]);
                    Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", String(v)]);
                }
            }
        }
    }
}
