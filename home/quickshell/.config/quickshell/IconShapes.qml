pragma Singleton

import Quickshell

// Shape of every app icon, measured once from its pixels (AppIcon.qml):
//   "square"  a (rounded) square (Zen, Claude)      → shown full size, corners rounded
//   "circle"  a round icon (Discord)                → shown full size, stays round
//   "tile"    any other outline (Finder, kitty)     → placed on the light tile
Singleton {
    property var shapes: ({})

    function set(source, shape) {
        const copy = Object.assign({}, shapes);
        copy[source] = shape;
        shapes = copy;
    }

    // From the alpha channel of a 64×64 drawing (RGBA bytes): { shape, scale }.
    // scale enlarges the icon so its shape fills the whole tile (icons in Apple's style
    // leave a transparent margin around their rounded square).
    function classify(data, size) {
        let opaque = 0, minX = size, minY = size, maxX = -1, maxY = -1;
        for (let y = 0; y < size; y++) {
            for (let x = 0; x < size; x++) {
                if (data[(y * size + x) * 4 + 3] > 128) {
                    opaque++;
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        const w = maxX - minX + 1, h = maxY - minY + 1;
        const squareish = w >= size * 0.7 && h >= size * 0.7 && Math.abs(w - h) <= size * 0.06;
        if (!squareish)
            return { shape: "tile", scale: 1 };
        const fill = opaque / (w * h);
        const scale = size / Math.max(w, h);
        if (fill >= 0.86)
            return { shape: "square", scale: scale };
        if (fill >= 0.72)
            return { shape: "circle", scale: scale }; // a circle covers π/4 ≈ 78.5 % of its box
        return { shape: "tile", scale: 1 };
    }
}
