import QtQuick
import qs.components
import qs.config

// The box a bar pill is drawn in, animated inside a window that does not
// animate.
//
// Every pill is a layer surface of its own. Animating the window's size made
// the surface resize on every frame, and a Wayland surface that resizes
// reallocates its buffers and waits on the compositor each time -- the
// expanding panels stuttered, and the pills beside them jerked along. Here
// the window changes size at most twice per move: at the start it jumps to
// hold both where the box was and where it is going, the box grows or
// shrinks inside it, and when the move has finished the window drops to what
// the box needs. Put the pill's content inside (or anchor it to this), anchor
// this to the window's edge the pill hangs from, and size the window with
// windowWidth / windowHeight.
//
// The window keeps input to this box with `Region { item: stage }`, so the
// room it holds for the move is not there for the pointer.
//
//   targetWidth, targetHeight   what the box should be; it animates there:
//                               growing on the shell's spring (Elastic),
//                               shrinking on a plain curve over `duration`
//   animateWidth / Height       off when the change is already animated
//                               upstream (the clock's date folding out)
//   minWindowWidth / Height     never less than this: a window sized for its
//                               largest state once is not resized at all
//                               (the spring's reach is added on top)
//   maxWindowWidth / Height     never more than this, when set; a spring that
//                               would run past it is cut at the edge
//   elastic                     off for a move that should not bounce
//   evenWidth                   keep the width even -- for a box centred in
//                               its window, so it sits on whole pixels
//
// The box is kept to whole pixels while it moves. Fractional sizes left the
// edge anchored to the window on a pixel and the other one between two, and
// the glass and its shadow shimmered as they crossed the grid.
Item {
    id: stage

    property real targetWidth: 0
    property real targetHeight: 0
    property bool animateWidth: true
    property bool animateHeight: true
    property int duration: 280
    property real minWindowWidth: 0
    property real minWindowHeight: 0
    property real maxWindowWidth: 0
    property real maxWindowHeight: 0
    property bool evenWidth: false
    property bool elastic: true

    // The animated values; the box itself is these rounded. Driven by hand
    // rather than by a Behavior: whether a move grows or shrinks has to be
    // known when it starts, to pick the spring or the plain curve, and a
    // Behavior gives no say in which animation it runs.
    property real animWidth: 0
    property real animHeight: 0

    width: stage.evenWidth ? Math.round(stage.animWidth / 2) * 2 : Math.round(stage.animWidth)
    height: Math.round(stage.animHeight)

    property bool ready: false
    Component.onCompleted: {
        stage.animWidth = stage.targetWidth
        stage.animHeight = stage.targetHeight
        stage.ready = true
    }

    Elastic { id: widthGrow; target: stage; property: "animWidth" }
    Elastic { id: heightGrow; target: stage; property: "animHeight" }
    NumberAnimation { id: widthShrink; target: stage; property: "animWidth"; duration: stage.duration; easing.type: Easing.OutCubic }
    NumberAnimation { id: heightShrink; target: stage; property: "animHeight"; duration: stage.duration; easing.type: Easing.OutCubic }

    // Room for the spring past the target, on the axis that is growing.
    property real reachWidth: 0
    property real reachHeight: 0

    function move(horizontal) {
        var grow = horizontal ? widthGrow : heightGrow
        var shrink = horizontal ? widthShrink : heightShrink
        var from = horizontal ? stage.animWidth : stage.animHeight
        var to = horizontal ? stage.targetWidth : stage.targetHeight
        grow.stop()
        shrink.stop()

        if (!stage.ready || !(horizontal ? stage.animateWidth : stage.animateHeight)) {
            if (horizontal) stage.animWidth = to
            else stage.animHeight = to
            return
        }

        if (stage.elastic && to > from) {
            var reach = Math.ceil((to - from) * Theme.springReach)
            if (horizontal) stage.reachWidth = Math.max(stage.reachWidth, reach)
            else stage.reachHeight = Math.max(stage.reachHeight, reach)
            grow.to = to
            grow.start()
        } else {
            shrink.to = to
            shrink.start()
        }
    }

    // The largest the box has been since the current move began. Taken when
    // the target changes -- at that instant `width` is still where the box
    // was -- and let go once the move is over.
    property real heldWidth: 0
    property real heldHeight: 0

    onTargetWidthChanged: {
        stage.heldWidth = Math.max(stage.heldWidth, stage.width)
        stage.move(true)
        release.restart()
    }
    onTargetHeightChanged: {
        stage.heldHeight = Math.max(stage.heldHeight, stage.height)
        stage.move(false)
        release.restart()
    }

    Timer {
        id: release
        interval: Math.max(stage.duration, Theme.durSpring) + 40
        onTriggered: {
            stage.heldWidth = 0
            stage.heldHeight = 0
            stage.reachWidth = 0
            stage.reachHeight = 0
        }
    }

    // Set while the bar is hidden (a fullscreen window): the pill draws
    // nothing then, so its window drops to a pixel -- these windows are
    // sized for their largest state (a 790x1032 control panel, a 640-high
    // media panel) and stay mapped, and Hyprland was compositing all that
    // transparent area over the game every frame. Shrinking while nothing is
    // drawn cannot show the one empty frame a resize costs.
    property bool collapsed: false

    // A window held at its largest state keeps the spring's reach past that
    // state too, so opening never resizes it; the others take the reach for
    // the length of the move, as they take `held`.
    function windowSize(min, max, target, reach, held) {
        var size = Math.max(min > 0 ? min * (1 + Theme.springReach) : 0, target + reach, held)
        return Math.ceil(max > 0 ? Math.min(max, size) : size)
    }

    readonly property real windowWidth: stage.collapsed ? 1
        : stage.windowSize(stage.minWindowWidth, stage.maxWindowWidth, stage.targetWidth, stage.reachWidth, stage.heldWidth)
    readonly property real windowHeight: stage.collapsed ? 1
        : stage.windowSize(stage.minWindowHeight, stage.maxWindowHeight, stage.targetHeight, stage.reachHeight, stage.heldHeight)
}
