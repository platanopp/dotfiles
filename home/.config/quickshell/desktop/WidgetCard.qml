import QtQuick
import QtQuick.Effects
import qs.config

// The card every desktop widget is drawn on: the panels' glass (blurred via the
// "quickshell-desktop" layer rule) and shadow. `live` goes off while the desktop is covered,
// stopping widgets that redraw; `bar` gives the player.
Rectangle {
    id: card

    // Off until the host says otherwise, so a widget subscribes to nothing
    // before it knows it is covered.
    property bool live: false
    property var bar: null

    color: Theme.glass
    radius: Theme.radiusXLarge

    // Under the card, like the panels' shadow; a RectangularShadow is
    // analytic, with no texture per card.
    RectangularShadow {
        z: -1
        anchors.fill: parent
        radius: card.radius
        blur: 22
        offset.y: 4
        color: Theme.alpha(Theme.shadow, 0.5)
    }
}
