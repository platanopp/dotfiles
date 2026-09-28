import Quickshell
import Quickshell.Wayland
import QtQuick

// The count of three before a recording starts (AppState.countdownRecording),
// big in the middle of the monitor about to be recorded: a glass disc, the
// number dropping into it on each second, and a ring running down around it.
// Esc or a click calls the recording off.
//
// Off the screen before the recording starts: AppState waits a beat after
// the "1" before starting, and Hyprland is told not to fade this layer out
// (hyprland.lua), so the count is never in the video. Mapped only while
// counting; nothing drawn or kept otherwise.
PanelWindow {
    id: overlay

    property var bar: null
    screen: bar.screen

    readonly property bool counting: AppState.recordCountdown > 0
                                     && (AppState.recordCountdownMonitor === ""
                                         || (bar.monitor && bar.monitor.name === AppState.recordCountdownMonitor))

    visible: overlay.counting

    color: "transparent"

    WlrLayershell.namespace: "quickshell:countdown"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    // For Esc. Set only while mapped, and the surface goes away with it, so
    // it is never changed under a surface that stays (see AppLauncher).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // A light dim, so the number reads over anything.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.25)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: AppState.cancelRecordingCountdown()
    }

    Item {
        focus: overlay.counting
        Keys.onEscapePressed: AppState.cancelRecordingCountdown()
        Component.onCompleted: forceActiveFocus()
    }

    Column {
        anchors.centerIn: parent
        spacing: 22

        Item {
            id: dial
            anchors.horizontalCenter: parent.horizontalCenter
            width: 180
            height: 180

            // Comes in with the first number.
            scale: overlay.counting ? 1 : 0.8
            opacity: overlay.counting ? 1 : 0
            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Theme.glass
                border.width: 1
                border.color: Theme.outline
            }

            // The second running down: a ring drawn once per second from full
            // to empty, in the recording red.
            Canvas {
                id: ring
                anchors.fill: parent
                anchors.margins: 6
                property real progress: 1

                onProgressChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var r = width / 2 - 4
                    ctx.lineWidth = 5
                    ctx.lineCap = "round"
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08)
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
                    ctx.stroke()
                    ctx.strokeStyle = Theme.error
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ring.progress)
                    ctx.stroke()
                }

                NumberAnimation on progress {
                    id: ringRun
                    from: 1
                    to: 0
                    duration: 1000
                    running: false
                }
            }

            // The number, dropping in and settling on each second.
            Text {
                id: digit
                anchors.centerIn: parent
                text: AppState.recordCountdown > 0 ? AppState.recordCountdown : ""
                color: Theme.textPrimary
                font.pixelSize: 88
                font.bold: true
                font.family: Theme.fontMono

                onTextChanged: {
                    if (text.length === 0) return
                    drop.restart()
                    ringRun.restart()
                }

                ParallelAnimation {
                    id: drop
                    NumberAnimation { target: digit; property: "scale"; from: 1.5; to: 1; duration: 420; easing.type: Easing.OutBack }
                    NumberAnimation { target: digit; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
                }
            }
        }

        // What happens next, and how not to.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: hint.implicitWidth + 28
            height: 30
            radius: 15
            color: Theme.glass
            opacity: dial.opacity

            Row {
                id: hint
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.error
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Recording starts  ·  esc to cancel"
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                }
            }
        }
    }
}
