import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
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
    mask: bar.barHidden ? blankMask : stageMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Input only where the pill is (see PillStage).
    Region {
        id: stageMask
        item: stage
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
    margins.top: Math.max(0, AppState.gapTop - 12)
    // contentArea insets by 12, so this leaves a 10px gap after the pill.
    // Not animated here: the workspaces pill it follows animates its own
    // width, and a second animation chasing that one only made this lag.
    margins.left: bar ? bar.leftPillRight - 2 : 50

    property bool panelOpen: false

    // qs ipc call media toggle (see AppState): only the screen that asked.
    Connections {
        target: AppState
        function onMediaRequested(how, screenName) {
            if (how === "close") { mediaWidgetItem.panelOpen = false; return }
            if (mediaWidgetItem.screen && screenName.length > 0 && mediaWidgetItem.screen.name !== screenName) return
            mediaWidgetItem.panelOpen = how === "open" ? true : !mediaWidgetItem.panelOpen
        }
    }
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

    // The pill's box, animated inside a window that is not (see PillStage).
    PillStage {
        id: stage
        anchors.top: parent.top
        anchors.left: parent.left
        targetWidth: mediaWidgetItem.panelOpen ? 396
                   : mediaWidgetRow.implicitWidth + 24 + 74 + Theme.pillPaddingH
        targetHeight: mediaWidgetItem.panelOpen ? Math.min(mediaContentColumn.implicitHeight + 60, 640) : 64
    }

    implicitWidth: stage.windowWidth
    implicitHeight: stage.windowHeight

    Item {
        id: contentArea
        visible: !bar.barHidden
        anchors.fill: stage
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
        //
        // The cover fills the pill's left end, full height and following
        // its rounded edge, and fades out into the glass towards the title.
        // How far along the song is runs as a hairline along the foot.
        // Paused, the cover steps back under a pause mark and the line dims.
        Item {
            id: compactArt
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            // Only the pill's end: the cover has faded to nothing before the
            // title starts, so a pale cover never sits under the text.
            width: 70
            visible: opacity > 0
            opacity: mediaWidgetItem.panelOpen ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            readonly property bool hasArt: coverImage.status === Image.Ready

            // What the cover is cut to: the pill's left end, solid at the
            // edge and clear by the right. Only its alpha is used.
            Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: height / 2
                visible: false
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
                    GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.85) }
                    GradientStop { position: 0.8; color: Qt.rgba(1, 1, 1, 0.2) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
            }

            Image {
                id: coverImage
                anchors.fill: parent
                source: bar.trackArtUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 224
                visible: false
            }

            // OpacityMask, not MultiEffect's mask: MultiEffect thresholds
            // the mask, and would cut the gradient to a hard edge (or, set
            // soft, not cut at all). This takes the gradient's alpha as it is.
            OpacityMask {
                anchors.fill: parent
                visible: compactArt.hasArt
                source: coverImage
                maskSource: coverMask
                cached: false

                // Paused: the cover steps back.
                layer.enabled: true
                layer.effect: MultiEffect {
                    brightness: bar.isPlaying ? 0 : -0.35
                    saturation: bar.isPlaying ? 0 : -0.4

                    Behavior on brightness { NumberAnimation { duration: Theme.durMedium } }
                    Behavior on saturation { NumberAnimation { duration: Theme.durMedium } }
                }
            }

            // No cover: a note where it would be.
            IconGlyph {
                visible: !compactArt.hasArt
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "󰎇"
                color: Theme.textSecondary
                size: Theme.iconMedium
            }

            // Paused: a mark over the cover.
            Rectangle {
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                radius: 11
                color: Qt.rgba(0, 0, 0, 0.5)
                opacity: bar.isPlaying || !compactArt.hasArt ? 0 : 1
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }

                IconGlyph {
                    anchors.centerIn: parent
                    text: "\u{F03E4}"
                    color: "#ffffff"
                    size: Theme.iconTiny
                }
            }
        }

        // How far along: a hairline along the foot of the pill, inside its
        // rounded ends.
        Item {
            id: compactProgress
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 3
            height: 2
            visible: opacity > 0 && progress > 0
            opacity: mediaWidgetItem.panelOpen ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            readonly property real progress: mediaWidgetItem.trackLength > 0
                ? Math.max(0, Math.min(1, mediaWidgetItem.currentPosition / mediaWidgetItem.trackLength)) : 0

            Rectangle {
                anchors.fill: parent
                radius: 1
                color: Theme.alpha(Theme.foreground, 0.12)
            }

            Rectangle {
                width: parent.width * compactProgress.progress
                height: parent.height
                radius: 1
                color: Theme.alpha(Theme.foreground, bar.isPlaying ? 0.75 : 0.35)

                Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
            }
        }

        RowLayout {
            id: mediaWidgetRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // The title starts where the cover has gone.
            anchors.leftMargin: 74
            spacing: 10
            visible: !mediaWidgetItem.panelOpen
            opacity: mediaWidgetItem.panelOpen ? 0 : 1

            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            Column {
                spacing: 0

                Item {
                    id: titleMarquee
                    // As wide as the title, up to the cap. A fixed 180 left a
                    // short title ("Remember Me") beside an empty strip.
                    width: Math.min(titleText.implicitWidth, 180)
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
            // The compact pill's progress line reads it too, so it runs
            // whenever something is playing, not only with the panel open.
            running: bar.isPlaying && !bar.barHidden
            triggeredOnStart: true
            onTriggered: if (mediaWidgetItem.player) mediaWidgetItem.currentPosition = mediaWidgetItem.player.position
        }

        // ── Expanded panel ───────────────────────────────────────────────
        //
        // The cover across the top of the panel, edge to edge under the
        // glass's rounded corners, fading down into it. The spectrum rises
        // from where it fades; the title and the rest start below, where the
        // picture has gone -- the same rule as the pill: no text on the cover.
        Item {
            id: hero
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 230
            visible: opacity > 0
            opacity: mediaWidgetItem.panelOpen ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }

            readonly property bool hasArt: heroImage.status === Image.Ready

            Rectangle {
                id: heroMask
                anchors.fill: parent
                radius: 26
                visible: false
                gradient: Gradient {
                    // Gone by 0.85 -- 195px down, just above the title.
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
                    GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0.9) }
                    GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.22) }
                    GradientStop { position: 0.85; color: Qt.rgba(1, 1, 1, 0) }
                }
            }

            Image {
                id: heroImage
                anchors.fill: parent
                source: bar.trackArtUrl
                fillMode: Image.PreserveAspectCrop
                // The middle of a square cover, not its top edge.
                verticalAlignment: Image.AlignVCenter
                asynchronous: true
                sourceSize.width: 512
                visible: false
            }

            OpacityMask {
                anchors.fill: parent
                visible: hero.hasArt
                source: heroImage
                maskSource: heroMask
                cached: false

                layer.enabled: true
                layer.effect: MultiEffect {
                    brightness: bar.isPlaying ? 0 : -0.3
                    saturation: bar.isPlaying ? 0 : -0.35

                    Behavior on brightness { NumberAnimation { duration: Theme.durMedium } }
                    Behavior on saturation { NumberAnimation { duration: Theme.durMedium } }
                }
            }

            // No cover: the note, large, where it would be.
            IconGlyph {
                visible: !hero.hasArt
                anchors.horizontalCenter: parent.horizontalCenter
                y: 64
                text: "󰎇"
                color: Theme.textMuted
                size: 44
            }

            // The spectrum: bars across the width, rising from where the
            // cover fades out, in the album's colour. Mirrored about the
            // middle, low bands at the centre.
            Row {
                id: bars
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 34
                spacing: 3
                visible: mediaWidgetItem.wantSpectrum

                readonly property int count: 48

                function level(i) {
                    var b = Spectrum.bands
                    var half = bars.count / 2
                    var band = i < half ? half - 1 - i : i - half
                    return (band >= 0 && band < b.length) ? b[band] : 0
                }

                Repeater {
                    model: bars.count

                    Rectangle {
                        required property int index
                        readonly property real level: bars.level(index)
                        // Not readonly: Behavior smooths the step between the
                        // helper's frames.
                        property real len: 2 + level * 34

                        anchors.bottom: parent.bottom
                        width: 3
                        height: len
                        radius: 1.5
                        color: Theme.alpha(AlbumColors.accent, 0.35 + level * 0.6)

                        Behavior on len {
                            NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 70 }
                        }
                    }
                }
            }
        }

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

                // Clear of the cover: it has faded out by here.
                Item {
                    width: parent.width
                    height: 180
                }

                ColumnLayout {
                    width: parent.width
                    spacing: 3

                    Text {
                        text: bar.trackTitle
                        color: Theme.textPrimary
                        font.pixelSize: 17
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

                    SettingsSlider {
                        Layout.fillWidth: true
                        compact: true
                        live: true
                        from: 0; to: 100; step: 1
                        value: mediaWidgetItem.shownVolume
                        // The list is polled on a timer, and a poll that lands
                        // between the write and pactl catching up reports the
                        // old volume -- the slider jumping backwards under the
                        // pointer. Held off for the length of the drag, the
                        // same way the audio panel's sliders do it.
                        onDraggingChanged: AppState.audioStreamsDragging = dragging
                        onMoved: v => mediaWidgetItem.setShownVolume(v / 100)
                    }

                    // Says which volume this is. A player that has dropped
                    // its stream has no per-app level left to show, and the
                    // row falls back to the master rather than to nothing --
                    // worth saying, since the two behave differently.
                    Text {
                        text: Math.round(mediaWidgetItem.shownVolume) + "%"
                            + (mediaWidgetItem.onAppVolume ? "" : " · system")
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
