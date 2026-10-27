pragma Singleton
import QtQuick
import Quickshell
import qs.config

// The shell's one accent, taken from the wallpaper.
//
// The accent marks what is active and nothing else: the current workspace,
// a toggle that is on, the chosen tab, the connected network. With a single
// fixed grey there was nothing to tell those apart from plain text; taking
// it from the wallpaper ties the shell to the picture it sits on.
//
// The work is one quantisation of a 64px thumbnail each time the wallpaper
// changes. Nothing polls and nothing runs between changes.
Singleton {
    id: root

    // Greys carry no identity, so a wallpaper that quantises to one keeps the
    // neutral accent rather than being given a colour it does not have.
    readonly property real minSaturation: 0.18
    readonly property real maxSaturation: 0.7

    // The accent is drawn as text and as thin rings on the dark glass as well
    // as a fill, so it has to read as text there: 4.5:1 against the
    // background, the WCAG AA bar for body text.
    readonly property real minContrast: 4.5

    readonly property string source: Wallpaper.wallpaperStill

    property color picked: Theme.neutralAccent

    // `to` is set here rather than bound: this handler runs before a binding
    // on `picked` would have caught up, and the fade went to the old colour.
    onPickedChanged: {
        fade.to = root.picked
        fade.restart()
    }

    ColorAnimation {
        id: fade
        target: Theme
        property: "color4"
        duration: Theme.durExtraLong
        easing.type: Easing.InOutCubic
    }

    ColorQuantizer {
        id: quantizer
        source: root.source.length > 0
            ? (root.source.indexOf("file://") === 0 ? root.source : "file://" + root.source)
            : ""
        depth: 3            // 2^3 colours, enough to find a dominant one
        rescaleSize: 64     // quantise a thumbnail, not a 1440p picture

        onColorsChanged: root.picked = root.pick(quantizer.colors)
    }

    function pick(colors) {
        if (!colors || colors.length === 0) return Theme.neutralAccent

        var best = null
        var bestScore = -1
        for (var i = 0; i < colors.length; i++) {
            var c = colors[i]
            if (c.hsvSaturation < root.minSaturation) continue
            // Vivid and not nearly black: a dark wallpaper's deep shadow is
            // the most common colour in it, and the least like an accent.
            var score = c.hsvSaturation * Math.max(c.hsvValue, 0.3)
            if (score > bestScore) {
                bestScore = score
                best = c
            }
        }
        if (best === null) return Theme.neutralAccent
        return root.legible(best.hsvHue, Math.min(best.hsvSaturation, root.maxSaturation))
    }

    // Brighten, then wash out, until the colour clears the contrast bar on the
    // background. Hue is never touched, so the colour stays the wallpaper's.
    function legible(hue, sat) {
        var val = 0.8
        var c = Qt.hsva(hue, sat, val, 1)
        for (var step = 0; step < 40 && Theme.contrast(c, Theme.background) < root.minContrast; step++) {
            if (val < 1) val = Math.min(1, val + 0.05)
            else sat = Math.max(0, sat - 0.05)
            c = Qt.hsva(hue, sat, val, 1)
        }
        return c
    }
}
