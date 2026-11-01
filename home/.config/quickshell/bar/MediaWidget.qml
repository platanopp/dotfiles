import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

PanelWindow {
    id: mediaWidgetItem
    property var bar: null
    screen: bar.screen
    visible: bar.trackTitle.length > 0

    // Hidden by cutting input and drawing nothing, never by unmapping: a remapped layer is
    // restacked above the pills and swallowed their clicks. The blur rule ignores pixels
    // under 0.3 alpha, so nothing shows.
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

    // Keeps the bar up while hovered; shell.qml folds these together with the reveal zone's hover.
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
    // The content insets by 12, so the window sits back that much and the
    // drawn edge lands on Hyprland's gap.
    margins.top: Math.max(0, Hypr.gapTop - 12)
    // contentArea insets by 12, leaving a 10px gap after the pill. Not animated: the workspaces
    // pill animates its own width, and a second animation chasing it lagged.
    margins.left: bar ? bar.leftPillRight - 2 : 50

    property bool panelOpen: false

    // Escape closes it (Panels.dismissPanels, bound while any panel is up).
    readonly property bool escapeOpen: mediaWidgetItem.panelOpen
    readonly property string escapeKey: "media:" + (mediaWidgetItem.screen ? mediaWidgetItem.screen.name : "")
    onEscapeOpenChanged: Panels.setPanelOpen(mediaWidgetItem.escapeKey, mediaWidgetItem.escapeOpen)

    Connections {
        target: Panels
        function onDismissRequested() { mediaWidgetItem.panelOpen = false }
    }

    // qs ipc call media toggle (see Panels): only the screen that asked.
    Connections {
        target: Panels
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

    // The sink input this player feeds, so the slider moves the number the audio panel shows for
    // the app; null when the player dropped its stream (a paused browser), then the slider falls
    // back to master. Read even while shut.
    readonly property var appStream: Audio.streamForPlayer(player)
    readonly property bool onAppVolume: appStream !== null

    // Held across a drag: the poll pauses while the pointer is down, so this alone
    // knows where the slider was left.
    property real appStreamVolume: 0
    onAppStreamChanged: if (appStream) appStreamVolume = appStream.volume

    readonly property real shownVolume: onAppVolume ? appStreamVolume : Audio.volumePercent

    function setShownVolume(fraction) {
        var v = Math.max(0, Math.min(100, Math.round(fraction * 100)))
        if (onAppVolume) {
            appStreamVolume = v
            Audio.setStreamVolumeThrottled(appStream.id, v)
        } else {
            Audio.setVolume(v)
        }
    }

    // Only the open panel draws the slider, so only then is the list kept current.
    onPanelOpenChanged: {
        panelOpen ? Audio.watchAudioStreams() : Audio.unwatchAudioStreams()
        // The pill's cover and title: gone at once when the panel opens, back once it
        // has mostly shut (see compactArt).
        if (panelOpen) {
            compactBack.stop()
            compactShown = false
        } else {
            compactBack.restart()
        }
    }

    property bool compactShown: true

    Timer {
        id: compactBack
        interval: mediaWidgetItem.compactDelay
        onTriggered: mediaWidgetItem.compactShown = true
    }

    // The capture helper runs only while the ring is on screen and moving.
    readonly property bool wantSpectrum: panelOpen && !!bar && bar.isPlaying

    // Hands the cover to the colour extractor; the same value from every bar
    // is ignored by the singleton.
    readonly property string artUrl: bar ? bar.trackArtUrl : ""
    onArtUrlChanged: AlbumColors.artUrl = artUrl
    onWantSpectrumChanged: wantSpectrum ? Spectrum.subscribe() : Spectrum.unsubscribe()
    Component.onDestruction: {
        if (mediaWidgetItem.escapeOpen) Panels.setPanelOpen(mediaWidgetItem.escapeKey, false)
        if (wantSpectrum) Spectrum.unsubscribe()
        if (panelOpen) Audio.unwatchAudioStreams()
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

    // The compact pill's inside: its 64px box less the 12px inset each side.
    readonly property int compactInner: 40
    // How long the pill's cover and title wait after the panel closes before
    // fading back in (see compactArt).
    readonly property int compactDelay: 130

    function loopIcon() {
        if (!player) return "󰑗"
        if (player.loopState === MprisLoopState.Track) return "󰑘"
        if (player.loopState === MprisLoopState.Playlist) return "󰑖"
        return "󰑗"
    }

    // The pill's box, animated inside a window that is not (see PillStage).
    PillStage {
        id: stage
        collapsed: bar.barHidden
        anchors.top: parent.top
        anchors.left: parent.left
        targetWidth: mediaWidgetItem.panelOpen ? 396
                   : mediaWidgetRow.implicitWidth + 24 + 74 + Theme.pillPaddingH
        targetHeight: mediaWidgetItem.panelOpen ? Math.min(mediaContentColumn.implicitHeight + 60, 640) : 64
        // Sized once for the open panel and never resized: shrinking to the pill's height left one
        // blank frame. Input stays on the box (stageMask).
        minWindowWidth: 396
        minWindowHeight: 640
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
            // The panel's radius is the cover's (heroMask), so their corners
            // match; the pill is round-ended.
            radius: mediaWidgetItem.panelOpen ? Theme.radiusXLarge : mediaWidgetItem.compactInner / 2
            color: Theme.glass
            visible: false
            layer.enabled: true

            Behavior on radius {
                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }
        }

        MultiEffect {
            source: mediaGlass
            anchors.fill: mediaGlass
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.5
            shadowBlur: 0.7
            shadowVerticalOffset: 4
            autoPaddingEnabled: true
        }

        // Compact pill: the cover fills its left end and fades into the glass towards
        // the title; paused, it steps back.
        Item {
            id: compactArt
            anchors.left: parent.left
            anchors.top: parent.top
            // Only the pill's end, so a pale cover never sits under the text.
            width: 70
            // The pill's height, not the box's: filling the box, the cover and title
            // came back stretched while closing.
            height: mediaWidgetItem.compactInner
            visible: opacity > 0
            opacity: mediaWidgetItem.compactShown ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.durShort }
            }

            readonly property bool hasArt: coverImage.status === Image.Ready

            // Rounded on the left only: twice as wide and cut at this item's edge, so
            // the cover fades out straight.
            Item {
                id: coverMask
                anchors.fill: parent
                visible: false

                Rectangle {
                    width: parent.width * 2
                    height: parent.height
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
                        GradientStop { position: 0.225; color: Qt.rgba(1, 1, 1, 0.85) }
                        GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0.2) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
                    }
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

            // OpacityMask, not MultiEffect's mask: MultiEffect thresholds the mask
            // and would cut the gradient hard.
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
                radius: height / 2
                color: Theme.alpha(Theme.shadow, 0.5)
                opacity: bar.isPlaying || !compactArt.hasArt ? 0 : 1
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }

                IconGlyph {
                    anchors.centerIn: parent
                    text: "\u{F03E4}"
                    color: Theme.knob
                    size: Theme.iconTiny
                }
            }
        }

        RowLayout {
            id: mediaWidgetRow
            anchors.left: parent.left
            // Centred on the pill (compactArt), not the box.
            anchors.verticalCenter: compactArt.verticalCenter
            // The title starts where the cover has gone.
            anchors.leftMargin: 74
            spacing: 10
            visible: opacity > 0
            opacity: mediaWidgetItem.compactShown ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.durShort }
            }

            Column {
                spacing: 0

                Item {
                    id: titleMarquee
                    // As wide as the title, up to the cap: a fixed 180 left a short
                    // title beside an empty strip.
                    width: Math.min(titleText.implicitWidth, 180)
                    height: titleText.implicitHeight
                    clip: true

                    Text {
                        id: titleText
                        text: bar.trackTitle
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontText

                        // The marquee leaves x where it stopped, so a short title after a scrolled
                        // long one drew off the edge. Both handlers: a title change under a stopped
                        // animation, and the animation stopping because it fits.
                        onTextChanged: {
                            x = 0
                            marquee.restart()
                        }

                        // Scrolls twice when the track starts, then rests; again on hover.
                        // Scrolling all song long redrew every frame.
                        readonly property bool overflows: titleText.implicitWidth > titleMarquee.width
                        readonly property bool hovered: mediaWidgetItem.barHovered

                        onOverflowsChanged: overflows ? marquee.restart() : marquee.stop()
                        onHoveredChanged: {
                            if (hovered && overflows && !marquee.running) {
                                marquee.loops = Animation.Infinite
                                marquee.restart()
                            } else if (!hovered && marquee.loops === Animation.Infinite) {
                                marquee.stop()
                            }
                        }

                        SequentialAnimation on x {
                            id: marquee
                            running: false
                            onRunningChanged: if (!running) titleText.x = 0
                            loops: 2
                            onStarted: if (!titleText.hovered) marquee.loops = 2

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
                    font.pixelSize: 11
                    font.family: Theme.fontText
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
            // Only the open panel shows how far along the song is.
            running: bar.isPlaying && mediaWidgetItem.panelOpen
            triggeredOnStart: true
            onTriggered: if (mediaWidgetItem.player) mediaWidgetItem.currentPosition = mediaWidgetItem.player.position
        }

        // Expanded panel: the cover across the top, fading down; the spectrum rises from
        // the fade and the text starts below it. Clipped to the box, or the 230px cover
        // hung below the glass while closing.
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(hero.height, parent.height)
            clip: true
            // hero.opacity, not hero.visible: a child's visible is false
            // while its parent is hidden.
            visible: hero.opacity > 0

            Item {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 230
                visible: opacity > 0
                opacity: mediaWidgetItem.panelOpen ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: mediaWidgetItem.panelOpen ? Theme.durMedium : Theme.durShort }
                }

                readonly property bool hasArt: heroImage.status === Image.Ready

                Rectangle {
                    id: heroMask
                    anchors.fill: parent
                    radius: Theme.radiusXLarge
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

                // The spectrum: bars from where the cover fades, in the album colour,
                // mirrored with the low bands centred.
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
                            // Not readonly: a Behavior smooths the step between
                            // the helper's frames.
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
                NumberAnimation { duration: Theme.durMedium }
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
                        font.family: Theme.fontText
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: bar.trackArtist
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: text.length > 0
                        text: mediaWidgetItem.player ? (mediaWidgetItem.player.trackAlbum || "") : ""
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontText
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
                            radius: height / 2
                            color: Theme.track

                            Rectangle {
                                id: seekFill
                                width: mediaWidgetItem.trackLength > 0
                                    ? seekTrack.width * Math.min(1, mediaWidgetItem.currentPosition / mediaWidgetItem.trackLength)
                                    : 0
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
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                            Layout.fillWidth: true
                        }

                        Text {
                            text: mediaWidgetItem.formatTime(mediaWidgetItem.trackLength)
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            font.features: Theme.tabular
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

                    // Play in a filled circle, the primary action. Text colour, not accent:
                    // the accent marks state here.
                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: height / 2
                        color: Theme.textPrimary
                        scale: playState.pressed ? 0.94 : 1.0

                        Behavior on scale {
                            NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad }
                        }

                        IconGlyph {
                            anchors.centerIn: parent
                            text: bar.isPlaying ? "󰏤" : "󰐊"
                            color: Theme.inkOn(Theme.textPrimary)
                            size: Theme.iconLarge
                        }

                        StateLayer {
                            id: playState
                            tint: Theme.inkOn(Theme.textPrimary)
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

                // This player's own volume: the same sink input as the audio panel's
                // slider for the app. Not the master (it turned everything down) nor MPRIS
                // volume (a third number for Spotify).
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
                        // A poll between the write and pactl catching up reports the old volume, so
                        // polling holds off during the drag.
                        onDraggingChanged: Audio.audioStreamsDragging = dragging
                        onMoved: v => mediaWidgetItem.setShownVolume(v / 100)
                    }

                    // Says which volume this is: a player without a stream
                    // falls back to the master.
                    Text {
                        text: Math.round(mediaWidgetItem.shownVolume) + "%"
                            + (mediaWidgetItem.onAppVolume ? "" : " · system")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontText
                        font.features: Theme.tabular
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
                    radius: Theme.radiusMedium
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
                                // Same guessing as the audio panel: entry names and
                                // icon names often differ.
                                return Audio.resolveAppIcon([entry, name, name + "-browser",
                                                                name.split(" ").pop()])
                            }
                        }

                        Text {
                            text: mediaWidgetItem.player ? (mediaWidgetItem.player.identity || "Player") : ""
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: mediaWidgetItem.playerCount > 1
                            text: (bar.activePlayerIndex + 1) + "/" + mediaWidgetItem.playerCount
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }

                        IconGlyph {
                            visible: mediaWidgetItem.canCyclePlayer
                            // Swap, not a chevron: the tap moves to the next
                            // player and opens no list.
                            text: "󰓡"
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
