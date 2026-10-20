import QtQuick
import QtQuick.Shapes

// riptide's logo, where the Apple logo sits on a Mac (the menu bar's left end): a small fir
// tree, drawn on a 24×24 grid and filled with the text colour.
Item {
    id: root

    property real size: 16
    property color colour: Config.text

    implicitWidth: size
    implicitHeight: size

    Shape {
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        // filled and outlined in the same colour: the round joins soften the corners
        ShapePath {
            fillColor: root.colour
            strokeColor: root.colour
            strokeWidth: 1.4
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: "M12 2 L17.5 9.5 L15 9.5 L19.5 16 L13.4 16 L13.4 21.5 L10.6 21.5 L10.6 16 L4.5 16 L9 9.5 L6.5 9.5 Z"
            }
        }
    }
}
