import QtQuick
import qs.config

// One icon glyph, sized by the box its ink fills: Nerd Font Material glyphs fill the em box
// unevenly (wifi 0.62, battery 0.88), so each is measured and scaled to Theme's reference box. The
// ink is centred in the line box, so ordinary vertical centring aligns corrected icons.
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
