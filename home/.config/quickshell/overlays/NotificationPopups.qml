import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Toasts: how a notification arrives, stacked under the bar's right end in its glass. Five seconds
// each (the line along the foot shows what's left), then off to the centre; hover or drag holds it,
// the cross or a drag right sends it on, a tap runs it. Critical ones stay until dealt with.
PanelWindow {
    id: popups

    property var bar: null
    screen: bar ? bar.screen : null

    readonly property int cardWidth: 372 - 24
    readonly property int lifetime: Notifications.lifetime

    // What a card shows between its notification closing and the card going, so no
    // binding reads a field of nothing.
    readonly property var emptyNotif: ({ summary: "", body: "", appName: "", appIcon: "", image: "",
                                         actions: [], urgency: NotificationUrgency.Normal,
                                         invoke: function () {} })

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        right: true
    }
    // Under the pills by the gap they keep between each other, right edge in
    // line; 12 is the content inset.
    margins.top: Hypr.gapTop + 40 + 10 - 12
    margins.right: Hypr.gapRight - 12

    // Only the focused monitor draws the stack, or every monitor would show the same notification.
    readonly property bool onFocusedMonitor: {
        if (!bar || !bar.monitor) return false
        var focused = Hyprland.focusedMonitor
        return !!focused && focused.id === bar.monitor.id
    }

    visible: Notifications.popups.count > 0 && onFocusedMonitor
    color: "transparent"

    // A fixed size, never animated (see PillStage); the stack moves inside, input is kept to it.
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
            Elastic { properties: "y"; small: true }
        }

        Repeater {
            model: Notifications.popups

            Item {
                id: card
                required property int key
                required property int index
                // Held: an app closing its notification drops it from Notifications at once,
                // and the card still has to leave.
                property var live: null
                readonly property var current: Notifications.get(card.key)
                onCurrentChanged: if (card.current) card.live = card.current
                Component.onCompleted: {
                    card.live = card.current
                    entrance.start()
                }
                readonly property var n: card.live || popups.emptyNotif

                // Only the newest few show; the rest wait with their time not running.
                readonly property bool shown: card.index < Notifications.maxVisible && card.live !== null
                visible: card.shown
                width: popups.cardWidth
                // Collapses on the way out, so the cards below slide up instead of jumping.
                property real collapse: 1
                height: (card.shown ? glass.height : 0) * card.collapse

                // Leaving: off to the right and fading, then its space closes; then
                // Notifications drops the row (finishLeave).
                readonly property bool leaving: !!card.live && card.live.leaving
                onLeavingChanged: {
                    if (card.leaving) exit.restart()
                    else if (exit.running) {           // raised again: back in
                        exit.stop()
                        card.collapse = 1
                        card.opacity = 1
                        card.x = 0
                    }
                }

                SequentialAnimation {
                    id: exit
                    ParallelAnimation {
                        NumberAnimation { target: card; property: "x"; to: 90; duration: 240; easing.type: Easing.InCubic }
                        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InQuad }
                    }
                    NumberAnimation { target: card; property: "collapse"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                    ScriptAction { script: Notifications.finishLeave(card.key) }
                }

                readonly property bool sticky: card.n.urgency === NotificationUrgency.Critical
                readonly property var defaultAction: {
                    for (var i = 0; i < card.n.actions.length; i++)
                        if (card.n.actions[i].identifier === "default") return card.n.actions[i]
                    return null
                }

                // Its own time, kept on the notification (expiresAt) so a rebuilt card can't
                // restart it. Starts when first shown, pauses while hovered or dragged, and on
                // running out the toast leaves for the centre.
                readonly property bool held: hover.hovered || drag.active
                property real remaining: 1

                function tick() {
                    var n = card.live
                    if (!n || card.sticky) return
                    var now = Date.now()
                    if (n.expiresAt === 0) n.expiresAt = now + popups.lifetime
                    if (card.held) {
                        if (n.pausedAt === 0) n.pausedAt = now
                        return
                    }
                    if (n.pausedAt !== 0) {
                        n.expiresAt += now - n.pausedAt
                        n.pausedAt = 0
                    }
                    card.remaining = Math.max(0, Math.min(1, (n.expiresAt - now) / popups.lifetime))
                    // Off the screen, into the centre -- not gone.
                    if (card.remaining <= 0) Notifications.expire(n)
                }

                Timer {
                    running: card.shown && !card.sticky
                    interval: 30
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: card.tick()
                }
                onHeldChanged: card.tick()

                // Entrance: in from the right, settling.
                opacity: 0
                x: 48

                ParallelAnimation {
                    id: entrance
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.durMedium }
                    Elastic { target: card; property: "x"; to: 0 }
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

                // Drag right past a third of the card to send it on, like the cross.
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

                // The glass, as the bar's pills have it
                Rectangle {
                    id: glass
                    width: parent.width
                    height: content.implicitHeight + 30
                    radius: Theme.radiusXLarge
                    color: Theme.surface
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    source: glass
                    anchors.fill: glass
                    shadowEnabled: true
                    shadowColor: Theme.shadow
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
                            radius: Theme.radiusMedium
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
                                    font.family: Theme.fontText
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
                                font.family: Theme.fontText
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
                                font.family: Theme.fontText
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

                // Time left, along the foot: runs down over the five seconds
                // and holds while hovered.
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
                        color: Theme.alpha(Theme.foreground, card.held ? 0.45 : 0.75)

                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                    }
                }
            }
        }
    }
}
