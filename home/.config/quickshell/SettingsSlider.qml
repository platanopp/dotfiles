import QtQuick
import QtQuick.Effects

// A slider for the Settings window: a slim track, the part up to the value
// filled in the accent, and a round knob. The reading lives on the row's
// title line (SettingsRow.value); a bubble with it rises over the knob only
// while it is being dragged.
//
// The value shows live while dragging -- `shown` is there for anything that
// wants to preview it -- but is committed only on release: every commit runs
// a process, and a drag would otherwise queue dozens of them.
//
//   from, to, value   the range and the current value
//   step              snap to multiples of this (0: continuous)
//   neutral           optional: a small mark on the track, and what a
//                     double-click returns to
//   format(v)         text for the bubble
//   gradient          optional Gradient for the track, e.g. colour temperature
//   moved(v)          on release
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0
    property real neutral: NaN
    property var format: function (v) { return Math.round(v) }
    property Gradient gradient: null
    // Kept for pages that still pass one; the slider is monochrome.
    property color tint: Theme.accent
    signal moved(real value)

    readonly property bool dragging: area.pressed
    property real dragValue: 0
    readonly property real shown: root.dragging ? root.dragValue : root.value
    readonly property real fraction: Math.max(0, Math.min(1, (root.shown - root.from) / (root.to - root.from)))

    implicitHeight: 24
    implicitWidth: 240

    function snapped(v) {
        if (root.step > 0) v = Math.round(v / root.step) * root.step
        return Math.max(root.from, Math.min(root.to, v))
    }

    function valueAt(x) {
        var f = Math.max(0, Math.min(1, (x - knob.width / 2) / (root.width - knob.width)))
        return root.snapped(root.from + f * (root.to - root.from))
    }

    // The knob travels inside the track's ends, never past them.
    readonly property real knobX: (root.width - knob.width) * root.fraction

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: Theme.track
        gradient: root.gradient

        Rectangle {
            visible: root.gradient === null
            width: root.knobX + knob.width / 2
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }

        // Neutral, marked as a dot just under the track.
        Rectangle {
            visible: !isNaN(root.neutral)
            width: 4
            height: 4
            radius: 2
            x: (root.width - knob.width) * Math.max(0, Math.min(1, (root.neutral - root.from) / (root.to - root.from)))
               + knob.width / 2 - width / 2
            y: parent.height + 5
            color: Theme.textMuted
        }
    }

    Rectangle {
        id: knob
        width: 18
        height: 18
        radius: 9
        x: root.knobX
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.foreground
        scale: root.dragging ? 1.2 : knobHover.hovered ? 1.1 : 1

        Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutCubic } }

        HoverHandler { id: knobHover }
    }

    // A soft ring under the knob, so it lifts off a light fill.
    RectangularShadow {
        anchors.fill: knob
        z: -1
        radius: knob.radius
        blur: 8
        spread: 1
        color: Qt.rgba(0, 0, 0, 0.45)
        scale: knob.scale
    }

    // The value over the knob, only while it moves.
    Rectangle {
        width: bubbleText.implicitWidth + 16
        height: 22
        radius: 11
        x: Math.max(0, Math.min(root.width - width, knob.x + knob.width / 2 - width / 2))
        y: -height - 8
        color: Theme.accent
        opacity: root.dragging ? 1 : 0
        scale: root.dragging ? 1 : 0.8
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
        Behavior on scale { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutBack } }

        Text {
            id: bubbleText
            anchors.centerIn: parent
            text: root.format(root.shown)
            font.pixelSize: 10
            font.bold: true
            font.family: Theme.fontMono
            color: Theme.accentText
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -8
        anchors.bottomMargin: -8
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        onPressed: mouse => root.dragValue = root.valueAt(mouse.x)
        onPositionChanged: mouse => { if (pressed) root.dragValue = root.valueAt(mouse.x) }
        onReleased: root.moved(root.dragValue)
        onDoubleClicked: if (!isNaN(root.neutral)) root.moved(root.neutral)
    }
}
