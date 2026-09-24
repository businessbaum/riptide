import QtQuick

// Slider like in the macOS control centre / settings.
//   value in [from, to]; `stepSize` > 0 snaps; `showValue` prints the number.
//   `moved(value)` fires while dragging or scrolling, never for outside changes.
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0
    property bool showValue: false
    property string unit: ""
    property int decimals: 0
    property string icon: ""      // Symbols Nerd Font glyph on the left inside the track
    property int trackHeight: 22
    signal moved(real value)

    readonly property real fraction: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    implicitWidth: 200
    implicitHeight: trackHeight

    function setFrom(x) {
        let v = from + Math.max(0, Math.min(1, x / track.width)) * (to - from);
        if (stepSize > 0)
            v = Math.round((v - from) / stepSize) * stepSize + from;
        v = Math.max(from, Math.min(to, v));
        if (v !== value)
            moved(v);
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: number.visible ? number.left : parent.right
        anchors.rightMargin: number.visible ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        height: root.trackHeight
        radius: height / 2
        color: Config.tile
        border.color: Config.border
        clip: true

        Rectangle {
            width: Math.max(track.height, track.width * root.fraction)
            height: parent.height
            radius: height / 2
            color: Config.dark ? "#e6ffffff" : "#ffffff"
            border.color: Config.border
        }

        Text {
            visible: root.icon !== ""
            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.family: Config.fontSymbols
            font.pixelSize: 12
            color: "#80000000"
        }

        MouseArea {
            anchors.fill: parent
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
        visible: root.showValue
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        horizontalAlignment: Text.AlignRight
        text: root.value.toFixed(root.decimals) + root.unit
        font.family: Config.fontSans
        font.pixelSize: 12
        font.features: { "tnum": 1 }
        color: Config.textSecondary
    }
}
