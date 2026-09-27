import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

// The notification centre: what the bell in the control pill opens. Every
// notification that arrived and has not been cleared, newest first -- a
// toast timing out moves it off the screen, not out of here (see
// Notifications). Tap a card to run its default action; the cross clears
// it. Do not disturb is switched from the header.
Item {
    id: centre

    // How tall the centre wants to be, for the pill to grow to.
    readonly property real wantedHeight: header.implicitHeight + 14
        + (Notifications.count > 0 ? Math.min(list.contentHeight, 560) : empty.implicitHeight + 24)

    // For "5m ago"; ticks while the centre is up.
    property date now: new Date()

    Timer {
        running: centre.visible
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: centre.now = new Date()
    }

    function ago(t) {
        var s = Math.max(0, Math.floor((centre.now - t) / 1000))
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    function iconFor(n) {
        if (n.image.length > 0) return n.image
        if (n.appIcon.length > 0) return Quickshell.iconPath(n.appIcon, true)
        return Quickshell.iconPath(n.appName.toLowerCase(), true)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        // ── Header ───────────────────────────────────────────────────────
        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Notifications"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.bold: true
                font.family: Theme.fontMono
            }

            Rectangle {
                visible: Notifications.count > 0
                implicitWidth: countText.implicitWidth + 14
                implicitHeight: 20
                radius: 10
                color: Theme.surfaceContainerHigh

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: Notifications.count
                    color: Theme.textSecondary
                    font.pixelSize: 10
                    font.bold: true
                    font.family: Theme.fontMono
                }
            }

            Item { Layout.fillWidth: true }

            // Do not disturb: no toasts, everything still lands here.
            IconButton {
                icon: Notifications.dnd ? "\u{F009B}" : "\u{F009C}"
                size: 30
                glyphSize: Theme.iconMedium
                iconColor: Notifications.dnd ? Theme.textPrimary : Theme.textMuted
                onTapped: AppState.toggleDnd()

                Rectangle {
                    anchors.fill: parent
                    z: -1
                    radius: width / 2
                    color: Theme.surfaceContainerHigh
                    visible: Notifications.dnd
                }
            }

            PillButton {
                visible: Notifications.count > 0
                text: "Clear all"
                onClicked: Notifications.dismissAll()
            }
        }

        // ── Nothing here ─────────────────────────────────────────────────
        Column {
            id: empty
            visible: Notifications.count === 0
            Layout.fillWidth: true
            Layout.topMargin: 12
            spacing: 8

            IconGlyph {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifications.dnd ? "\u{F009B}" : "\u{F0E11}"
                size: 30
                color: Theme.textMuted
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Notifications.dnd ? "Do not disturb is on" : "All caught up"
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontMono
            }
        }

        // ── The list ─────────────────────────────────────────────────────
        ListView {
            id: list
            visible: Notifications.count > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: Notifications.list

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durMedium }
                NumberAnimation { property: "x"; from: 30; to: 0; duration: Theme.durLong; easing.type: Easing.OutCubic }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.durShort }
                NumberAnimation { property: "x"; to: 60; duration: Theme.durMedium; easing.type: Easing.InCubic }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }

            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var n: card.modelData
                readonly property var defaultAction: {
                    for (var i = 0; i < card.n.actions.length; i++)
                        if (card.n.actions[i].identifier === "default") return card.n.actions[i]
                    return null
                }

                width: ListView.view.width
                implicitHeight: body.implicitHeight + 24
                radius: 16
                color: cardHover.hovered && card.defaultAction ? Theme.surfaceContainerHigh : Theme.surfaceContainer

                Behavior on color { ColorAnimation { duration: Theme.durShort } }

                HoverHandler { id: cardHover; cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor }

                // The default action is what tapping a notification means;
                // having done it, the notification has served its purpose.
                TapHandler {
                    enabled: card.defaultAction !== null
                    onTapped: {
                        card.n.invoke("default")
                        Notifications.dismiss(card.n)
                    }
                }

                // Critical, marked down the leading edge like the toast.
                Rectangle {
                    visible: card.n.urgency === NotificationUrgency.Critical
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    width: 3
                    radius: 2
                    color: Theme.error
                }

                RowLayout {
                    id: body
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    anchors.leftMargin: 14
                    spacing: 12

                    ClippingRectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 9
                        color: Theme.surfaceContainerHigh

                        IconImage {
                            id: appImage
                            anchors.fill: parent
                            source: centre.iconFor(card.n)
                            mipmap: true
                            visible: status === Image.Ready
                        }

                        IconGlyph {
                            anchors.centerIn: parent
                            visible: appImage.status !== Image.Ready
                            text: "\u{F009A}"
                            size: Theme.iconSmall
                            color: Theme.textMuted
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: (card.n.appName || "Notification") + "  ·  " + centre.ago(card.n.time)
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
                                opacity: cardHover.hovered ? 1 : 0.4
                                onTapped: Notifications.dismiss(card.n)

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

                        // The rest of its actions; "default" is the card itself.
                        Flow {
                            visible: card.n.actions.some(a => a.identifier !== "default")
                            Layout.fillWidth: true
                            Layout.topMargin: 6
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
                }
            }
        }
    }
}
