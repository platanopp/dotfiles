pragma Singleton
import QtQuick
import Quickshell

// Design tokens for the shell: one fixed palette plus a shared motion scale.
// Everything visual should read from here rather than hardcoding a hex.
Singleton {
    id: root

    // ── Palette ──────────────────────────────────────────────────────────
    property color background: "#101014"
    property color foreground: "#f2f2f2"

    property color color0: "#101014"
    property color color1: "#e06c75"
    property color color2: "#98c379"
    property color color3: "#e5c07b"
    property color color4: "#d8d8d8"
    property color color5: "#c678dd"
    property color color6: "#56b6c2"
    property color color7: "#f2f2f2"
    property color color8: "#5c6370"

    // ── Semantic tokens ──────────────────────────────────────────────────
    readonly property color accent: color4

    // Text drawn on top of an accent fill. Follows the accent's luminance, so
    // a dark wallpaper palette does not leave dark text on a dark pill.
    // Note: these must not be named onAccent/onSurface — QML reads any
    // `on<Capital>` identifier as a signal handler, not a property.
    readonly property color accentText: luminance(accent) > 0.5 ? "#101014" : "#ffffff"

    readonly property color textPrimary: foreground
    readonly property color textSecondary: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.66)
    readonly property color textMuted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)

    // Translucent fills layered over the panel glass.
    readonly property color surfaceContainer: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    readonly property color surfaceContainerHigh: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

    readonly property color error: color1
    readonly property color warning: color3
    readonly property color success: color2

    // Panel glass: the background at 80% so the compositor blur shows through.
    readonly property color glass: Qt.rgba(background.r, background.g, background.b, 0.8)

    // ── Type and icons ───────────────────────────────────────────────────
    // The shell asked for "JetBrainsMono Nerd Font", which is not installed
    // here: labels fell back to Noto Sans Mono and each glyph was drawn by
    // whatever font happened to cover it, which is why icons disagreed on
    // size and style. Only the exact family name resolves -- "SFMono Nerd
    // Font" alone falls back, "SFMono Nerd Font Mono" does not.
    readonly property string fontMono: "SFMono Nerd Font Mono"

    // One icon scale, picked by role rather than per call site. These are
    // optical sizes: the box the glyph's ink fills, not the em box it is
    // drawn in. IconGlyph does the conversion -- see below.
    readonly property int iconTiny: 11    // chips and dense metadata
    readonly property int iconSmall: 13   // inline markers: check, lock, close
    readonly property int iconMedium: 16  // list rows and tiles
    readonly property int iconLarge: 19   // bar indicators, transport controls
    readonly property int iconHero: 28    // the weather's headline glyph

    // Nerd Font's Material Design set does not draw its glyphs at a common
    // size. At one font.pixelSize the wifi fan inks 0.62 em across while the
    // battery inks 0.88 em tall -- a 1.4x difference sitting side by side on
    // the bar, which is why a single scale still looked ragged. The scale can
    // only set the em box; the glyphs disagree on how much of it they fill.
    //
    // So every icon is measured and divided back down to one reference box.
    // The reference is measured too, from a plain cell-filling glyph (the
    // refresh arrow), so the scale stays correct if fontMono ever changes.
    readonly property TextMetrics iconProbe: TextMetrics {
        font.family: root.fontMono
        font.pixelSize: 100
        text: "\u{F0450}"
    }

    readonly property real iconReferenceBox: {
        var r = iconProbe.tightBoundingRect
        return Math.max(r.width, r.height) / 100
    }

    // ── Motion ───────────────────────────────────────────────────────────
    // Material 3 duration and easing scale, so every animation in the shell
    // is picked from the same set instead of an ad-hoc magic number.
    readonly property int durShort: 100
    readonly property int durMedium: 200
    readonly property int durLong: 300
    readonly property int durExtraLong: 450

    readonly property var easeStandard: [0.2, 0.0, 0.0, 1.0, 1, 1]
    readonly property var easeDecelerate: [0.05, 0.7, 0.1, 1.0, 1, 1]
    readonly property var easeAccelerate: [0.3, 0.0, 0.8, 0.15, 1, 1]
    readonly property var easeSpring: [0.34, 1.3, 0.64, 1.0, 1, 1]

    // State layer opacities for hover / press feedback.
    readonly property real hoverOpacity: 0.08
    readonly property real pressOpacity: 0.14

    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    // Alpha-blended variant of any token, for one-off overlays.
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

}
