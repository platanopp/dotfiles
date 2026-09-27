import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Toasts: how a notification arrives. They stack under the right-hand end of
// the bar, in the bar's glass, as wide as the control panel they sit under.
// Each shows for five seconds -- the line along its foot runs down to show
// how long is left -- and then leaves the screen for the centre (the bell),
// not for good. Hovering or dragging holds it; the cross or a drag to the
// right sends it on at once; tapping it does what the notification is for.
// Critical ones stay until dealt with, and have no line.
PanelWindow {
    id: popups

    property var bar: null
    screen: bar ? bar.screen : null

    readonly property int cardWidth: 372 - 24
    readonly property int lifetime: 5000

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        right: true
    }
    // Under the bar's pills by the same gap the pills keep between each
    // other, the right edge in line with theirs. The 12 is the inset every
    // surface here draws its content at.
    margins.top: AppState.gapTop + 40 + 10 - 12
    margins.right: AppState.gapRight - 12

    // One stack per screen would show the same notification on every monitor,
    // so only the focused one draws it.
    readonly property bool onFocusedMonitor: {
        if (!bar || !bar.monitor) return false
        var focused = Hyprland.focusedMonitor
        return !!focused && focused.id === bar.monitor.id
    }

    visible: Notifications.visibleList.length > 0 && onFocusedMonitor
    color: "transparent"

    // A fixed size, never animated: a surface that resizes every frame
    // stutters (see PillStage). The stack moves inside; input is kept to it.
    implicitWidth: cardWidth + 24
    implicitHeight: screen ? Math.min(screen.height - 120, 820) : 700

    mask: Region {
        item: stack
    }

    Column {
        id: stack
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        width: popups.cardWidth
        spacing: 10

        move: Transition {
            NumberAnimation { properties: "y"; duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: Notifications.visibleList

            Item {
                id: card
                required property var modelData
                readonly property var n: card.modelData

                width: popups.cardWidth
                height: glass.height

                readonly property bool sticky: card.n.urgency === NotificationUrgency.Critical
                readonly property var defaultAction: {
                    for (var i = 0; i < card.n.actions.length; i++)
                        if (card.n.actions[i].identifier === "default") return card.n.actions[i]
                    return null
                }

                // What is left of its time on screen, 1 to 0.
                property real remaining: 1

                NumberAnimation {
                    id: countdown
                    target: card
                    property: "remaining"
                    from: 1
                    to: 0
                    duration: popups.lifetime
                    running: !card.sticky
                    paused: running && (hover.hovered || drag.active)
                    // Off the screen, into the centre -- not gone.
                    onFinished: Notifications.expire(card.n)
                }

                // Entrance: in from the right, settling.
                opacity: 0
                x: 48
                Component.onCompleted: entrance.start()

                ParallelAnimation {
                    id: entrance
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.durMedium }
                    NumberAnimation { target: card; property: "x"; to: 0; duration: Theme.durLong; easing.type: Easing.OutCubic }
                }

                HoverHandler {
                    id: hover
                    cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                // What tapping a notification means; done, it has served.
                TapHandler {
                    enabled: card.defaultAction !== null
                    onTapped: {
                        card.n.invoke("default")
                        Notifications.dismiss(card.n)
                    }
                }

                // Drag right past a third of the card to send it on, like the
                // cross.
                DragHandler {
                    id: drag
                    target: card
                    yAxis.enabled: false
                    xAxis.minimum: 0

                    onActiveChanged: {
                        if (drag.active) return
                        if (card.x > popups.cardWidth * 0.33) Notifications.expire(card.n)
                        else settleBack.start()
                    }
                }

                NumberAnimation {
                    id: settleBack
                    target: card
                    property: "x"
                    to: 0
                    duration: Theme.durMedium
                    easing.type: Easing.OutCubic
                }

                // ── The glass, as the bar's pills have it ───────────────────
                Rectangle {
                    id: glass
                    width: parent.width
                    height: content.implicitHeight + 30
                    radius: 22
                    color: Theme.glass
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    source: glass
                    anchors.fill: glass
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowOpacity: 0.5
                    shadowBlur: 0.7
                    shadowVerticalOffset: 4
                    autoPaddingEnabled: true
                }

                // A touch lighter under the pointer, like every button here.
                Rectangle {
                    anchors.fill: glass
                    radius: glass.radius
                    color: Theme.foreground
                    opacity: hover.hovered && card.defaultAction ? Theme.hoverOpacity * 0.6 : 0

                    Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                }

                ColumnLayout {
                    id: content
                    anchors.left: glass.left
                    anchors.right: glass.right
                    anchors.top: glass.top
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    anchors.topMargin: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        ClippingRectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 11
                            color: Theme.surfaceContainerHigh

                            IconImage {
                                id: appImage
                                anchors.fill: parent
                                mipmap: true
                                visible: status === Image.Ready
                                source: {
                                    if (card.n.image.length > 0) return card.n.image
                                    if (card.n.appIcon.length > 0) return Quickshell.iconPath(card.n.appIcon, true)
                                    return Quickshell.iconPath(card.n.appName.toLowerCase(), true)
                                }
                            }

                            IconGlyph {
                                anchors.centerIn: parent
                                visible: appImage.status !== Image.Ready
                                text: "\u{F009A}"
                                size: Theme.iconMedium
                                color: Theme.textMuted
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Critical, as a dot beside the app's name.
                                Rectangle {
                                    visible: card.sticky
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 6
                                    implicitHeight: 6
                                    radius: 3
                                    color: Theme.error
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (card.n.appName || "Notification") + "  ·  now"
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                }

                                IconButton {
                                    icon: "\u{F0156}"
                                    size: 22
                                    glyphSize: Theme.iconSmall
                                    iconColor: Theme.textMuted
                                    opacity: hover.hovered ? 1 : 0
                                    onTapped: Notifications.expire(card.n)

                                    Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                                }
                            }

                            Text {
                                visible: text.length > 0
                                Layout.fillWidth: true
                                text: card.n.summary
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.bold: true
                                font.family: Theme.fontMono
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: text.length > 0
                                Layout.fillWidth: true
                                text: card.n.body
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontMono
                                textFormat: Text.PlainText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // Its other actions; "default" is the card itself.
                    Flow {
                        visible: card.n.actions.some(a => a.identifier !== "default")
                        Layout.fillWidth: true
                        Layout.leftMargin: 48
                        spacing: 6

                        Repeater {
                            model: card.n.actions.filter(a => a.identifier !== "default")

                            PillButton {
                                required property var modelData
                                text: modelData.text
                                onClicked: {
                                    card.n.invoke(modelData.identifier)
                                    Notifications.dismiss(card.n)
                                }
                            }
                        }
                    }
                }

                // ── Time left ───────────────────────────────────────────────
                //
                // Along the foot of the card, running down from full to
                // nothing over the five seconds; it holds while the pointer is
                // on the card.
                Rectangle {
                    visible: !card.sticky
                    anchors.left: glass.left
                    anchors.right: glass.right
                    anchors.bottom: glass.bottom
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.bottomMargin: 8
                    height: 3
                    radius: 1.5
                    color: Theme.track

                    Rectangle {
                        width: parent.width * card.remaining
                        height: parent.height
                        radius: parent.radius
                        color: Theme.alpha(Theme.foreground, countdown.paused ? 0.45 : 0.75)

                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                    }
                }
            }
        }
    }
}
