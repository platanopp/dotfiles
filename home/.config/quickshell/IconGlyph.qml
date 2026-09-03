import QtQuick

// One icon glyph, sized by the box its ink actually fills.
//
// Setting font.pixelSize on a Text sets the em box, and the Material Design
// glyphs in a Nerd Font fill wildly different fractions of it: at the same
// pixel size the wifi fan inks 0.62 em, the battery 0.88 em. Asking for one
// "icon size" therefore still produced icons that disagreed by ~40% side by
// side. Measuring each glyph and dividing back down to Theme's reference box
// makes `size` mean the same thing for every icon, and any glyph added later
// corrects itself without a lookup table.
//
// The ink sits at the centre of the line box in this font (offset -0.0008 em,
// i.e. nothing), so ordinary vertical centring keeps corrected icons aligned
// with their neighbours; no baseline nudging is needed.
Text {
    id: root

    // Optical size, from Theme's icon scale rather than a raw number.
    property int size: Theme.iconMedium

    // Em fraction this glyph's ink covers, at its widest or tallest.
    readonly property real box: {
        var r = metrics.tightBoundingRect
        return Math.max(r.width, r.height) / 100
    }

    font.family: Theme.fontMono
    // An empty or missing glyph measures zero; fall back to the raw size
    // rather than dividing by it.
    font.pixelSize: box > 0.01 ? Math.round(size * (Theme.iconReferenceBox / box)) : size

    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    TextMetrics {
        id: metrics
        font.family: Theme.fontMono
        font.pixelSize: 100
        text: root.text
    }
}
