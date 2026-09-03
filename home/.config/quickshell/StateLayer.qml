import QtQuick

// Hover and press feedback for anything clickable. Overlays its parent and
// tints it on interaction, so rows and buttons stop being dead glyphs.
// Replaces the bare TapHandlers the panels used to carry.
Rectangle {
    id: root

    property bool interactive: true
    property color tint: Theme.foreground

    // Extra reach for small targets like icon glyphs.
    property int hitMargin: 0

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

        // Without this the default policy is DragThreshold, which does not
        // take an exclusive grab: a Flickable ancestor steals the press the
        // moment the pointer shifts a pixel or two between press and
        // release, and the tap is dropped. A mouse jitters like that
        // constantly, so clicks failed at random -- which reads as dead
        // spots rather than as a timing problem. Press and release inside
        // the item is a click here, whatever the pointer did in between.
        // TrayItems already does this for its right and middle buttons.
        gesturePolicy: TapHandler.ReleaseWithinBounds

        onTapped: root.tapped()
    }
}
