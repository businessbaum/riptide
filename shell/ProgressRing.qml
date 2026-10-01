import QtQuick
import QtQuick.Shapes

// Progress circle like in the Mac App Store: a turning arc while the amount of work is
// unknown (downloading), a filling ring once it is known (value 0…1, or < 0 = unknown).
Item {
    id: root

    property real value: -1
    property color colour: Config.accent
    property real thickness: 2.5

    implicitWidth: 22
    implicitHeight: 22

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        rotation: root.value < 0 ? spin.angle : -90

        // track
        ShapePath {
            strokeColor: Config.tile
            strokeWidth: root.thickness
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - root.thickness
                radiusY: root.height / 2 - root.thickness
                startAngle: 0
                sweepAngle: 360
            }
        }
        // progress
        ShapePath {
            strokeColor: root.colour
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - root.thickness
                radiusY: root.height / 2 - root.thickness
                startAngle: 0
                sweepAngle: root.value < 0 ? 90 : Math.max(8, 360 * Math.min(1, root.value))
                Behavior on sweepAngle {
                    NumberAnimation { duration: 200 }
                }
            }
        }
    }

    // turning while unknown
    QtObject {
        id: spin
        property real angle: 0
    }
    NumberAnimation {
        target: spin
        property: "angle"
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: root.visible && root.value < 0
    }
}
