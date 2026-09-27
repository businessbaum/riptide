import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// "Bedienungshilfen", like on a Mac: less motion, more contrast, larger text in apps,
// zooming the screen. Hyprland reads settings.json "accessibility" (reload), the shell
// follows at once; GTK apps through gsettings (the portal passes it into sandboxes).
Page {
    id: page
    title: "Bedienungshilfen"
    property var window

    readonly property var a11y: Config.settings.accessibility ?? ({})

    Group {
        title: "Anzeige"
        SettingRow {
            first: true
            title: "Bewegung reduzieren"
            subtitle: "Fenster, Schreibtische und Mission Control blenden über, statt zu gleiten"
            Toggle {
                checked: page.a11y.reduce_motion === true
                onToggled: on => Store.set("accessibility", "reduce_motion", on, true)
            }
        }
        SettingRow {
            title: "Kontrast erhöhen"
            subtitle: "Kräftigere Ränder, fast undurchsichtige Menüs, kräftigere Nebentexte"
            Toggle {
                checked: page.a11y.contrast === true
                onToggled: on => {
                    Store.set("accessibility", "contrast", on, true);
                    Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.a11y.interface", "high-contrast", on ? "true" : "false"]);
                }
            }
        }
        SettingRow {
            title: "Textgröße in Apps"
            subtitle: "Für Programme wie Finder, Thunderbird und die meisten anderen"
            Choice {
                window: page.window
                options: [{ value: 1, text: "Normal" }, { value: 1.1, text: "Etwas größer" }, { value: 1.25, text: "Größer" },
                    { value: 1.5, text: "Sehr groß" }]
                current: page.a11y.text_scale ?? 1
                onPicked: v => {
                    Store.set("accessibility", "text_scale", v);
                    Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", String(v)]);
                }
            }
        }
    }

    Group {
        title: "Zoom"
        description: "Vergrößert den ganzen Bildschirm rund um den Mauszeiger."
        SettingRow {
            first: true
            title: "Mit Tastaturkurzbefehlen zoomen"
            subtitle: "⌥⌘8 ein und aus, ⌥⌘+ näher, ⌥⌘- weiter weg"
            Toggle {
                checked: page.a11y.zoom_keys === true
                onToggled: on => Store.set("accessibility", "zoom_keys", on, true)
            }
        }
    }
}
