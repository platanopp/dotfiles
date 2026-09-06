import Quickshell
import Quickshell.Wayland
import QtQuick

// The fade on either side of the lock screen.
//
// veila puts its lock up through ext-session-lock, which the compositor swaps
// in whole and draws above every layer this shell can reach. There is no frame
// in which both the desktop and the lock are on screen, so the change is a
// hard cut in both directions, and veila has no setting that softens it --
// its config knows nothing about animation.
//
// So the transition is done on this side of the swap instead. The curtain is
// already opaque before the lock is asked for, and is still opaque when the
// lock lets go, which leaves the eye one continuous dim out and back with the
// cut hidden inside it. AppState.lockPhase drives the two halves; the moments
// it turns on come from scripts/lock_session.sh.
PanelWindow {
    id: overlay

    property var bar: null
    screen: bar.screen

    // "closing" and "locked" both mean covered: the second half of the lock
    // is spent fully opaque and out of sight underneath veila, which is what
    // makes the unlock fade possible at all -- there is nothing to fade in,
    // it was never taken down.
    readonly property bool covering: AppState.lockPhase === "closing"
                                  || AppState.lockPhase === "locked"

    readonly property bool idle: AppState.lockPhase === ""

    // Mapped for the life of the shell and hidden by drawing nothing, the way
    // the bar and the cheatsheet are: toggling `visible` destroys the layer
    // surface, and a surface recreated at lock time would have to win its
    // place in the stack again at the worst possible moment.
    visible: true
    color: "transparent"

    WlrLayershell.namespace: "quickshell:lock-fade"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Held for the whole 300ms the screen is still visible and going dark, so
    // a keystroke aimed at whatever was open cannot land there after the user
    // has already asked for the screen to be locked. Dropped again the moment
    // veila takes over, which is the point at which the compositor is doing
    // this properly rather than us approximating it.
    WlrLayershell.keyboardFocus: AppState.lockPhase === "closing"
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Swallows the pointer for the whole transition for the same reason, and
    // gives it back only once the fade is finished -- a click during the last
    // frames of the fade out is one the user aimed at a screen they could not
    // yet properly see.
    mask: overlay.idle ? blankMask : null

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    Item {
        id: veil
        anchors.fill: parent

        // Animated rather than bound, so the two directions can be given
        // different curves and lengths; see the transitions below.
        property real dim: 0
        property real markOpacity: 0
        property real markScale: 1.3

        Rectangle {
            anchors.fill: parent
            // The shell's own near-black rather than #000, so the dim reads as
            // the same surface everything else here is drawn on.
            color: Theme.background
            opacity: veil.dim
        }

        // Closed on the way in, open on the way out. It is on screen for only
        // a few hundred milliseconds either side, and that is the whole point:
        // it says which way the transition is going while it is going.
        IconGlyph {
            anchors.centerIn: parent
            text: overlay.covering ? "\u{F033E}" : "\u{F033F}"
            // Off Theme's icon scale on purpose: those sizes are for icons
            // sitting next to text, and this one is alone on a whole screen.
            size: 40
            color: Theme.textMuted
            opacity: veil.markOpacity
            scale: veil.markScale
        }

        states: State {
            name: "covered"
            when: overlay.covering
            PropertyChanges {
                target: veil
                dim: 1
                markOpacity: 1
                markScale: 1.0
            }
        }

        // Written as transitions rather than Behaviors because the curve has
        // to differ by direction, and a Behavior can only read one duration
        // at the instant it is triggered.
        transitions: [
            // Going: accelerating, so the desktop is gone quickly. The mark
            // settles from slightly too large with a little overshoot, which
            // is what makes it read as a latch closing rather than a fade.
            Transition {
                to: "covered"
                ParallelAnimation {
                    NumberAnimation {
                        target: veil; property: "dim"
                        duration: Theme.durLong
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.easeAccelerate
                    }
                    NumberAnimation {
                        target: veil; property: "markOpacity"
                        duration: Theme.durMedium
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.easeStandard
                    }
                    NumberAnimation {
                        target: veil; property: "markScale"
                        duration: Theme.durExtraLong
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.easeSpring
                    }
                }
            },
            // Coming back: decelerating and longer, and the mark leaves first
            // so the last thing on screen is the desktop rather than an icon
            // hanging over it. It grows as it goes, which is the same latch
            // opening.
            Transition {
                from: "covered"
                ParallelAnimation {
                    NumberAnimation {
                        target: veil; property: "dim"
                        duration: Theme.durExtraLong
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.easeDecelerate
                    }
                    NumberAnimation {
                        target: veil; property: "markOpacity"
                        duration: Theme.durMedium
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.easeAccelerate
                    }
                    NumberAnimation {
                        target: veil; property: "markScale"
                        duration: Theme.durExtraLong
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.easeDecelerate
                    }
                }
            }
        ]
    }
}
