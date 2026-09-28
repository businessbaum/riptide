import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// What the lock screen shows on the screens that are not the main one (MainScreen.qml),
// below the clock: the weather, this month, what is playing – each one chosen in System
// Settings → Bildschirme (settings.json lockscreen.aside). Only to look at: nothing here
// can be clicked while the screen is locked. Shares the lock screen's look (white on the
// wallpaper, frosted cards).
Row {
    id: root

    readonly property var aside: Config.settings.lockscreen?.aside ?? ({})
    readonly property bool showWeather: aside.weather !== false && Weather.place !== null
    readonly property bool showCalendar: aside.calendar !== false
    readonly property var player: aside.media !== false
        ? (Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values.find(p => p.trackTitle) ?? null) : null
    readonly property string font: "Inter" // the login window's (LoginScreen.qml)

    spacing: 20

    // the weather is fetched only while a lock screen shows it
    property bool watching: false
    function follow() {
        if (showWeather !== watching) {
            Weather.watch(showWeather);
            watching = showWeather;
        }
    }
    onShowWeatherChanged: follow()
    Component.onCompleted: follow()
    Component.onDestruction: if (watching) Weather.watch(false)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component Card: Rectangle {
        default property alias content: inner.data
        width: 300
        height: inner.implicitHeight + 40
        radius: 22
        color: "#2effffff"
        border.color: "#40ffffff"
        Column {
            id: inner
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 10
        }
    }

    // ---------------------------------------------------------------- weather
    Card {
        id: weather
        visible: root.showWeather
        readonly property var now: Weather.current ? Weather.describe(Weather.current.code, Weather.current.day) : null

        Row {
            spacing: 14
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: weather.now?.glyph ?? "\u{f0590}"
                font.family: Config.fontSymbols
                font.pixelSize: 46
                color: "white"
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: Weather.current ? Math.round(Weather.current.temperature) + "°" : "–"
                    font.family: root.font
                    font.pixelSize: 40
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    text: Weather.current ? (weather.now?.text ?? "") : "Wetter wird geladen …"
                    font.family: root.font
                    font.pixelSize: 13
                    color: "#d9ffffff"
                }
            }
        }
        Text {
            width: parent.width
            text: Weather.place?.name ?? ""
            elide: Text.ElideRight
            font.family: root.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: "#e6ffffff"
        }
        Rectangle {
            visible: Weather.days.length > 1
            width: parent.width
            height: 1
            color: "#33ffffff"
        }
        Repeater {
            model: Weather.days.slice(1, 4)
            Item {
                required property var modelData
                width: parent.width
                height: 24
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: new Date(modelData.date + "T12:00").toLocaleDateString(Qt.locale("de_DE"), "dddd")
                    font.family: root.font
                    font.pixelSize: 13
                    color: "white"
                }
                Text {
                    x: parent.width * 0.5 - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.describe(modelData.code, true).glyph
                    font.family: Config.fontSymbols
                    font.pixelSize: 18
                    color: "white"
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(modelData.max) + "°  " + Math.round(modelData.min) + "°"
                    font.family: root.font
                    font.pixelSize: 13
                    color: "#d9ffffff"
                }
            }
        }
    }

    // ---------------------------------------------------------------- this month
    Card {
        id: month
        visible: root.showCalendar
        readonly property date today: clock.date
        readonly property int year: today.getFullYear()
        readonly property int monthIndex: today.getMonth()
        // Monday first; blanks before the 1st
        readonly property int lead: (new Date(year, monthIndex, 1).getDay() + 6) % 7
        readonly property int length: new Date(year, monthIndex + 1, 0).getDate()

        Text {
            text: month.today.toLocaleDateString(Qt.locale("de_DE"), "MMMM yyyy")
            font.family: root.font
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: "white"
        }
        Grid {
            columns: 7
            columnSpacing: 0
            rowSpacing: 2
            Repeater {
                model: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
                Text {
                    required property string modelData
                    width: 260 / 7
                    height: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.family: root.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: "#b3ffffff"
                }
            }
            Repeater {
                model: month.lead + month.length
                Item {
                    required property int index
                    readonly property int day: index - month.lead + 1
                    readonly property bool isToday: day === month.today.getDate()
                    width: 260 / 7
                    height: 30
                    Rectangle {
                        visible: parent.isToday
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: "white"
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: parent.day > 0
                        text: parent.day
                        font.family: root.font
                        font.pixelSize: 13
                        font.weight: parent.isToday ? Font.DemiBold : Font.Normal
                        color: parent.isToday ? "#1c1c1e" : "white"
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- now playing
    Card {
        visible: root.player !== null
        Row {
            spacing: 14
            Rectangle {
                width: 64
                height: 64
                radius: 10
                color: "#33ffffff"
                clip: true
                Image {
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !(root.player?.trackArtUrl)
                    text: "\u{f075a}" // music
                    font.family: Config.fontSymbols
                    font.pixelSize: 26
                    color: "white"
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: 300 - 40 - 64 - 14
                spacing: 2
                Text {
                    width: parent.width
                    text: root.player?.trackTitle || root.player?.identity || ""
                    elide: Text.ElideRight
                    font.family: root.font
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.player?.trackArtist ?? ""
                    elide: Text.ElideRight
                    font.family: root.font
                    font.pixelSize: 13
                    color: "#d9ffffff"
                }
                Text {
                    width: parent.width
                    text: (root.player?.isPlaying ? "Läuft gerade · " : "Pausiert · ") + (root.player?.identity ?? "")
                    elide: Text.ElideRight
                    font.family: root.font
                    font.pixelSize: 11
                    color: "#b3ffffff"
                }
            }
        }
    }
}
