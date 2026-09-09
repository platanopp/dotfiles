import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

PanelWindow {
    id: mediaWidgetItem
    property var bar: null
    screen: bar.screen
    visible: bar.trackTitle.length > 0

    // Hidden by cutting input and drawing nothing, never by unmapping the
    // window. Toggling visible destroys the layer surface, and Hyprland
    // restacks it on the way back: the full-width bar came back above the
    // pills and swallowed every click meant for them. The blur rule ignores
    // pixels below 0.3 alpha, so a surface drawing nothing leaves no band.
    mask: bar.barHidden ? blankMask : null

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Keeps the bar up while the pointer is on it; shell.qml folds these
    // together with the reveal zone's own hover.
    readonly property bool barHovered: barHover.hovered

    HoverHandler {
        id: barHover
    }
    color: "transparent"

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        left: true
    }
    // The content inside insets itself by 12, so the window sits back by
    // that much and the drawn edge lands exactly on Hyprland's gap.
    margins.top: AppState.gapTop - 12
    // contentArea insets by 12, so this leaves a 10px gap after the pill.
    margins.left: bar ? bar.leftPillRight - 2 : 50

    Behavior on margins.left {
        NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
    }

    property bool panelOpen: false
    property real currentPosition: 0

    readonly property var player: bar ? bar.activePlayer : null
    readonly property real trackLength: player && player.length ? player.length : 0
    readonly property int playerCount: Mpris.players.values.length
    // Cycling is pointless while a preferred player holds the widget.
    readonly property bool canCyclePlayer: playerCount > 1 && bar && !bar.playerLocked

    // The sink input this player is feeding, when it has one, so the slider
    // below moves the same number the audio panel shows for the app. Null
    // for a player that dropped its stream -- a paused browser does -- which
    // is why the slider falls back to the master rather than going dead.
    //
    // Read from the last known list even while the panel is shut, so opening
    // it does not show the fallback for the moment before the first poll
    // lands. A stale id is written to at worst once, and pactl ignores it.
    readonly property var appStream: AppState.streamForPlayer(player)
    readonly property bool onAppVolume: appStream !== null

    // Held across a drag: the poll is paused while the pointer is down, so
    // this is the only thing that knows where the slider was left until
    // pactl reports back.
    property real appStreamVolume: 0
    onAppStreamChanged: if (appStream) appStreamVolume = appStream.volume

    readonly property real shownVolume: onAppVolume ? appStreamVolume : AppState.volumePercent

    function setShownVolume(fraction) {
        var v = Math.max(0, Math.min(100, Math.round(fraction * 100)))
        if (onAppVolume) {
            appStreamVolume = v
            AppState.setStreamVolumeThrottled(appStream.id, v)
        } else {
            AppState.setVolume(v)
        }
    }

    // Only the open panel draws the slider, so only the open panel needs the
    // list kept current.
    onPanelOpenChanged: panelOpen ? AppState.watchAudioStreams() : AppState.unwatchAudioStreams()

    // The capture helper only runs while the ring is both on screen and
    // moving, so nothing listens to the speakers in the background.
    readonly property bool wantSpectrum: panelOpen && !!bar && bar.isPlaying

    // Hand the cover to the colour extractor. With a bar per monitor this is
    // assigned several times with the same value, which the singleton ignores.
    readonly property string artUrl: bar ? bar.trackArtUrl : ""
    onArtUrlChanged: AlbumColors.artUrl = artUrl
    onWantSpectrumChanged: wantSpectrum ? Spectrum.subscribe() : Spectrum.unsubscribe()
    Component.onDestruction: {
        if (wantSpectrum) Spectrum.unsubscribe()
        if (panelOpen) AppState.unwatchAudioStreams()
    }

    function formatTime(secs) {
        var s = Math.max(0, Math.floor(secs))
        var m = Math.floor(s / 60)
        var r = s % 60
        return m + ":" + (r < 10 ? "0" : "") + r
    }

    function seekTo(fraction) {
        if (!player || !player.canSeek || trackLength <= 0) return
        var clamped = Math.max(0, Math.min(1, fraction))
        player.position = clamped * trackLength
        mediaWidgetItem.currentPosition = player.position
    }

    // None -> Playlist -> Track -> None
    function cycleLoop() {
        if (!player || !player.loopSupported) return
        if (player.loopState === MprisLoopState.None) player.loopState = MprisLoopState.Playlist
        else if (player.loopState === MprisLoopState.Playlist) player.loopState = MprisLoopState.Track
        else player.loopState = MprisLoopState.None
    }

    function loopIcon() {
        if (!player) return "󰑗"
        if (player.loopState === MprisLoopState.Track) return "󰑘"
        if (player.loopState === MprisLoopState.Playlist) return "󰑖"
        return "󰑗"
    }

    implicitWidth: panelOpen ? 396 : mediaWidgetRow.implicitWidth + 44
    implicitHeight: panelOpen ? Math.min(mediaContentColumn.implicitHeight + 60, 640) : 64

    Behavior on implicitWidth {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    Behavior on implicitHeight {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    Item {
        id: contentArea
        visible: !bar.barHidden
        anchors.fill: parent
        anchors.margins: 12

        Rectangle {
            id: mediaGlass
            anchors.fill: parent
            radius: mediaWidgetItem.panelOpen ? 26 : 20
            color: Theme.glass
            visible: false
            layer.enabled: true

            Behavior on radius {
                NumberAnimation { duration: 200 }
            }
        }

        MultiEffect {
            source: mediaGlass
            anchors.fill: mediaGlass
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.5
            shadowBlur: 0.7
            shadowVerticalOffset: 4
            autoPaddingEnabled: true
        }

        // ── Compact pill ─────────────────────────────────────────────────
        RowLayout {
            id: mediaWidgetRow
            anchors.centerIn: parent
            spacing: 8
            visible: !mediaWidgetItem.panelOpen
            opacity: mediaWidgetItem.panelOpen ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            Item {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32

                Rectangle {
                    id: artMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: bar.trackArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: artMask
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.track
                    visible: artImage.status !== Image.Ready

                    IconGlyph {
                        anchors.centerIn: parent
                        text: "󰎇"
                        color: Theme.textPrimary
                        size: Theme.iconSmall
                    }
                }
            }

            Column {
                spacing: 0

                Item {
                    id: titleMarquee
                    width: 180
                    height: titleText.implicitHeight
                    clip: true

                    Text {
                        id: titleText
                        text: bar.trackTitle
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontMono

                        // An animation on a property leaves that property
                        // wherever it stopped, and this one stops whenever a
                        // title is short enough not to need scrolling. So a
                        // long title that had scrolled left, followed by a
                        // short one, drew the short one off the clipped edge:
                        // the track was playing and its name was simply not
                        // there. Both handlers are needed -- one for the title
                        // changing under a stopped animation, one for the
                        // animation stopping because the new title fits.
                        onTextChanged: x = 0

                        SequentialAnimation on x {
                            running: titleText.implicitWidth > titleMarquee.width
                            onRunningChanged: if (!running) titleText.x = 0
                            loops: Animation.Infinite

                            PauseAnimation { duration: 1400 }

                            NumberAnimation {
                                from: 0
                                to: titleMarquee.width - titleText.implicitWidth
                                duration: Math.max(2200, (titleText.implicitWidth - titleMarquee.width) * 45)
                                easing.type: Easing.Linear
                            }

                            PauseAnimation { duration: 1400 }

                            NumberAnimation {
                                from: titleMarquee.width - titleText.implicitWidth
                                to: 0
                                duration: Math.max(2200, (titleText.implicitWidth - titleMarquee.width) * 45)
                                easing.type: Easing.Linear
                            }
                        }
                    }
                }

                Text {
                    text: bar.trackArtist
                    color: Theme.textSecondary
                    font.pixelSize: 10
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 180)
                }
            }
        }

        StateLayer {
            interactive: !mediaWidgetItem.panelOpen
            onTapped: mediaWidgetItem.panelOpen = true
        }

        HyprlandFocusGrab {
            windows: [mediaWidgetItem]
            active: mediaWidgetItem.panelOpen
            onCleared: mediaWidgetItem.panelOpen = false
        }

        Timer {
            interval: 1000
            repeat: true
            running: mediaWidgetItem.panelOpen && bar.isPlaying
            triggeredOnStart: true
            onTriggered: if (mediaWidgetItem.player) mediaWidgetItem.currentPosition = mediaWidgetItem.player.position
        }

        // ── Expanded panel ───────────────────────────────────────────────
        Flickable {
            visible: mediaWidgetItem.panelOpen
            opacity: mediaWidgetItem.panelOpen ? 1 : 0
            anchors.fill: parent
            anchors.margins: 18
            contentHeight: mediaContentColumn.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }

            Column {
                id: mediaContentColumn
                width: parent.width
                spacing: 16

                // Art and metadata
                RowLayout {
                    width: parent.width
                    spacing: 16

                    Item {
                        // 120 rather than 104: the extra ring gives the bars a
                        // gap from the cover and room to travel. The panel grew
                        // by the same amount so the metadata column is unchanged.
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 120

                        // Spectrum ring: each mark is a frequency band, growing
                        // outward from just past the artwork. The 24 bands are
                        // mirrored across the circle so the two halves match
                        // instead of meeting at a seam. It still turns slowly,
                        // which keeps it alive during quiet passages.
                        Item {
                            id: ring
                            anchors.fill: parent

                            readonly property int marks: 48
                            // The cover is inset 18 of a 120 box, so its edge is
                            // at radius 42. Bars start 6px clear of it and a full
                            // band stops just inside the box.
                            readonly property real base: width / 2 - 12
                            readonly property real travel: 9

                            function level(i) {
                                var b = Spectrum.bands
                                // Mirror: marks 0..23 run one way, 24..47 back.
                                var band = i < b.length ? i : ring.marks - 1 - i
                                return (band >= 0 && band < b.length) ? b[band] : 0
                            }

                            // wantSpectrum, not isPlaying. This is the panel's
                            // ring, and the panel hides by drawing nothing
                            // rather than by unmapping -- so on isPlaying alone
                            // these 48 marks kept turning behind a closed panel,
                            // dirtying the surface every frame for something
                            // nobody could see. Measured at 70% of a core in
                            // quickshell, plus Hyprland re-blurring the region,
                            // while a game wanted that CPU.
                            NumberAnimation on rotation {
                                running: mediaWidgetItem.wantSpectrum
                                from: 0
                                to: 360
                                duration: 48000
                                loops: Animation.Infinite
                            }

                            Repeater {
                                model: ring.marks

                                Rectangle {
                                    id: mark
                                    required property int index
                                    readonly property real angle: index * 2 * Math.PI / ring.marks
                                    readonly property real level: ring.level(index)

                                    // Not readonly: Behavior smooths the step
                                    // between the helper's frames.
                                    property real len: 2.5 + level * ring.travel

                                    width: 2.5
                                    height: len
                                    radius: 1.25
                                    color: Theme.alpha(AlbumColors.accent, 0.25 + level * 0.6)

                                    x: ring.width / 2 + Math.cos(angle) * (ring.base + len / 2) - width / 2
                                    y: ring.height / 2 + Math.sin(angle) * (ring.base + len / 2) - height / 2

                                    // Point the bar outward along its radius.
                                    rotation: angle * 180 / Math.PI + 90
                                    transformOrigin: Item.Center

                                    Behavior on len {
                                        NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 70 }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: bigArtMask
                            anchors.fill: parent
                            anchors.margins: 18
                            radius: width / 2
                            visible: false
                            layer.enabled: true
                        }

                        Image {
                            id: bigArtImage
                            anchors.fill: parent
                            anchors.margins: 18
                            source: bar.trackArtUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: bigArtMask
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 18
                            radius: width / 2
                            color: Theme.surfaceContainerHigh
                            visible: bigArtImage.status !== Image.Ready

                            IconGlyph {
                                anchors.centerIn: parent
                                text: "󰎇"
                                color: Theme.textSecondary
                                size: Theme.iconHero
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 3

                        Text {
                            text: bar.trackTitle
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.bold: true
                            font.family: Theme.fontMono
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: bar.trackArtist
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontMono
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: text.length > 0
                            text: mediaWidgetItem.player ? (mediaWidgetItem.player.trackAlbum || "") : ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontMono
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }

                // Seek
                Column {
                    width: parent.width
                    spacing: 5

                    Item {
                        width: parent.width
                        height: 14

                        Rectangle {
                            id: seekTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 5
                            radius: 3
                            color: Theme.track

                            Rectangle {
                                id: seekFill
                                width: mediaWidgetItem.trackLength > 0
                                    ? seekTrack.width * Math.min(1, mediaWidgetItem.currentPosition / mediaWidgetItem.trackLength)
                                    : 0
                                height: parent.height
                                radius: 3
                                color: Theme.accent
                            }

                            Rectangle {
                                width: 11
                                height: 11
                                radius: 5.5
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
                            enabled: mediaWidgetItem.player && mediaWidgetItem.player.canSeek
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPressed: mediaWidgetItem.seekTo(mouseX / width)
                            onPositionChanged: if (pressed) mediaWidgetItem.seekTo(mouseX / width)
                        }
                    }

                    RowLayout {
                        width: parent.width

                        Text {
                            text: mediaWidgetItem.formatTime(mediaWidgetItem.currentPosition)
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontMono
                            Layout.fillWidth: true
                        }

                        Text {
                            text: mediaWidgetItem.formatTime(mediaWidgetItem.trackLength)
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontMono
                        }
                    }
                }

                // Transport
                RowLayout {
                    width: parent.width
                    spacing: 6

                    IconButton {
                        icon: (mediaWidgetItem.player && mediaWidgetItem.player.shuffle) ? "󰒝" : "󰒞"
                        size: 34
                        glyphSize: Theme.iconMedium
                        iconColor: (mediaWidgetItem.player && mediaWidgetItem.player.shuffle) ? Theme.accent : Theme.textMuted
                        interactive: mediaWidgetItem.player && mediaWidgetItem.player.shuffleSupported
                        onTapped: mediaWidgetItem.player.shuffle = !mediaWidgetItem.player.shuffle
                    }

                    Item { Layout.fillWidth: true }

                    IconButton {
                        icon: "󰒮"
                        size: 38
                        glyphSize: Theme.iconLarge
                        iconColor: Theme.textPrimary
                        interactive: bar.canGoPrevious
                        onTapped: mediaWidgetItem.player.previous()
                    }

                    // Play sits in a filled circle, as the primary action.
                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: 24
                        color: Theme.accent
                        scale: playState.pressed ? 0.94 : 1.0

                        Behavior on scale {
                            NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad }
                        }

                        IconGlyph {
                            anchors.centerIn: parent
                            text: bar.isPlaying ? "󰏤" : "󰐊"
                            color: Theme.accentText
                            size: Theme.iconLarge
                        }

                        StateLayer {
                            id: playState
                            tint: Theme.accentText
                            interactive: bar.canTogglePlaying
                            onTapped: mediaWidgetItem.player.togglePlaying()
                        }
                    }

                    IconButton {
                        icon: "󰒭"
                        size: 38
                        glyphSize: Theme.iconLarge
                        iconColor: Theme.textPrimary
                        interactive: bar.canGoNext
                        onTapped: mediaWidgetItem.player.next()
                    }

                    Item { Layout.fillWidth: true }

                    IconButton {
                        icon: mediaWidgetItem.loopIcon()
                        size: 34
                        glyphSize: Theme.iconMedium
                        iconColor: (mediaWidgetItem.player && mediaWidgetItem.player.loopState !== MprisLoopState.None)
                            ? Theme.accent : Theme.textMuted
                        interactive: mediaWidgetItem.player && mediaWidgetItem.player.loopSupported
                        onTapped: mediaWidgetItem.cycleLoop()
                    }
                }

                // This player's own volume -- the very slider the audio
                // panel shows for the app, writing to the same sink input.
                //
                // It drove the master volume before, which was at least one
                // number rather than two, but it meant turning the music down
                // also turned down everything else. It cannot drive the MPRIS
                // volume either: for Spotify that is a third quantity again,
                // reading 0.72 while its stream sat at 0.69.
                //
                // So the widget finds the app's stream and moves that. The
                // panel's slider for the same app is then the same slider,
                // and neither has to be told when the other moves: both read
                // the one list AppState polls.
                RowLayout {
                    width: parent.width
                    spacing: 10
                    visible: mediaWidgetItem.player !== null

                    IconGlyph {
                        text: mediaWidgetItem.shownVolume > 50 ? "󰕾" : "󰖀"
                        color: Theme.textSecondary
                        size: Theme.iconSmall
                    }

                    Item {
                        Layout.fillWidth: true
                        height: 14

                        Rectangle {
                            id: volTrack
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.track

                            Rectangle {
                                width: volTrack.width * (mediaWidgetItem.shownVolume / 100)
                                height: parent.height
                                radius: 2
                                color: Theme.alpha(Theme.accent, 0.8)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // The list is polled on a timer, and a poll that
                            // lands between the write and pactl catching up
                            // reports the old volume -- which is the slider
                            // jumping backwards under the pointer. Held off
                            // for the length of the drag, the same way the
                            // audio panel's sliders do it.
                            onPressed: {
                                AppState.audioStreamsDragging = true
                                mediaWidgetItem.setShownVolume(mouseX / width)
                            }
                            onPositionChanged: if (pressed) mediaWidgetItem.setShownVolume(mouseX / width)
                            onReleased: AppState.audioStreamsDragging = false
                            onCanceled: AppState.audioStreamsDragging = false
                        }
                    }

                    // Says which volume this is. A player that has dropped
                    // its stream has no per-app level left to show, and the
                    // row falls back to the master rather than to nothing --
                    // worth saying, since the two behave differently.
                    Text {
                        text: Math.round(mediaWidgetItem.shownVolume) + "%"
                            + (mediaWidgetItem.onAppVolume ? "" : " · sistema")
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontMono
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.outline
                }

                // Which player this is; tapping cycles when several are open.
                Rectangle {
                    width: parent.width
                    height: 34
                    radius: 12
                    color: Theme.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        IconImage {
                            visible: source.toString().length > 0
                            implicitSize: 16
                            mipmap: true
                            source: {
                                if (!mediaWidgetItem.player) return ""
                                var entry = mediaWidgetItem.player.desktopEntry || ""
                                var name = (mediaWidgetItem.player.identity || "").toLowerCase()
                                // Same guessing the audio panel does: the entry
                                // name and the theme's icon name often differ.
                                return AppState.resolveAppIcon([entry, name, name + "-browser",
                                                                name.split(" ").pop()])
                            }
                        }

                        Text {
                            text: mediaWidgetItem.player ? (mediaWidgetItem.player.identity || "Player") : ""
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontMono
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: mediaWidgetItem.playerCount > 1
                            text: (bar.activePlayerIndex + 1) + "/" + mediaWidgetItem.playerCount
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontMono
                        }

                        IconGlyph {
                            visible: mediaWidgetItem.canCyclePlayer
                            text: "󰅀"
                            color: Theme.textMuted
                            size: Theme.iconSmall
                        }
                    }

                    StateLayer {
                        interactive: mediaWidgetItem.canCyclePlayer
                        onTapped: bar.cyclePlayer()
                    }
                }
            }
        }
    }
}
