import QtQuick
import Quickshell.Widgets
import qs.components
import qs.config
import qs.desktop
import qs.services

// What is playing: the cover, the title and artist, how far along, and the
// three controls. It follows the same player as the bar's media pill (the
// bar's activePlayer: osu, then Spotify, then whatever else), so the two
// never disagree about what "the music" is.
WidgetCard {
    id: root

    readonly property var player: root.bar ? root.bar.activePlayer : null
    readonly property bool playing: root.bar ? root.bar.isPlaying : false
    readonly property real length: root.player && root.player.length > 0 ? root.player.length : 0
    property real position: 0

    function formatTime(secs) {
        var s = Math.max(0, Math.floor(secs))
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }

    // MPRIS does not announce the position as it moves; it is asked for,
    // once a second, only while playing and while the desktop can be seen.
    Timer {
        interval: 1000
        repeat: true
        running: root.live && root.playing
        triggeredOnStart: true
        onTriggered: if (root.player) root.position = root.player.position
    }

    onPlayerChanged: root.position = root.player ? root.player.position : 0

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        ClippingRectangle {
            width: parent.width
            height: parent.width
            radius: Theme.radiusLarge
            color: Theme.surfaceContainer

            Image {
                id: art
                anchors.fill: parent
                source: root.bar ? root.bar.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 448
                visible: status === Image.Ready
            }

            IconGlyph {
                anchors.centerIn: parent
                visible: art.status !== Image.Ready
                text: "󰎇"
                color: Theme.textMuted
                size: 44
            }
        }

        Column {
            width: parent.width
            leftPadding: 4
            rightPadding: 4
            spacing: 2

            Text {
                width: parent.width - 8
                text: root.player ? (root.bar.trackTitle || "Unknown track") : "Nothing playing"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.weight: Font.Bold
                font.family: Theme.fontText
                elide: Text.ElideRight
            }

            Text {
                width: parent.width - 8
                text: root.player ? (root.bar.trackArtist || root.player.identity || "")
                                  : "Play something and it shows here."
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        // Progress, in the accent: how far along is the live part of this card.
        Column {
            width: parent.width
            leftPadding: 4
            rightPadding: 4
            spacing: 4
            visible: root.length > 0

            Item {
                width: parent.width - 8
                height: 12

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: height / 2
                    color: Theme.track

                    Rectangle {
                        width: track.width * Math.min(1, root.position / root.length)
                        height: parent.height
                        radius: height / 2
                        color: Theme.accent
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.player !== null && root.player.canSeek
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: mouse => {
                        root.player.position = Math.max(0, Math.min(1, mouse.x / width)) * root.length
                        root.position = root.player.position
                    }
                }
            }

            Item {
                width: parent.width - 8
                height: elapsed.implicitHeight

                Text {
                    id: elapsed
                    text: root.formatTime(root.position)
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }

                Text {
                    anchors.right: parent.right
                    text: root.formatTime(root.length)
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        spacing: 18

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "󰒮"
            size: 36
            glyphSize: Theme.iconLarge
            iconColor: Theme.textPrimary
            interactive: root.bar ? root.bar.canGoPrevious : false
            onTapped: root.player.previous()
        }

        // Play in the text colour, as in the media panel: the accent marks
        // state, and this button is there whether anything plays or not.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 46
            height: 46
            radius: height / 2
            color: root.player ? Theme.textPrimary : Theme.surfaceContainerHigh
            scale: playState.pressed ? 0.94 : 1

            Behavior on scale { Elastic { small: true } }

            IconGlyph {
                anchors.centerIn: parent
                text: root.playing ? "󰏤" : "󰐊"
                color: root.player ? Theme.inkOn(Theme.textPrimary) : Theme.textMuted
                size: Theme.iconLarge
            }

            StateLayer {
                id: playState
                tint: Theme.inkOn(Theme.textPrimary)
                interactive: root.bar ? root.bar.canTogglePlaying : false
                onTapped: root.player.togglePlaying()
            }
        }

        IconButton {
            anchors.verticalCenter: parent.verticalCenter
            icon: "󰒭"
            size: 36
            glyphSize: Theme.iconLarge
            iconColor: Theme.textPrimary
            interactive: root.bar ? root.bar.canGoNext : false
            onTapped: root.player.next()
        }
    }
}
