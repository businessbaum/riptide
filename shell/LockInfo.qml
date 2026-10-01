import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// What the lock screen shows on the screens that are not the main one (MainScreen.qml),
// below the clock: the weather (today, hour by hour, and the week), this month, what is playing – each one chosen in System
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
        // dark glass: white text stays readable on light parts of any wallpaper
        color: "#66101014"
        border.color: "#33ffffff"
        Column {
            id: inner
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 10
        }
    }

    // ---------------------------------------------------------------- weather: today
    // now, the day's range, rain and sun; then the next 12 hours
    Card {
        id: dayCard
        visible: root.showWeather
        width: 560
        readonly property var now: Weather.current ? Weather.describe(Weather.current.code, Weather.current.day) : null
        readonly property var day: Weather.days[0] ?? null
        // from this hour on (the forecast is fetched every 30 minutes)
        readonly property var nextHours: {
            const hour = Qt.formatDateTime(clock.date, "yyyy-MM-ddTHH:00");
            return Weather.hours.filter(h => h.time >= hour).slice(0, 12);
        }

        Item {
            width: parent.width
            height: 58
            Text {
                id: nowGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: dayCard.now?.glyph ?? "\u{f0590}"
                font.family: Config.fontSymbols
                font.pixelSize: 46
                color: "white"
            }
            Column {
                anchors.left: nowGlyph.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: Weather.current ? Math.round(Weather.current.temperature) + "°" : "–"
                    font.family: root.font
                    font.pixelSize: 38
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    text: Weather.current
                        ? (dayCard.now?.text ?? "") + " · gefühlt " + Math.round(Weather.current.feels) + "°"
                        : "Wetter wird geladen …"
                    font.family: root.font
                    font.pixelSize: 13
                    color: "#d9ffffff"
                }
            }
            Column {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.right: parent.right
                    text: Weather.place?.name ?? ""
                    font.family: root.font
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: "white"
                }
                Text {
                    anchors.right: parent.right
                    visible: dayCard.day !== null
                    text: dayCard.day ? `H: ${Math.round(dayCard.day.max)}°  T: ${Math.round(dayCard.day.min)}°` : ""
                    font.family: root.font
                    font.pixelSize: 13
                    color: "#d9ffffff"
                }
            }
        }
        Text {
            visible: dayCard.day !== null
            width: parent.width
            text: dayCard.day
                ? `Regenrisiko ${dayCard.day.rain} %  ·  Sonnenaufgang ${dayCard.day.sunrise.slice(11, 16)}  ·  Sonnenuntergang ${dayCard.day.sunset.slice(11, 16)}`
                : ""
            font.family: root.font
            font.pixelSize: 13
            color: "#d9ffffff"
        }
        Rectangle {
            visible: dayCard.nextHours.length > 0
            width: parent.width
            height: 1
            color: "#33ffffff"
        }
        Row {
            visible: dayCard.nextHours.length > 0
            Repeater {
                model: dayCard.nextHours
                Column {
                    required property var modelData
                    required property int index
                    width: (560 - 40) / 12
                    spacing: 5
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.index === 0 ? "Jetzt" : modelData.time.slice(11, 13)
                        font.family: root.font
                        font.pixelSize: 12
                        font.weight: parent.index === 0 ? Font.DemiBold : Font.Normal
                        color: "#d9ffffff"
                    }
                    // "Jetzt": the current values, the same as above (the hour's are from its start)
                    readonly property var shown: index === 0 && Weather.current
                        ? { code: Weather.current.code, day: Weather.current.day, temperature: Weather.current.temperature }
                        : modelData
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Weather.describe(parent.shown.code, parent.shown.day).glyph
                        font.family: Config.fontSymbols
                        font.pixelSize: 20
                        color: "white"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.rain >= 20 ? modelData.rain + " %" : " "
                        font.family: root.font
                        font.pixelSize: 10
                        color: "#9fd3ff"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(parent.shown.temperature) + "°"
                        font.family: root.font
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: "white"
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- weather: the week
    // seven days; the bar shows each day's range within the whole week's
    Card {
        id: week
        visible: root.showWeather && Weather.days.length > 0
        width: 340
        readonly property real low: Math.min.apply(null, Weather.days.map(d => d.min))
        readonly property real high: Math.max.apply(null, Weather.days.map(d => d.max))

        Text {
            text: "Diese Woche"
            font.family: root.font
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: "white"
        }
        Repeater {
            model: Weather.days
            Item {
                required property var modelData
                required property int index
                width: parent.width
                height: 28
                Text {
                    id: dayName
                    width: 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.index === 0 ? "Heute"
                        : new Date(modelData.date + "T12:00").toLocaleDateString(Qt.locale("de_DE"), "ddd").replace(".", "")
                    font.family: root.font
                    font.pixelSize: 13
                    font.weight: parent.index === 0 ? Font.DemiBold : Font.Normal
                    color: "white"
                }
                Text {
                    id: dayGlyph
                    anchors.left: dayName.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: Weather.describe(modelData.code, true).glyph
                    font.family: Config.fontSymbols
                    font.pixelSize: 18
                    color: "white"
                }
                Text {
                    id: dayRain
                    anchors.left: dayGlyph.right
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    text: modelData.rain >= 20 ? modelData.rain + " %" : ""
                    font.family: root.font
                    font.pixelSize: 11
                    color: "#9fd3ff"
                }
                Text {
                    id: dayMin
                    anchors.left: dayRain.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(modelData.min) + "°"
                    font.family: root.font
                    font.pixelSize: 13
                    color: "#b3ffffff"
                }
                Rectangle {
                    id: track
                    anchors.left: dayMin.right
                    anchors.leftMargin: 8
                    anchors.right: dayMax.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 5
                    radius: 2.5
                    color: "#26ffffff"
                    Rectangle {
                        readonly property real span: Math.max(1, week.high - week.low)
                        x: (modelData.min - week.low) / span * track.width
                        width: Math.max(height, (modelData.max - modelData.min) / span * track.width)
                        height: parent.height
                        radius: parent.radius
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#8fd3ff" }
                            GradientStop { position: 1; color: "#ffd479" }
                        }
                    }
                }
                Text {
                    id: dayMax
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(modelData.max) + "°"
                    font.family: root.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: "white"
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
