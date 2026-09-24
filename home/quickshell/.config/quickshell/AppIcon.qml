import QtQuick
import Quickshell
import Quickshell.Widgets

// An app icon in one common size for dock, Launchpad, Spotlight and ⌘Tab, like on macOS:
//   icons that fill a square (Zen, Claude) are shown full size with rounded corners,
//   round icons (Discord) stay round at the same size,
//   every other outline (Finder, kitty) sits on a light rounded tile.
// The shape is measured once from the icon's pixels (IconShapes.qml).
Item {
    id: root

    property var entry: null      // desktop entry (preferred)
    property string appId: ""     // window class, used when there is no entry
    property string source: ""    // explicit icon path/URL (overrides both)
    property int size: 64

    readonly property string src: source !== "" ? source : Apps.icon(entry, appId)
    readonly property var measured: IconShapes.shapes[src] ?? { shape: "tile", scale: 1 }
    readonly property string shape: measured.shape
    // Whole pixels only: the rounded clip renders through a texture, and half-pixel
    // positions would make the icon blurry.
    readonly property int inset: Math.round(size * 0.04)
    readonly property int inner: size - 2 * inset
    readonly property real radius: inner * 0.225

    implicitWidth: size
    implicitHeight: size

    // Soft shadow below the icon, in its shape
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.inset
        anchors.topMargin: root.inset + root.size * 0.03
        anchors.bottomMargin: root.inset - root.size * 0.03
        radius: root.shape === "circle" ? width / 2 : root.radius
        color: "#000000"
        opacity: 0.22
    }

    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: root.inset
        radius: root.shape === "circle" ? width / 2 : root.radius
        color: root.shape === "tile" ? "#f4f4f6" : "transparent"
        border.color: root.shape === "tile" ? "#1a000000" : "transparent"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            visible: root.shape === "tile"
            gradient: Gradient {
                GradientStop { position: 0; color: "#ffffff" }
                GradientStop { position: 1; color: "#e4e4e8" }
            }
        }

        IconImage {
            readonly property int px: root.shape === "tile" ? Math.round(root.inner * 0.76) : Math.round(root.inner * root.measured.scale)
            x: Math.round((root.inner - px) / 2)
            y: Math.round((root.inner - px) / 2)
            width: px
            height: px
            source: root.src
            asynchronous: true
        }
    }

    // Measure the icon's shape once (drawn invisibly, then its alpha channel is read)
    Loader {
        active: IconShapes.shapes[root.src] === undefined && root.src !== ""
        sourceComponent: Canvas {
            width: 64
            height: 64
            opacity: 0
            Component.onCompleted: loadImage(root.src)
            onImageLoaded: requestPaint()
            onPaint: {
                if (!isImageLoaded(root.src))
                    return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, 64, 64);
                ctx.drawImage(root.src, 0, 0, 64, 64);
                IconShapes.set(root.src, IconShapes.classify(ctx.getImageData(0, 0, 64, 64).data, 64));
            }
        }
    }
}
