import QtQuick

// A slider in the Settings window's style: a thick rounded track, an upright
// handle, and the value in a bubble riding above it.
//
// The value is shown live while dragging but only committed on release --
// every commit here runs a process (hyprsunset, nvibrant), and a drag would
// otherwise queue dozens of them behind each other.
//
//   from, to, value     the range and the current value
//   neutral             optional: marked on the track, and what a double-click
//                       returns to
//   format(v)           text for the bubble
//   gradient            optional Gradient for the track, e.g. colour temperature
//   moved(v)            on release
Item {
    id: root

    property real from: 0
    property real to: 1
    property real value: 0
    property real neutral: NaN
    property var format: function (v) { return Math.round(v) }
    property Gradient gradient: null
    signal moved(real value)

    readonly property bool dragging: area.pressed
    property real dragValue: 0
    readonly property real shown: root.dragging ? root.dragValue : root.value
    readonly property real fraction: Math.max(0, Math.min(1, (root.shown - root.from) / (root.to - root.from)))

    implicitHeight: 54
    implicitWidth: 240

    function valueAt(x) {
        var f = Math.max(0, Math.min(1, x / track.width))
        return root.from + f * (root.to - root.from)
    }

    // The value, riding above the handle and kept inside the slider's width.
    Rectangle {
        id: bubble
        y: 0
        width: bubbleText.implicitWidth + 16
        height: 20
        radius: 10
        x: Math.max(0, Math.min(root.width - width, handle.x + handle.width / 2 - width / 2))
        color: root.dragging ? Theme.accent : Theme.surfaceContainerHigh

        Behavior on color { ColorAnimation { duration: Theme.durShort } }

        Text {
            id: bubbleText
            anchors.centerIn: parent
            text: root.format(root.shown)
            font.pixelSize: 10
            font.bold: true
            font.family: Theme.fontMono
            color: root.dragging ? Theme.accentText : Theme.textPrimary
        }
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 7
        height: 12
        radius: 6
        color: Theme.track
        gradient: root.gradient

        // The filled part. Left out over a gradient track, where the colour
        // itself is the reading and a fill would only hide it.
        Rectangle {
            visible: root.gradient === null
            width: Math.max(track.radius * 2, track.width * root.fraction)
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }

        // Where neutral sits, so it can be found again by eye.
        Rectangle {
            visible: !isNaN(root.neutral)
            x: track.width * Math.max(0, Math.min(1, (root.neutral - root.from) / (root.to - root.from))) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: parent.height + 6
            radius: 1
            color: Theme.alpha(Theme.foreground, 0.35)
        }
    }

    Rectangle {
        id: handle
        width: 6
        height: 26
        radius: 3
        x: track.width * root.fraction - width / 2
        anchors.verticalCenter: track.verticalCenter
        color: Theme.textPrimary
        scale: root.dragging ? 1.12 : 1

        Behavior on scale { NumberAnimation { duration: Theme.durShort } }
    }

    MouseArea {
        id: area
        anchors.fill: track
        anchors.topMargin: -14
        anchors.bottomMargin: -6
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        onPressed: mouse => root.dragValue = root.valueAt(mouse.x)
        onPositionChanged: mouse => { if (pressed) root.dragValue = root.valueAt(mouse.x) }
        onReleased: root.moved(root.dragValue)
        onDoubleClicked: if (!isNaN(root.neutral)) root.moved(root.neutral)
    }
}
