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

    property color color1: "#e06c75"
    property color color2: "#98c379"
    property color color3: "#e5c07b"
    property color color4: neutralAccent

    // What the accent falls back to while no wallpaper colour has been picked,
    // or when the wallpaper is a grey with nothing to pick (services/Accent).
    readonly property color neutralAccent: "#d8d8d8"

    // ── Semantic tokens ──────────────────────────────────────────────────
    readonly property color accent: color4

    // Text drawn on top of an accent fill: whichever of the dark or the white
    // ink reads better on it, by WCAG contrast rather than by a luminance
    // cut-off. The accent now follows the wallpaper, and a mid-tone blue or
    // red sits exactly where a 0.5 threshold picks the worse of the two.
    // Note: these must not be named onAccent/onSurface -- QML reads any
    // `on<Capital>` identifier as a signal handler, not a property.
    readonly property color accentText: inkOn(accent)

    readonly property color textPrimary: foreground
    readonly property color textSecondary: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.66)
    // 0.62, not the 0.45 it was: at 0.45 muted text measured 3.2:1 over a
    // light wallpaper and 3.8:1 on a raised fill, under the 4.5:1 WCAG AA asks
    // of body text. With the glass at 0.9 it now clears 4.5:1 on every fill
    // here, white wallpaper behind included.
    readonly property color textMuted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)

    // Translucent fills layered over the panel glass.
    readonly property color surfaceContainer: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
    readonly property color surfaceContainerHigh: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
    readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)

    readonly property color error: color1
    readonly property color warning: color3
    readonly property color success: color2

    // Panel glass: the background at 90% so the compositor blur shows through.
    // Glass belongs to the bar's pills and the panels that open out of them,
    // and to nothing else: it is the shell's one signature surface, and on
    // every layer at once it stopped marking anything. 0.9 rather than 0.8 so
    // text on it keeps AA contrast over the brightest wallpaper.
    readonly property color glass: Qt.rgba(background.r, background.g, background.b, 0.9)

    // The full-screen overlays (launcher, overview, wallpapers, keybinds) draw
    // their cards on this instead: opaque, so what they hold reads the same
    // over any desktop, and with no compositor blur under them -- a blurred
    // full-screen layer is the most expensive thing the shell can ask for.
    readonly property color surface: Qt.tint(background, Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05))
    // The dim behind those cards. Without blur it is what keeps the desktop
    // from competing with the card, so it is darker than the old tint was.
    readonly property color scrim: Qt.rgba(background.r, background.g, background.b, 0.6)

    // The desktop widgets' card: the wallpaper's hue (the accent's, which
    // Accent takes from it) at a dark value, so the widgets read as part of
    // the picture they sit on and follow it when it changes. Opaque, like the
    // overlays' cards, and dark enough that muted text on it keeps 4.5:1 for
    // any hue. A grey wallpaper has no hue to give, and gets the plain surface.
    readonly property color widgetSurface: accent.hsvSaturation < 0.05 ? surface
        : Qt.hsva(accent.hsvHue, Math.min(0.55, accent.hsvSaturation * 1.1), 0.21, 1)

    // Shadow under a raised surface, and the white of a switch's knob.
    readonly property color shadow: "#000000"
    readonly property color knob: "#ffffff"

    // ── Type and icons ───────────────────────────────────────────────────
    // The shell asked for "JetBrainsMono Nerd Font", which is not installed
    // here: labels fell back to Noto Sans Mono and each glyph was drawn by
    // whatever font happened to cover it, which is why icons disagreed on
    // size and style. Only the exact family name resolves -- "SFMono Nerd
    // Font" alone falls back, "SFMono Nerd Font Mono" does not.
    readonly property string fontMono: "SFMono Nerd Font Mono"

    // Words are set in SF Pro: Text for labels and body, Display for titles
    // of 20px and up, the cut it was drawn for. Mono stays for the Nerd Font
    // glyphs, which only it carries. Figures that tick (the clock, a timer, a
    // percentage) use SF Pro's tabular figures instead -- the reason the whole
    // shell used to be monospaced, now kept to the places that need it.
    readonly property string fontText: "SF Pro Text"
    readonly property string fontDisplay: "SF Pro Display"
    readonly property var tabular: ({ "tnum": 1 })

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

    // ── Bar pills ────────────────────────────────────────────────────────
    // Space between a pill's contents and its left and right edges, the same
    // on every pill on the bar. Each pill's window is 24px wider than the
    // glass it draws (a 12px inset each side), so a widget adds 24 plus twice
    // this to its content; the workspace pill draws its glass directly and
    // adds only the padding.
    readonly property int pillPaddingH: 16

    // ── Corners ──────────────────────────────────────────────────────────
    // Four radii, by how big the thing is, plus fully round (height / 2) for
    // pills, dots and round buttons. The shell had grown sixteen values
    // between 3 and 26; each one now rounds to the nearest of these.
    readonly property int radiusSmall: 6     // keycaps, chips, tiny badges
    readonly property int radiusMedium: 12   // rows, tiles, inputs
    readonly property int radiusLarge: 18    // cards and panel sections
    readonly property int radiusXLarge: 24   // whole panels and overlay cards

    // ── Motion ───────────────────────────────────────────────────────────
    // One duration scale, so every animation in the shell is picked from the
    // same set instead of an ad-hoc magic number.
    readonly property int durShort: 100
    readonly property int durMedium: 200
    readonly property int durLong: 300
    readonly property int durExtraLong: 450

    // Springs, for things that arrive: a panel growing out of its pill, an
    // overlay's card, a notification sliding in, an indicator landing on the
    // tab it moved to. They run past where they are going and settle back,
    // the soft give of a damped spring (components/Elastic.qml). Leaving,
    // fading and colour stay on the plain curves above: a spring on the way
    // out reads as hesitation, and opacity has no "past".
    //
    // The overshoot is OutBack's parameter. Its peak is 4s^3 / 27(s+1)^2 of
    // the distance travelled: 1.2 runs ~5% past, about what Hyprland's "soft"
    // spring does, so windows and the shell move alike. Small moves (a knob,
    // a tab indicator) get more, or their few pixels of give are invisible.
    readonly property int durSpring: 460
    readonly property int durSpringSmall: 340
    readonly property real springOvershoot: 1.2        // ~5% past
    readonly property real springOvershootSmall: 1.8   // ~11% past
    // How far past, as a fraction of the move: room a window must keep so
    // the overshoot is not cut off at its edge.
    readonly property real springReach: 0.06

    // State layer opacities for hover / press feedback.
    readonly property real hoverOpacity: 0.08
    readonly property real pressOpacity: 0.14

    function luminance(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    // WCAG 2 relative luminance and contrast ratio, for picking ink and for
    // the accent's legibility check.
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
