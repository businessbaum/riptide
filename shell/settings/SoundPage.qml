import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs

Page {
    id: page
    title: "Ton"
    property var window

    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [page.sink, page.source]
    }

    Group {
        title: "Ausgabe"
        SettingRow {
            first: true
            title: "Gerät"
            Choice {
                window: page.window
                options: page.sinks.map(n => ({ value: n.id, text: n.description || n.nickname || n.name }))
                current: page.sink?.id
                onPicked: v => Pipewire.preferredDefaultAudioSink = page.sinks.find(n => n.id === v)
            }
        }
        SettingRow {
            title: "Lautstärke"
            Slider {
                width: 260
                from: 0
                to: 100
                stepSize: 5
                showValue: true
                unit: " %"
                value: Math.round((page.sink?.audio?.volume ?? 0) * 100)
                onMoved: v => page.sink.audio.volume = v / 100
            }
        }
        SettingRow {
            title: "Stumm"
            Toggle {
                checked: page.sink?.audio?.muted ?? false
                onToggled: on => page.sink.audio.muted = on
            }
        }
    }

    Group {
        title: "Eingabe"
        visible: page.sources.length > 0
        SettingRow {
            first: true
            title: "Gerät"
            Choice {
                window: page.window
                options: page.sources.map(n => ({ value: n.id, text: n.description || n.nickname || n.name }))
                current: page.source?.id
                onPicked: v => Pipewire.preferredDefaultAudioSource = page.sources.find(n => n.id === v)
            }
        }
        SettingRow {
            title: "Eingangslautstärke"
            Slider {
                width: 260
                from: 0
                to: 100
                stepSize: 5
                showValue: true
                unit: " %"
                value: Math.round((page.source?.audio?.volume ?? 0) * 100)
                onMoved: v => page.source.audio.volume = v / 100
            }
        }
    }

    Group {
        title: "Toneffekte"
        SettingRow {
            first: true
            title: "Toneffekte der Oberfläche"
            subtitle: "Zum Beispiel beim Bildschirmfoto und beim Leeren des Papierkorbs"
            Toggle {
                checked: Config.settings.sound?.ui_sounds !== false
                onToggled: on => Store.set("sound", "ui_sounds", on)
            }
        }
        SettingRow {
            title: "Rückmeldung bei Änderung der Lautstärke"
            subtitle: "Ein kurzer Ton, wenn du die Lautstärketasten drückst"
            Toggle {
                checked: Config.settings.sound?.volume_feedback === true
                onToggled: on => {
                    Store.set("sound", "volume_feedback", on);
                    if (on)
                        SystemSounds.play("audio-volume-change");
                }
            }
        }
    }
}
