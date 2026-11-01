pragma Singleton
import QtQuick
import Quickshell

// Design tokens for the shell: one fixed palette plus a shared motion scale. Read
// colours from here, never hardcode a hex.
Singleton {
    id: root

    // Palette
    property color background: "#101014"
    property color foreground: "#f2f2f2"

    property color color1: "#e06c75"
    property color color2: "#98c379"
    property color color3: "#e5c07b"
    property color color4: neutralAccent

    // The accent before a wallpaper colour has been picked, or when the wallpaper is a
    // grey with nothing to pick (Accent).
    readonly property color neutralAccent: "#d8d8d8"

    // Semantic tokens
    readonly property color accent: color4

    // Ink on an accent fill: dark or white, whichever has more WCAG contrast (a 0.5
    // luminance cut picked the worse one for mid-tone accents). Not named
    // onAccent/onSurface: QML reads `on<Capital>` as a signal handler.
    readonly property color accentText: inkOn(accent)

    readonly property color textPrimary: foreground
    readonly property color textSecondary: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.66)
    // At 0.62 muted text clears WCAG AA (4.5:1) on every fill here, white wallpaper
    // behind included; 0.45 measured 3.2:1.
    readonly property color textMuted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)

    // Translucent fills layered over the panel glass.
    readonly property color surfaceContainer: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    readonly property color surfaceContainerHigh: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

    readonly property color error: color1
    readonly property color warning: color3
    readonly property color success: color2

    // Panel glass, the background at 90%: only the bar's pills, their panels and
    // the desktop widgets wear it, so it keeps meaning something. 0.9 keeps AA
    // contrast over the brightest wallpaper.
    readonly property color glass: Qt.rgba(background.r, background.g, background.b, 0.9)

    // The full-screen overlays' cards (launcher, overview, wallpapers, keybinds):
    // opaque and unblurred, since a blurred full-screen layer is the most
    // expensive thing the shell can ask for.
    readonly property color surface: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05))
    // The dim behind those cards; with no blur, it keeps the desktop from competing with the card.
    readonly property color scrim: Qt.rgba(background.r, background.g, background.b, 0.6)

    // Shadow under a raised surface, and the white of a switch's knob.
    readonly property color shadow: "#000000"
    readonly property color knob: "#ffffff"

    // Type and icons. Only the exact family name resolves: "SFMono Nerd Font" falls
    // back, "SFMono Nerd Font Mono" does not.
    readonly property string fontMono: "SFMono Nerd Font Mono"

    // Words in SF Pro: Text for labels and body, Display for titles of 20px and up.
    // Mono only for the Nerd Font glyphs; ticking figures (clock, timers,
    // percentages) use SF Pro's tabular figures.
    readonly property string fontText: "SF Pro Text"
    readonly property string fontDisplay: "SF Pro Display"
    readonly property var tabular: ({ "tnum": 1 })

    // One icon scale by role. Optical sizes: the box the glyph's ink fills, not
    // its em box (IconGlyph converts).
    readonly property int iconTiny: 11    // chips and dense metadata
    readonly property int iconSmall: 13   // inline markers: check, lock, close
    readonly property int iconMedium: 16  // list rows and tiles
    readonly property int iconLarge: 19   // bar indicators, transport controls
    readonly property int iconHero: 28    // the weather's headline glyph

    // Nerd Font's Material glyphs don't fill the em box alike (the wifi fan inks 0.62 em, the
    // battery 0.88), so every icon is measured and scaled to one reference box, itself measured
    // from the cell-filling refresh arrow.
    readonly property TextMetrics iconProbe: TextMetrics {
        font.family: root.fontMono
        font.pixelSize: 100
        text: "\u{F0450}"
    }

    readonly property real iconReferenceBox: {
        var r = iconProbe.tightBoundingRect
        return Math.max(r.width, r.height) / 100
    }

    // Bar pills. Padding between a pill's contents and its edges, the same on every pill.
    // Each pill's window is 24px wider than its glass (12px inset each side); the
    // workspace pill draws its glass directly.
    readonly property int pillPaddingH: 16

    // Corners: four radii by size, plus fully round (height / 2) for pills, dots and round buttons.
    readonly property int radiusSmall: 6     // keycaps, chips, tiny badges
    readonly property int radiusMedium: 12   // rows, tiles, inputs
    readonly property int radiusLarge: 18    // cards and panel sections
    readonly property int radiusXLarge: 24   // whole panels and overlay cards

    // Motion: one duration scale for every animation in the shell.
    readonly property int durShort: 100
    readonly property int durMedium: 200
    readonly property int durLong: 300
    readonly property int durExtraLong: 450

    // Springs, for things that arrive (components/Elastic.qml); leaving, fades and colour stay on
    // the plain curves, since a spring on the way out reads as hesitation. The overshoot is
    // OutBack's parameter, peaking at 4s^3 / 27(s+1)^2 of the move: 1.2 is ~5%, like Hyprland's
    // "soft" spring; small moves get more to be visible.
    readonly property int durSpring: 460
    readonly property int durSpringSmall: 340
    readonly property real springOvershoot: 1.2        // ~5% past
    readonly property real springOvershootSmall: 1.8   // ~11% past
    // How far past, as a fraction of the move: room a window must keep so
    // the overshoot is not cut off.
    readonly property real springReach: 0.06

    // State layer opacities for hover / press feedback.
    readonly property real hoverOpacity: 0.08
    readonly property real pressOpacity: 0.14

    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    // WCAG 2 relative luminance and contrast ratio, for picking ink and
    // checking the accent's legibility.
    function relLuminance(c) {
        function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    function contrast(a, b) {
        var la = relLuminance(a), lb = relLuminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }

    // The dark or the white ink, whichever reads better on a fill.
    function inkOn(fill) {
        return contrast(fill, background) >= contrast(fill, knob) ? background : knob
    }

    // Alpha-blended variant of any token, for one-off overlays.
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

}
