import QtQuick

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
//   targetWidth, targetHeight   what the box should be; it animates there
//   animateWidth / Height       off when the change is already animated
//                               upstream (the clock's date folding out)
//   minWindowWidth / Height     never less than this: a window sized for its
//                               largest state once is not resized at all
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
    property bool evenWidth: false

    // The animated values; the box itself is these rounded.
    property real animWidth: targetWidth
    property real animHeight: targetHeight

    width: stage.evenWidth ? Math.round(stage.animWidth / 2) * 2 : Math.round(stage.animWidth)
    height: Math.round(stage.animHeight)

    Behavior on animWidth {
        enabled: stage.animateWidth
        NumberAnimation { duration: stage.duration; easing.type: Easing.OutCubic }
    }

    Behavior on animHeight {
        enabled: stage.animateHeight
        NumberAnimation { duration: stage.duration; easing.type: Easing.OutCubic }
    }

    // The largest the box has been since the current move began. Taken when
    // the target changes -- at that instant `width` is still where the box
    // was -- and let go once the move is over.
    property real heldWidth: 0
    property real heldHeight: 0

    onTargetWidthChanged: {
        stage.heldWidth = Math.max(stage.heldWidth, stage.width)
        release.restart()
    }
    onTargetHeightChanged: {
        stage.heldHeight = Math.max(stage.heldHeight, stage.height)
        release.restart()
    }

    Timer {
        id: release
        interval: stage.duration + 40
        onTriggered: {
            stage.heldWidth = 0
            stage.heldHeight = 0
        }
    }

    readonly property real windowWidth: Math.ceil(Math.max(stage.minWindowWidth, stage.targetWidth, stage.heldWidth))
    readonly property real windowHeight: Math.ceil(Math.max(stage.minWindowHeight, stage.targetHeight, stage.heldHeight))
}
