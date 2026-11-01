import QtQuick
import qs.config
import qs.desktop
import qs.services

// Hands on a dial, stepping once a minute. No second hand: it would redraw every
// second for a mostly covered desktop.
WidgetCard {
    id: root

    readonly property var now: { Clock.currentTime; return new Date() }
    readonly property real minuteAngle: root.now.getMinutes() * 6
    readonly property real hourAngle: (root.now.getHours() % 12) * 30 + root.now.getMinutes() * 0.5

    radius: width / 2

    // A tick per hour; the quarters longer, as on a watch face.
    Repeater {
        model: 12

        Item {
            required property int index
            anchors.fill: parent
            rotation: index * 30

            Rectangle {
                readonly property bool quarter: parent.index % 3 === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                width: quarter ? 4 : 3
                height: quarter ? 14 : 8
                radius: width / 2
                color: quarter ? Theme.textSecondary : Theme.textMuted
            }
        }
    }

    // Both hands turn about the centre; Clockwise so 59 to 0 goes forward a
    // minute instead of back round the dial.
    component Hand: Rectangle {
        id: hand
        property real angle: 0
        property real length: 60
        width: 6
        height: hand.length
        radius: width / 2
        x: (root.width - width) / 2
        y: root.height / 2 - hand.length + width / 2
        transform: Rotation {
            origin.x: hand.width / 2
            origin.y: hand.length - hand.width / 2
            angle: hand.angle

            Behavior on angle {
                RotationAnimation {
                    direction: RotationAnimation.Clockwise
                    duration: Theme.durSpringSmall
                    easing.type: Easing.OutBack
                    easing.overshoot: Theme.springOvershootSmall
                }
            }
        }
    }

    Hand {
        angle: root.hourAngle
        length: root.height * 0.27
        width: 7
        color: Theme.textPrimary
    }

    Hand {
        angle: root.minuteAngle
        length: root.height * 0.38
        width: 5
        color: Theme.textPrimary
    }

    Rectangle {
        anchors.centerIn: parent
        width: 12
        height: 12
        radius: height / 2
        color: Theme.textPrimary
    }
}
