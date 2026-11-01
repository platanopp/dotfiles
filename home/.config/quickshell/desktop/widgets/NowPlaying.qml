import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.desktop
import qs.services

// The bar's media panel left open on the desktop, following the same player
// as the bar's pill (activePlayer).
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

    function seekTo(fraction) {
        if (!root.player || !root.player.canSeek || root.length <= 0) return
        root.player.position = Math.max(0, Math.min(1, fraction)) * root.length
        root.position = root.player.position
    }

    // None -> Playlist -> Track -> None, as in the panel.
    function cycleLoop() {
        if (!root.player || !root.player.loopSupported) return
        if (root.player.loopState === MprisLoopState.None) root.player.loopState = MprisLoopState.Playlist
        else if (root.player.loopState === MprisLoopState.Playlist) root.player.loopState = MprisLoopState.Track
        else root.player.loopState = MprisLoopState.None
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

    // The cover, masked by a gradient so it is gone before the title starts; paused, it steps back.
    // The mask is cached and redrawn only when the cover changes.
    Item {
        id: hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 200

        readonly property bool hasArt: cover.status === Image.Ready

        Rectangle {
            id: fade
            anchors.fill: parent
            radius: root.radius
            visible: false
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
                GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0.9) }
                GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.22) }
                GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0) }
            }
        }

        Image {
            id: cover
            anchors.fill: parent
            source: root.bar ? root.bar.trackArtUrl : ""
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignVCenter
            asynchronous: true
            sourceSize.width: 512
            visible: false
        }

        OpacityMask {
            anchors.fill: parent
            visible: hero.hasArt
            source: cover
            maskSource: fade
            cached: true
            opacity: root.playing ? 1 : 0.55

            Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }
        }

        // No cover: the note, large, where it would be.
        IconGlyph {
            visible: !hero.hasArt
            anchors.horizontalCenter: parent.horizontalCenter
            y: 56
            text: "󰎇"
            color: Theme.textMuted
            size: 44
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // Clear of the cover: it has faded out by here.
        Item { Layout.preferredHeight: 136 }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: root.player ? (root.bar.trackTitle || "Unknown track") : "Nothing playing"
                color: Theme.textPrimary
                font.pixelSize: 17
                font.bold: true
                font.family: Theme.fontText
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.player ? (root.bar.trackArtist || root.player.identity || "")
                                  : "Play something and it shows here."
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        // Seek. Kept in the layout with nothing to seek, so the controls do
        // not jump when a song starts.
        Column {
            Layout.fillWidth: true
            spacing: 5
            opacity: root.length > 0 ? 1 : 0

            Item {
                width: parent.width
                height: 14

                Rectangle {
                    id: seekTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5
                    radius: height / 2
                    color: Theme.track

                    Rectangle {
                        id: seekFill
                        width: root.length > 0 ? seekTrack.width * Math.min(1, root.position / root.length) : 0
                        height: parent.height
                        radius: height / 2
                        color: Theme.accent
                    }

                    Rectangle {
                        width: 11
                        height: 11
                        radius: height / 2
                        color: Theme.textPrimary
                        visible: seekArea.containsMouse || seekArea.pressed
                        anchors.verticalCenter: parent.verticalCenter
                        x: seekFill.width - width / 2
                    }
                }

                MouseArea {
                    id: seekArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player !== null && root.player.canSeek && root.length > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: root.seekTo(mouseX / width)
                    onPositionChanged: if (pressed) root.seekTo(mouseX / width)
                }
            }

            RowLayout {
                width: parent.width

                Text {
                    Layout.fillWidth: true
                    text: root.formatTime(root.position)
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }

                Text {
                    text: root.formatTime(root.length)
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }
            }
        }

        // Transport
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            IconButton {
                icon: root.player && root.player.shuffle ? "󰒝" : "󰒞"
                size: 34
                glyphSize: Theme.iconMedium
                iconColor: root.player && root.player.shuffle ? Theme.accent : Theme.textMuted
                interactive: root.player !== null && root.player.shuffleSupported
                onTapped: root.player.shuffle = !root.player.shuffle
            }

            Item { Layout.fillWidth: true }

            IconButton {
                icon: "󰒮"
                size: 38
                glyphSize: Theme.iconLarge
                iconColor: Theme.textPrimary
                interactive: root.bar ? root.bar.canGoPrevious : false
                onTapped: root.player.previous()
            }

            // Play in a filled circle, text colour, as in the panel: the accent marks state.
            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: height / 2
                color: root.player ? Theme.textPrimary : Theme.surfaceContainerHigh
                scale: playState.pressed ? 0.94 : 1

                Behavior on scale {
                    NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad }
                }

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
                icon: "󰒭"
                size: 38
                glyphSize: Theme.iconLarge
                iconColor: Theme.textPrimary
                interactive: root.bar ? root.bar.canGoNext : false
                onTapped: root.player.next()
            }

            Item { Layout.fillWidth: true }

            IconButton {
                icon: !root.player ? "󰑗"
                    : root.player.loopState === MprisLoopState.Track ? "󰑘"
                    : root.player.loopState === MprisLoopState.Playlist ? "󰑖" : "󰑗"
                size: 34
                glyphSize: Theme.iconMedium
                iconColor: root.player && root.player.loopState !== MprisLoopState.None ? Theme.accent : Theme.textMuted
                interactive: root.player !== null && root.player.loopSupported
                onTapped: root.cycleLoop()
            }
        }
    }
}
