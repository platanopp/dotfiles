import QtQuick
import QtQuick.Effects
import qs.config

// The card every desktop widget is drawn on: the bar panels' own glass
// (Theme.glass, blurred by the compositor through the "quickshell-desktop"
// layer rule) with the same soft shadow under it, so a widget reads as one of
// the shell's panels left open on the desktop rather than a card of its own.
//
// Each widget sets `live` off while its monitor's desktop is covered, and the
// ones that redraw on their own (the spectrum, the meters, a song's progress)
// stop with it. `bar` is the monitor's bar, for the media player it follows.
Rectangle {
    id: card

    // Off until the host says otherwise, so a widget does not subscribe to
    // anything for the moment between being created and being told it is
    // covered.
    property bool live: false
    property var bar: null

    color: Theme.glass
    radius: Theme.radiusXLarge

    // Under the card (z below its parent), as the panels' MultiEffect draws
    // it: half-opaque black, a short drop. A RectangularShadow rather than a
    // MultiEffect over a layer: it is drawn analytically, no texture per card.
    RectangularShadow {
        z: -1
        anchors.fill: parent
        radius: card.radius
        blur: 22
        offset.y: 4
        color: Theme.alpha(Theme.shadow, 0.5)
    }
}
