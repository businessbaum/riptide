import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Which app opens what: web links, e-mail links, folders, PDFs, pictures, music, videos,
// text and archives. Only apps that can open the kind of file are offered.
Page {
    id: page
    title: "Standard-Apps"
    property var window

    property var categories: []

    function load() {
        query.running = true;
    }
    Component.onCompleted: load()

    Process {
        id: query
        command: ["python3", Quickshell.shellPath("scripts/default-apps.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.categories = JSON.parse(text);
                } catch (e) {
                    page.categories = [];
                }
            }
        }
    }

    Process {
        id: setter
        onExited: page.load()
    }

    function appName(id) {
        const loaded = DesktopEntries.applications.values.length; // refresh when launchers are read
        return Apps.entryById(id)?.name ?? id.replace(/\.desktop$/, "");
    }

    Group {
        description: "Gilt für Doppelklicks im Finder, Links in Apps und Anhänge."

        Repeater {
            model: page.categories
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData.label
                Choice {
                    window: page.window
                    options: modelData.apps.map(a => ({ value: a, text: page.appName(a) }))
                    current: modelData.default
                    onPicked: v => {
                        setter.command = ["python3", Quickshell.shellPath("scripts/default-apps.py"), "set", modelData.key, v];
                        setter.running = true;
                    }
                }
            }
        }
    }
}
