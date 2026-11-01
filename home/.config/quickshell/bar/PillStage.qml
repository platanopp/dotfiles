import QtQuick
import qs.components
import qs.config

// The box a bar pill is drawn in, animated inside a window that does not animate: a layer surface
// resized every frame reallocated buffers and stuttered. The window resizes at most twice per move
// (to hold both ends, then to the final size); `Region { item: stage }` keeps input to the box.
//
// targetWidth, targetHeight   what the box should be: grows on the spring, shrinks on a plain curve
// animateWidth / Height       off when the change is already animated upstream (the clock's date)
// minWindowWidth / Height     never less: a window sized for its largest state is never resized
// maxWindowWidth / Height     never more, when set; a spring past it is cut at the edge
// elastic                     off for a move that should not bounce
// evenWidth                   keep the width even, so a centred box sits on whole pixels
//
// The box stays on whole pixels while moving: fractional sizes made the glass and shadow shimmer.
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

    // Driven by hand rather than a Behavior: picking the spring or the plain curve needs to know at
    // the start whether the move grows or shrinks.
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

    // The largest the box has been in the current move, taken when the target changes (while
    // `width` is still the old size) and let go when the move ends.
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

    // Set while the bar is hidden under fullscreen: the window drops to a pixel, since Hyprland
    // composited the whole transparent area of these large windows over the game every frame.
    property bool collapsed: false

    // A window held at its largest state keeps the spring's reach too, so opening never resizes it;
    // others take the reach for the move only.
    function windowSize(min, max, target, reach, held) {
        var size = Math.max(min > 0 ? min * (1 + Theme.springReach) : 0, target + reach, held)
        return Math.ceil(max > 0 ? Math.min(max, size) : size)
    }

    readonly property real windowWidth: stage.collapsed ? 1
        : stage.windowSize(stage.minWindowWidth, stage.maxWindowWidth, stage.targetWidth, stage.reachWidth, stage.heldWidth)
    readonly property real windowHeight: stage.collapsed ? 1
        : stage.windowSize(stage.minWindowHeight, stage.maxWindowHeight, stage.targetHeight, stage.reachHeight, stage.heldHeight)
}
