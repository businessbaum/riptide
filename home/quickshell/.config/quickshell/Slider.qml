import QtQuick

// Slider like on a Mac, in two looks:
//   thin (default)  settings: a thin track, filled in the accent colour, and a white
//                   round knob with a fine edge and shadow – that is what you drag
//   bar             control centre: a thick rounded bar with a symbol (`icon`), filled
//                   white up to a round knob at its end; chosen by `icon` or `bar: true`
//   value in [from, to]; `stepSize` > 0 snaps; `showValue` prints the number (`unit`,
//   `decimals`), `percent` prints it as 0–100 %.
//   `moved(value)` fires while dragging or scrolling, never for outside changes.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0
    property bool showValue: false
    property bool percent: false
    property string unit: ""
    property int decimals: 0
    property string icon: ""       // Symbols Nerd Font glyph inside the bar (bar look)
    property bool bar: icon !== ""
    property int trackHeight: bar ? 24 : 4
    signal moved(real value)

    readonly property real fraction: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0
    readonly property int knob: bar ? trackHeight : 20
    readonly property bool shown: showValue || percent

    implicitWidth: 200
    implicitHeight: Math.max(knob, trackHeight) + 2

    function setFrom(x) {
        const usable = track.width - knob;
        let v = from + Math.max(0, Math.min(1, (x - knob / 2) / Math.max(1, usable))) * (to - from);
        if (stepSize > 0)
            v = Math.round((v - from) / stepSize) * stepSize + from;
        v = Math.max(from, Math.min(to, v));
        if (v !== value)
            moved(v);
    }

    Item {
        id: track
        anchors.left: parent.left
        anchors.right: number.visible ? number.left : parent.right
        anchors.rightMargin: number.visible ? 10 : 0
        anchors.verticalCenter: parent.verticalCenter
        height: root.implicitHeight

        readonly property real knobX: Math.round(root.fraction * (width - root.knob))

        // the track
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: root.trackHeight
            radius: height / 2
            color: root.bar ? Config.tile : (Config.dark ? "#4dffffff" : "#26000000")
            border.color: root.bar ? Config.border : "transparent"
        }
        // the filled part, up to the knob
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: root.bar ? track.knobX + root.knob : track.knobX + root.knob / 2
            height: root.trackHeight
            radius: height / 2
            color: root.bar ? (Config.dark ? "#e6ffffff" : "#ffffff") : Config.accent
        }
        Text {
            visible: root.icon !== ""
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.family: Config.fontSymbols
            font.pixelSize: 12
            color: "#8c000000"
        }
        // the knob: shadow, then the white circle with a fine edge
        Rectangle {
            x: track.knobX
            y: (track.height - height) / 2 + 1
            width: root.knob
            height: root.knob
            radius: width / 2
            color: "#40000000"
        }
        Rectangle {
            x: track.knobX
            anchors.verticalCenter: parent.verticalCenter
            width: root.knob
            height: root.knob
            radius: width / 2
            color: "white"
            border.width: 1
            border.color: mouse.pressed ? Config.accent : "#33000000"
            scale: mouse.pressed ? 1.08 : 1
            Behavior on scale {
                NumberAnimation { duration: 90 }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: e => root.setFrom(e.x)
            onPositionChanged: e => { if (pressed) root.setFrom(e.x); }
            onWheel: e => {
                const step = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 20;
                root.moved(Math.max(root.from, Math.min(root.to, root.value + (e.angleDelta.y > 0 ? step : -step))));
            }
        }
    }

    Text {
        id: number
        visible: root.shown
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.percent ? 38 : 48
        horizontalAlignment: Text.AlignRight
        text: root.percent ? Math.round(root.fraction * 100) + " %" : root.value.toFixed(root.decimals) + root.unit
        font.family: Config.fontSans
        font.pixelSize: 12
        font.features: { "tnum": 1 }
        color: Config.textSecondary
    }
}
