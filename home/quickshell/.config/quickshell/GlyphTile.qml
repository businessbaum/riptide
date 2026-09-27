import QtQuick

// A symbol on a coloured rounded square, like the icons in macOS System Settings.
// The symbols of the font sit differently in their boxes and are drawn in different
// sizes: each one is measured (its drawn outline) and brought to one common size,
// centred on whole pixels. So every tile looks alike without tuning by hand.
Rectangle {
    id: root

    property string glyph: ""
    property int size: 20
    property real glyphScale: 1  // optical fine-tuning of a single symbol, rarely needed

    width: size
    height: size
    radius: Math.round(size / 4)
    color: "#8e8e93"

    // the outline at a large size gives the scale: the longer side fills 60 % of the tile
    TextMetrics {
        id: probe
        font.family: Config.fontSymbols
        font.pixelSize: 100
        text: root.glyph
    }
    readonly property real longest: Math.max(probe.tightBoundingRect.width, probe.tightBoundingRect.height)
    readonly property int pixelSize: longest > 0 ? Math.round(size * 0.6 * glyphScale * 100 / longest)
                                                 : Math.round(size * 0.55 * glyphScale)
    // the outline at the size drawn: the large one scaled down (the font rounds the
    // outline of small sizes to whole pixels, a pixel too generous)
    readonly property real k: pixelSize / 100
    readonly property rect ink: Qt.rect(probe.tightBoundingRect.x * k, probe.tightBoundingRect.y * k,
                                        probe.tightBoundingRect.width * k, probe.tightBoundingRect.height * k)

    Text {
        x: (root.size - root.ink.width) / 2 - root.ink.x
        y: (root.size - root.ink.height) / 2 - root.ink.y - baselineOffset
        text: root.glyph
        font.family: Config.fontSymbols
        font.pixelSize: root.pixelSize
        color: "white"
    }
}
