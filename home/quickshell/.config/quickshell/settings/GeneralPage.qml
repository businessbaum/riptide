import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs

Page {
    id: page
    title: "Allgemein"

    // name|value lines from a small shell script
    property var info: []
    Process {
        running: true
        command: ["sh", "-c", [
            "echo \"Name|$(cat /proc/sys/kernel/hostname)\"",
            ". /etc/os-release; echo \"System|$PRETTY_NAME\"",
            "echo \"Prozessor|$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')\"",
            "g=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1); [ -n \"$g\" ] && echo \"Grafik|$g\"",
            "echo \"Arbeitsspeicher|$(awk '/MemTotal/ {printf \"%.0f GB\", $2/1024/1024}' /proc/meminfo)\"",
            "echo \"Kernel|$(uname -r)\"",
            "echo \"Speicher (System)|$(df -h --output=used,size / | tail -1 | awk '{sub(/G$/, \" GB\", $1); sub(/G$/, \" GB\", $2); print $1 \" von \" $2 \" belegt\"}')\"",
            "echo \"Pakete|$(pacman -Qq | wc -l)\""
        ].join("; ")]
        stdout: StdioCollector {
            onStreamFinished: page.info = text.split("\n").filter(l => l.includes("|")).map(l => l.split("|"))
        }
    }

    Group {
        title: "Über diesen Computer"
        Repeater {
            model: page.info
            SettingRow {
                required property var modelData
                required property int index
                first: index === 0
                title: modelData[0]
                Text {
                    text: modelData[1]
                    font.family: Config.fontSans
                    font.pixelSize: 13
                    color: Config.textSecondary
                }
            }
        }
    }
}
