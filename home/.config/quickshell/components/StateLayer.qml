import QtQuick
import qs.config

// Hover and press feedback for anything clickable: overlays its parent and tints it on interaction.
Rectangle {
    id: root

    property bool interactive: true
    property color tint: Theme.foreground

    // Extra reach for small targets like icon glyphs.
    property int hitMargin: 0

    // How the press is held (see the TapHandler below). Items on a draggable surface (a carousel
    // panel) set DragThreshold, so a press that becomes a drag goes to the view.
    property int gesturePolicy: TapHandler.ReleaseWithinBounds

    // Exposed so callers can drive their own press/hover animations.
    readonly property bool pressed: tap.pressed
    readonly property bool hovered: hover.hovered

    signal tapped()

    anchors.fill: parent
    anchors.margins: -hitMargin

    radius: parent && parent.radius !== undefined ? parent.radius : height / 2

    color: Theme.alpha(tint,
        !root.interactive ? 0
        : tap.pressed ? Theme.pressOpacity
        : hover.hovered ? Theme.hoverOpacity
        : 0)

    Behavior on color {
        ColorAnimation { duration: Theme.durShort }
    }

    HoverHandler {
        id: hover
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap
        enabled: root.interactive

        // Not DragThreshold by default: its non-exclusive grab let a Flickable ancestor steal
        // the press when the mouse jittered a pixel, so clicks failed at random. Press and
        // release inside the item is a click.
        gesturePolicy: root.gesturePolicy

        onTapped: root.tapped()
    }
}
