import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Toast stack under the bar on the right. Cards time out on their own, pause
// while hovered, and can be dismissed by click or by dragging to the right.
PanelWindow {
    id: popups

    property var bar: null
    screen: bar ? bar.screen : null

    readonly property int cardWidth: 360

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        right: true
    }
    margins.top: 56
    margins.right: 12

    // One stack per screen would show the same notification on every monitor,
    // so only the focused one draws it.
    readonly property bool onFocusedMonitor: {
        if (!bar || !bar.monitor) return false
        var focused = Hyprland.focusedMonitor
        return !!focused && focused.id === bar.monitor.id
    }

    visible: Notifications.visibleList.length > 0 && onFocusedMonitor
    color: "transparent"

    implicitWidth: cardWidth + 24
    implicitHeight: Math.max(1, stack.implicitHeight + 24)

    Behavior on implicitHeight {
        NumberAnimation { duration: Theme.durMedium; easing.type: Easing.Bezier; easing.bezierCurve: Theme.easeDecelerate }
    }

    function urgencyColor(urgency) {
        if (urgency === NotificationUrgency.Critical) return Theme.error
        if (urgency === NotificationUrgency.Low) return Theme.textMuted
        return Theme.accent
    }

    Column {
        id: stack
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        width: popups.cardWidth
        spacing: 10

        move: Transition {
            NumberAnimation { properties: "y"; duration: Theme.durMedium; easing.type: Easing.Bezier; easing.bezierCurve: Theme.easeDecelerate }
        }

        Repeater {
            model: Notifications.visibleList

            Item {
                id: card
                required property var modelData

                width: popups.cardWidth
                height: cardBody.implicitHeight

                // Critical notifications stay until acted on; the spec uses a
                // negative timeout to mean "server decides".
                readonly property bool sticky: modelData.urgency === NotificationUrgency.Critical
                readonly property int lifetime: modelData.expireTimeout > 0 ? modelData.expireTimeout : 5000

                // Entrance: slide in from the right and settle.
                opacity: 0
                x: 40

                Component.onCompleted: entrance.start()

                ParallelAnimation {
                    id: entrance
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.durMedium }
                    NumberAnimation {
                        target: card; property: "x"; to: 0
                        duration: Theme.durLong
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Theme.easeDecelerate
                    }
                }

                // Countdown; hovering or dragging holds the card open.
                Timer {
                    interval: card.lifetime
                    running: !card.sticky && !hover.hovered && !drag.active
                    onTriggered: Notifications.dismiss(card.modelData)
                }

                Rectangle {
                    id: cardBody
                    width: parent.width
                    implicitHeight: contentRow.implicitHeight + 28
                    radius: 20
                    color: Theme.glass

                    // Urgency stripe down the leading edge.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        width: 3
                        radius: 2
                        color: popups.urgencyColor(card.modelData.urgency)
                    }

                    RowLayout {
                        id: contentRow
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 16
                        anchors.topMargin: 14
                        anchors.bottomMargin: 14
                        spacing: 12

                        IconImage {
                            visible: source.toString().length > 0
                            implicitSize: 34
                            mipmap: true
                            Layout.alignment: Qt.AlignTop
                            source: {
                                if (card.modelData.image.length > 0) return card.modelData.image
                                if (card.modelData.appIcon.length > 0) return Quickshell.iconPath(card.modelData.appIcon, true)
                                return Quickshell.iconPath(card.modelData.appName.toLowerCase(), true)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: card.modelData.appName
                                    color: popups.urgencyColor(card.modelData.urgency)
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                IconGlyph {
                                    visible: hover.hovered
                                    text: "󰅖"
                                    color: Theme.textSecondary
                                    size: Theme.iconSmall

                                    TapHandler {
                                        onTapped: Notifications.dismiss(card.modelData)
                                    }
                                }
                            }

                            Text {
                                visible: text.length > 0
                                text: card.modelData.summary
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.bold: true
                                font.family: Theme.fontMono
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: text.length > 0
                                text: card.modelData.body
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontMono
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Flow {
                                visible: card.modelData.actions.length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 6

                                Repeater {
                                    model: card.modelData.actions

                                    Rectangle {
                                        id: actionButton
                                        required property var modelData

                                        implicitWidth: actionLabel.implicitWidth + 22
                                        implicitHeight: 26
                                        radius: 13
                                        color: actionTap.pressed ? Theme.surfaceContainerHigh
                                             : (actionHover.hovered ? Theme.surfaceContainer : Theme.alpha(Theme.foreground, 0.05))

                                        Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                        Text {
                                            id: actionLabel
                                            anchors.centerIn: parent
                                            text: actionButton.modelData.text
                                            color: Theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: Theme.fontMono
                                        }

                                        HoverHandler {
                                            id: actionHover
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        TapHandler {
                                            id: actionTap
                                            onTapped: {
                                                card.modelData.invoke(actionButton.modelData.identifier)
                                                Notifications.dismiss(card.modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                HoverHandler {
                    id: hover
                }

                // Drag right past a third of the card to throw it away.
                DragHandler {
                    id: drag
                    target: card
                    yAxis.enabled: false
                    xAxis.minimum: 0

                    onActiveChanged: {
                        if (drag.active) return
                        if (card.x > popups.cardWidth * 0.33) Notifications.dismiss(card.modelData)
                        else settleBack.start()
                    }
                }

                NumberAnimation {
                    id: settleBack
                    target: card
                    property: "x"
                    to: 0
                    duration: Theme.durMedium
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.easeDecelerate
                }
            }
        }
    }
}
