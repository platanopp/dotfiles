import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.services

// The session lock's face. All the state it draws (PAM's turn, faillock attempts, Caps
// Lock, layout, battery, network, Bluetooth) belongs to LockEngine; nothing is decided
// here. One centred column for clock, field and status; glance chips in the corners, dimmed
// while typing; the bar's glass throughout.
Scope {
    id: root

    // Now playing: the bar's choice (shell.qml's activePlayer): osu, then
    // Spotify, then the rest, playing first.
    readonly property var preferredPlayers: ["osu", "spotify"]

    function playerRank(p) {
        var key = ((p.desktopEntry || "") + " " + (p.dbusName || "") + " " + (p.identity || "")).toLowerCase()
        for (var i = 0; i < root.preferredPlayers.length; i++)
            if (key.indexOf(root.preferredPlayers[i]) !== -1) return i
        return root.preferredPlayers.length
    }

    readonly property var player: {
        var list = Mpris.players.values
        var best = null
        for (var i = 0; i < list.length; i++) {
            var p = list[i]
            if (!p.trackTitle) continue
            if (!best) { best = p; continue }
            var a = root.playerRank(p), b = root.playerRank(best)
            if (a < b || (a === b && p.isPlaying && !best.isPlaying)) best = p
        }
        return best
    }

    WlSessionLock {
        id: session
        locked: LockEngine.locked

        // Handed to the engine so a suspend can wait for the compositor's
        // answer, not just the request.
        onSecureChanged: LockEngine.secured = session.secure

        surface: WlSessionLockSurface {
            id: pane
            color: "black"

            // The engine picks the screen and moves focus there so the keyboard follows the card
            // (see fieldMonitor). If it named no screen, every surface draws the field.
            readonly property bool primary: LockEngine.fieldMonitor === ""
                || !pane.screen || pane.screen.name === LockEngine.fieldMonitor

            Item {
                id: stage
                anchors.fill: parent

                // Motion. Two clocks: `reveal` is the backdrop's (0 the desktop as it was, 1
                // the lock at rest), `ui` the cards', each taking its own slot so they arrive
                // in order and leave in reverse.
                property real reveal: 0
                property real ui: 0
                // Only for a surface with no desktop picture (the boot lock, a screen plugged
                // in while locked): up out of black.
                property real fadeIn: 0

                // This screen's picture from when the lock was asked for, decided once
                // (LockEngine.arriving says when not).
                property string shotSource: ""
                readonly property bool fromShot: shotImage.status === Image.Ready

                // Typing deepens the blur and scrim, so the field is the only thing in focus.
                property real focusDepth: LockEngine.focused ? 1 : 0

                Behavior on focusDepth {
                    NumberAnimation { duration: Theme.durExtraLong; easing.type: Easing.OutCubic }
                }

                // The cards step back while typing: a factor of its own, so the entrance owns
                // the opacity without a Behavior.
                property real dim: LockEngine.focused ? 0.45 : 1

                Behavior on dim {
                    NumberAnimation { duration: Theme.durExtraLong }
                }

                // The wallpaper decodes in the background, so it fades in rather than
                // popping in under the scrim.
                property real wallIn: 0

                NumberAnimation {
                    id: wallFade
                    target: stage
                    property: "wallIn"
                    to: 1
                    duration: Theme.durLong
                }

                // A card's share of `ui`, eased out; a slot is a little over half the
                // clock, so neighbours overlap.
                function slot(a) {
                    var t = Math.max(0, Math.min(1, (stage.ui - a) / 0.55))
                    return 1 - Math.pow(1 - t, 3)
                }

                // In from below (dir 1) or above (dir -1), up and away on the way out;
                // the sign only flips at rest.
                function rise(a, dir) {
                    return (1 - stage.slot(a)) * (LockEngine.leaving ? -16 : 22 * (dir || 1))
                }

                opacity: stage.fromShot ? 1 : stage.fadeIn

                // The start waits for the screen, since pane.screen is still null in
                // Component.onCompleted and the picture is per screen; it falls back to no
                // picture if none is named in time.
                property bool started: false

                function begin() {
                    if (stage.started)
                        return
                    stage.started = true
                    stage.shotSource = LockEngine.arriving && pane.screen
                        ? LockEngine.shotFor(pane.screen.name) : ""
                    if (LockEngine.leaving)
                        departure.start()
                    else
                        arrival.start()
                }

                Component.onCompleted: if (pane.screen) stage.begin()

                Connections {
                    target: pane
                    function onScreenChanged() {
                        if (pane.screen)
                            stage.begin()
                    }
                }

                Timer {
                    running: !stage.started
                    interval: Theme.durMedium
                    onTriggered: stage.begin()
                }

                ParallelAnimation {
                    id: arrival
                    NumberAnimation {
                        target: stage; property: "fadeIn"; from: 0; to: 1
                        duration: Theme.durLong; easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: stage; property: "reveal"; from: 0; to: 1
                        duration: Theme.durExtraLong + Theme.durLong; easing.type: Easing.InOutCubic
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: Theme.durMedium }
                        NumberAnimation {
                            target: stage; property: "ui"; from: 0; to: 1
                            duration: Theme.durExtraLong + Theme.durLong
                        }
                    }
                }

                // On the way out the cards lift off first, then the desktop picture comes
                // forward, so the lock's last frame is the desktop's first. Must stay well
                // under the engine's 2s deadman.
                SequentialAnimation {
                    id: departure
                    ParallelAnimation {
                        NumberAnimation {
                            target: stage; property: "ui"; to: 0
                            duration: Theme.durExtraLong
                        }
                        SequentialAnimation {
                            PauseAnimation { duration: Theme.durShort }
                            NumberAnimation {
                                target: stage; property: "reveal"; to: 0
                                duration: Theme.durExtraLong; easing.type: Easing.InOutCubic
                            }
                        }
                    }
                    ScriptAction { script: LockEngine.release() }
                }

                Connections {
                    target: LockEngine
                    function onLeavingChanged() {
                        if (!LockEngine.leaving)
                            return
                        arrival.stop()
                        departure.start()
                    }
                }

                // Backdrop: a lock surface covers the output, so whatever isn't painted here is
                // black. At rest the blurred wallpaper; while locking and unlocking, the desktop
                // picture steps back into a card or forward.
                Item {
                    id: wall
                    anchors.fill: parent
                    // A little larger than the screen, so the blur's soft rim falls outside it.
                    scale: 1 + 0.05 * (stage.fromShot ? 1 : stage.reveal)
                    opacity: stage.wallIn

                    Image {
                        id: wallImage
                        anchors.fill: parent
                        source: LockEngine.wallpaper.length > 0 ? "file://" + LockEngine.wallpaper : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        visible: false
                        // Qualified: an unqualified `status` is the status line's id further down.
                        onStatusChanged: if (wallImage.status === Image.Ready) wallFade.start()
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: wallImage
                        // Off until the picture is in.
                        blurEnabled: wallImage.status === Image.Ready
                        blurMax: 64
                        // Under a desktop picture it can be fully blurred from the first frame;
                        // alone, it blurs as the lock comes up.
                        blur: (0.6 + 0.4 * stage.focusDepth) * (stage.fromShot ? 1 : stage.reveal)
                    }
                }

                RectangularShadow {
                    anchors.fill: card
                    scale: card.scale
                    visible: card.visible
                    radius: card.radius
                    blur: 48
                    offset.y: 10
                    // Strongest while the card is opaque, gone before it is see-through
                    // enough to show underneath.
                    color: Theme.alpha(Theme.shadow, 0.45 * stage.reveal * Math.pow(card.opacity, 3))
                }

                Item {
                    id: card
                    anchors.fill: parent
                    readonly property real radius: 32 * stage.reveal
                    // Dissolves over the last part of the way in, and only into
                    // a wallpaper that exists.
                    readonly property real dissolve: Math.max(0, Math.min(1, (stage.reveal - 0.35) / 0.65))

                    visible: stage.fromShot && card.opacity > 0.001
                    scale: 1 - 0.1 * stage.reveal
                    opacity: 1 - card.dissolve * stage.wallIn

                    // Rounded corners with OpacityMask: on the lock surface a
                    // ClippingRectangle drew nothing.
                    layer.enabled: card.visible
                    layer.effect: OpacityMask {
                        maskSource: cardMask
                    }

                    Image {
                        id: shotImage
                        anchors.fill: parent
                        source: stage.shotSource
                        // Decoded before the first frame, which must be the desktop: raw
                        // PPM from tmpfs, a few ms.
                        asynchronous: false
                        cache: false
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: shotImage
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blurMax: 48
                        blur: 0.7 * stage.reveal
                    }
                }

                Item {
                    id: cardMask
                    anchors.fill: parent
                    visible: false

                    Rectangle {
                        anchors.fill: parent
                        radius: card.radius
                    }
                }

                // No wallpaper yet, or none set: the scrim is the backdrop and must be opaque.
                Rectangle {
                    anchors.fill: parent
                    color: {
                        var settled = (0.4 + 0.22 * stage.focusDepth) * stage.reveal
                        var ready = stage.fromShot ? 1 : stage.wallIn
                        return Theme.alpha(Theme.background, settled * ready + (1 - ready))
                    }
                }

                // The column
                ColumnLayout {
                    id: column
                    anchors.centerIn: parent
                    width: Math.min(520, pane.width - 96)
                    spacing: 0

                    // Clock on one line, saving vertical room for the field. Every card below takes
                    // its slot of stage.ui through opacity and a Translate, since layout children's
                    // x/y belong to the ColumnLayout.
                    RowLayout {
                        id: clockRow
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        opacity: stage.slot(0)
                        transform: [
                            Translate { y: stage.rise(0) },
                            Scale {
                                origin.x: clockRow.width / 2
                                origin.y: clockRow.height / 2
                                xScale: 0.94 + 0.06 * stage.slot(0)
                                yScale: 0.94 + 0.06 * stage.slot(0)
                            }
                        ]

                        Text {
                            text: LockEngine.hourText + ":" + LockEngine.minuteText
                            color: Theme.textPrimary
                            font.family: Theme.fontDisplay
                            font.features: Theme.tabular
                            font.pixelSize: 104
                            font.weight: Font.Light
                        }

                        Text {
                            visible: LockEngine.meridiem.length > 0
                            text: LockEngine.meridiem
                            color: Theme.textMuted
                            font.family: Theme.fontText
                            font.pixelSize: 18
                            Layout.alignment: Qt.AlignBottom
                            Layout.bottomMargin: 20
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: -4
                        opacity: stage.slot(0.05)
                        transform: Translate { y: stage.rise(0.05) }
                        text: LockEngine.dateText
                        color: Theme.textSecondary
                        font.family: Theme.fontText
                        font.pixelSize: 14
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        opacity: stage.slot(0.09)
                        transform: Translate { y: stage.rise(0.09) }
                        // The greeting stands in for the field on the screens that don't have it.
                        text: LockEngine.greeting + (pane.primary ? "" : ", " + LockEngine.displayName)
                        color: Theme.textMuted
                        font.family: Theme.fontText
                        font.pixelSize: 12
                    }

                    // Now playing: the bar's media pill, grown, with the beat along its
                    // foot. Steps back while typing.
                    Rectangle {
                        id: nowPlaying
                        readonly property var p: root.player
                        readonly property bool playing: nowPlaying.p !== null && nowPlaying.p.isPlaying
                        readonly property bool hasArt: coverImage.status === Image.Ready

                        visible: nowPlaying.p !== null
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 30
                        Layout.preferredWidth: 400
                        Layout.preferredHeight: 94
                        radius: Theme.radiusXLarge
                        color: Theme.glass
                        opacity: stage.dim * stage.slot(0.15)
                        transform: Translate { y: stage.rise(0.15) }

                        RectangularShadow {
                            anchors.fill: parent
                            z: -1
                            radius: parent.radius
                            blur: 18
                            offset.y: 4
                            color: Theme.alpha(Theme.shadow, 0.35)
                        }

                        Item {
                            id: coverArea
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 100

                            // Rounded on the left only: twice as wide and cut at this edge, so
                            // the cover fades out straight.
                            Item {
                                id: coverMask
                                anchors.fill: parent
                                visible: false

                                Rectangle {
                                    width: parent.width * 2
                                    height: parent.height
                                    radius: nowPlaying.radius
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1) }
                                        GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.85) }
                                        GradientStop { position: 0.41; color: Qt.rgba(1, 1, 1, 0.2) }
                                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
                                    }
                                }
                            }

                            Image {
                                id: coverImage
                                anchors.fill: parent
                                source: nowPlaying.p ? (nowPlaying.p.trackArtUrl || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 256
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                visible: nowPlaying.hasArt
                                source: coverImage
                                maskSource: coverMask
                                cached: false

                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    brightness: nowPlaying.playing ? 0 : -0.3
                                    saturation: nowPlaying.playing ? 0 : -0.35

                                    Behavior on brightness { NumberAnimation { duration: Theme.durMedium } }
                                    Behavior on saturation { NumberAnimation { duration: Theme.durMedium } }
                                }
                            }

                            IconGlyph {
                                visible: !nowPlaying.hasArt
                                x: 26
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{F075A}"
                                color: Theme.textSecondary
                                size: Theme.iconLarge
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 104
                            anchors.rightMargin: 14
                            // Clear of the beat along the foot.
                            anchors.bottomMargin: 16
                            spacing: 6

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: nowPlaying.p ? nowPlaying.p.trackTitle : ""
                                    color: Theme.textPrimary
                                    font.family: Theme.fontText
                                    font.pixelSize: 14
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: nowPlaying.p ? (nowPlaying.p.trackArtist || nowPlaying.p.identity || "") : ""
                                    color: Theme.textSecondary
                                    font.family: Theme.fontText
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }

                            IconButton {
                                icon: "\u{F04AE}"
                                size: 32
                                glyphSize: Theme.iconMedium
                                iconColor: Theme.textPrimary
                                interactive: nowPlaying.p !== null && nowPlaying.p.canGoPrevious
                                onTapped: nowPlaying.p.previous()
                            }

                            Rectangle {
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                radius: height / 2
                                color: Theme.accent
                                scale: playTap.pressed ? 0.94 : 1

                                Behavior on scale { NumberAnimation { duration: Theme.durShort } }

                                IconGlyph {
                                    anchors.centerIn: parent
                                    text: nowPlaying.playing ? "\u{F03E4}" : "\u{F040A}"
                                    color: Theme.accentText
                                    size: Theme.iconMedium
                                }

                                StateLayer {
                                    id: playTap
                                    tint: Theme.accentText
                                    interactive: nowPlaying.p !== null && nowPlaying.p.canTogglePlaying
                                    onTapped: nowPlaying.p.togglePlaying()
                                }
                            }

                            IconButton {
                                icon: "\u{F04AD}"
                                size: 32
                                glyphSize: Theme.iconMedium
                                iconColor: Theme.textPrimary
                                interactive: nowPlaying.p !== null && nowPlaying.p.canGoNext
                                onTapped: nowPlaying.p.next()
                            }
                        }

                        // The beat: the media panel's spectrum, small, in the album colour.
                        // Spectrum runs only while subscribed.
                        readonly property bool wantSpectrum: LockEngine.locked && nowPlaying.visible && nowPlaying.playing
                        onWantSpectrumChanged: nowPlaying.wantSpectrum ? Spectrum.subscribe() : Spectrum.unsubscribe()
                        Component.onDestruction: if (nowPlaying.wantSpectrum) Spectrum.unsubscribe()

                        Row {
                            id: beat
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 104
                            anchors.rightMargin: 18
                            anchors.bottomMargin: 9
                            height: 14
                            spacing: 2
                            opacity: nowPlaying.playing ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }

                            readonly property int count: Math.floor((width + spacing) / (3 + spacing))

                            // Low bands in the middle, mirrored out to both ends.
                            function level(i) {
                                var b = Spectrum.bands
                                var half = beat.count / 2
                                var band = Math.floor(Math.abs(i - half + 0.5) / half * b.length)
                                return (band >= 0 && band < b.length) ? b[band] : 0
                            }

                            Repeater {
                                model: beat.count

                                Rectangle {
                                    required property int index
                                    readonly property real level: beat.level(index)
                                    // Not readonly: a Behavior smooths the step between
                                    // the helper's frames.
                                    property real len: 2 + level * 12

                                    anchors.bottom: parent.bottom
                                    width: 3
                                    height: len
                                    radius: 1.5
                                    color: Theme.alpha(AlbumColors.accent, 0.4 + level * 0.6)

                                    Behavior on len {
                                        NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                        }
                    }

                    // Password
                    Rectangle {
                        id: fieldPill
                        visible: pane.primary
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: nowPlaying.visible ? 22 : 36
                        Layout.preferredWidth: 340
                        Layout.preferredHeight: 52
                        radius: height / 2
                        color: Theme.glass
                        opacity: stage.slot(0.21)
                        border.width: 1
                        border.color: LockEngine.granted ? Theme.alpha(Theme.success, 0.6)
                                    : LockEngine.lockedOut ? Theme.alpha(Theme.error, 0.7)
                                    : field.activeFocus ? Theme.alpha(Theme.foreground, 0.28)
                                    : "transparent"

                        RectangularShadow {
                            anchors.fill: parent
                            z: -1
                            radius: parent.radius
                            blur: 18
                            offset.y: 4
                            color: Theme.alpha(Theme.shadow, 0.35)
                        }

                        Behavior on border.color { ColorAnimation { duration: Theme.durMedium } }

                        // A wrong password shakes the pill once. Through a Translate,
                        // since the layout owns its x.
                        transform: Translate {
                            id: nudge
                            y: stage.rise(0.21)
                        }

                        SequentialAnimation {
                            id: shake
                            NumberAnimation { target: nudge; property: "x"; to: -9; duration: 55 }
                            NumberAnimation { target: nudge; property: "x"; to: 9; duration: 55 }
                            NumberAnimation { target: nudge; property: "x"; to: -5; duration: 55 }
                            NumberAnimation { target: nudge; property: "x"; to: 0; duration: 55 }
                        }

                        // The right password swells the pill once and turns the button to a
                        // tick, inside the engine's grace.
                        SequentialAnimation {
                            id: welcome
                            NumberAnimation {
                                target: fieldPill; property: "scale"; to: 1.04
                                duration: Theme.durMedium; easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: fieldPill; property: "scale"; to: 1
                                duration: Theme.durMedium; easing.type: Easing.InOutCubic
                            }
                        }

                        Connections {
                            target: LockEngine
                            function onFailed() {
                                field.text = ""
                                shake.restart()
                            }
                            function onGrantedChanged() {
                                if (LockEngine.granted)
                                    welcome.restart()
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 8
                            spacing: 10

                            IconGlyph {
                                text: LockEngine.granted ? "\u{F033F}"
                                    : LockEngine.lockedOut ? "\u{F0026}" : "\u{F033E}"
                                color: LockEngine.granted ? Theme.success
                                     : LockEngine.lockedOut ? Theme.error : Theme.textMuted
                                size: Theme.iconMedium

                                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                            }

                            TextInput {
                                id: field
                                Layout.fillWidth: true
                                enabled: LockEngine.acceptsInput
                                // PAM can ask a question whose answer is not secret, and says so.
                                echoMode: LockEngine.secret ? TextInput.Password : TextInput.Normal
                                passwordCharacter: "•"
                                color: Theme.textPrimary
                                font.family: Theme.fontText
                                font.pixelSize: 15
                                verticalAlignment: TextInput.AlignVCenter
                                focus: true
                                clip: true

                                // The engine drives the blur and step-back off this,
                                // from the first keystroke.
                                onTextChanged: if (text.length > 0) LockEngine.engage()
                                onAccepted: { LockEngine.submit(text); text = "" }

                                // Refocused whenever the field is usable again: PAM disables it per
                                // turn, and a disabled item drops focus.
                                Connections {
                                    target: LockEngine
                                    function onAcceptsInputChanged() {
                                        if (LockEngine.acceptsInput && LockEngine.locked)
                                            field.forceActiveFocus()
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: field.text.length === 0
                                    text: LockEngine.lockedOut ? "Locked"
                                        : LockEngine.prompt.length > 0 ? LockEngine.prompt
                                        : "Password"
                                    color: Theme.textMuted
                                    font: field.font
                                }
                            }

                            // Submit, carrying the spinner too, so the status line stays for words.
                            Rectangle {
                                id: submitBtn
                                readonly property bool ready: field.text.length > 0 && LockEngine.acceptsInput
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                radius: height / 2
                                color: LockEngine.granted ? Theme.success
                                     : submitBtn.ready ? Theme.accent : "transparent"

                                Behavior on color { ColorAnimation { duration: Theme.durMedium } }

                                IconGlyph {
                                    anchors.centerIn: parent
                                    visible: !LockEngine.busy
                                    text: LockEngine.granted ? "\u{F012C}" : "\u{F0054}"
                                    color: LockEngine.granted ? Theme.background
                                         : submitBtn.ready ? Theme.accentText : Theme.textMuted
                                    size: Theme.iconMedium
                                }

                                // A spinning ring with a gap: no animated image, and it
                                // takes the theme colour.
                                Item {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    visible: LockEngine.busy

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: "transparent"
                                        border.width: 2
                                        border.color: Theme.alpha(Theme.accent, 0.25)
                                    }

                                    Rectangle {
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: Theme.accent
                                        x: parent.width / 2 - 2.5
                                        y: -1
                                        transformOrigin: Item.Center
                                    }

                                    RotationAnimation on rotation {
                                        running: LockEngine.busy
                                        loops: Animation.Infinite
                                        from: 0
                                        to: 360
                                        duration: 850
                                    }
                                }

                                StateLayer {
                                    interactive: submitBtn.ready
                                    onTapped: { LockEngine.submit(field.text); field.text = "" }
                                }
                            }
                        }
                    }

                    // The line under the field: PAM's wording, tries left and the faillock
                    // countdown, coloured by severity. Its height is held so the column
                    // doesn't jump when a message appears.
                    Item {
                        visible: pane.primary
                        opacity: stage.slot(0.27)
                        transform: Translate { y: stage.rise(0.27) }
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 14
                        Layout.preferredWidth: 400
                        Layout.preferredHeight: Math.max(18, status.implicitHeight)

                        Text {
                            id: status
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: LockEngine.statusText
                            opacity: text.length > 0 ? 1 : 0
                            color: LockEngine.statusKind === "error" ? Theme.error
                                 : LockEngine.statusKind === "good" ? Theme.success
                                 : Theme.textSecondary
                            font.family: Theme.fontText
                            font.pixelSize: 12

                            Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }
                        }
                    }

                    // Caps Lock and the layout, shown only when unusual: a wrong layout
                    // quietly fails a correct password.
                    RowLayout {
                        visible: pane.primary && (LockEngine.capsLock || LockEngine.layoutShort.length > 0)
                        opacity: stage.slot(0.3)
                        transform: Translate { y: stage.rise(0.3) }
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        spacing: 8

                        Rectangle {
                            visible: LockEngine.capsLock
                            Layout.preferredWidth: capsLabel.implicitWidth + 22
                            Layout.preferredHeight: 24
                            radius: height / 2
                            color: Theme.alpha(Theme.warning, 0.16)
                            border.width: 1
                            border.color: Theme.alpha(Theme.warning, 0.4)

                            Text {
                                id: capsLabel
                                anchors.centerIn: parent
                                text: "Caps Lock"
                                color: Theme.warning
                                font.family: Theme.fontText
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }

                        Rectangle {
                            visible: LockEngine.layoutShort.length > 0
                            Layout.preferredWidth: layoutRow.implicitWidth + 20
                            Layout.preferredHeight: 24
                            radius: height / 2
                            color: LockEngine.card
                            border.width: 1
                            border.color: LockEngine.hairline

                            RowLayout {
                                id: layoutRow
                                anchors.centerIn: parent
                                spacing: 6

                                IconGlyph {
                                    text: "\u{F030C}"
                                    color: Theme.textMuted
                                    size: Theme.iconTiny
                                }

                                Text {
                                    text: LockEngine.layoutShort
                                    color: Theme.textSecondary
                                    font.family: Theme.fontText
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }

                // Who is being asked, top left: outside the column, which is the sign-in itself.
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 28
                    visible: pane.primary && LockEngine.displayName.length > 0
                    opacity: stage.dim * stage.slot(0.33)
                    transform: Translate { y: stage.rise(0.33, -1) }
                    width: whoRow.implicitWidth + 12 + 18
                    height: 44
                    radius: height / 2
                    color: Theme.glass

                    RectangularShadow {
                        anchors.fill: parent
                        z: -1
                        radius: parent.radius
                        blur: 16
                        offset.y: 4
                        color: Theme.alpha(Theme.shadow, 0.3)
                    }

                    RowLayout {
                        id: whoRow
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        // The user's picture (Settings -> Profile) or initial. OpacityMask: a
                        // ClippingRectangle drew nothing here.
                        Item {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32

                            Rectangle {
                                id: whoMask
                                anchors.fill: parent
                                radius: width / 2
                                visible: false
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Theme.surfaceContainerHigh
                                visible: whoImage.status !== Image.Ready

                                Text {
                                    anchors.centerIn: parent
                                    text: LockEngine.initials
                                    color: Theme.textPrimary
                                    font.family: Theme.fontText
                                    font.pixelSize: 13
                                    font.bold: true
                                }
                            }

                            Image {
                                id: whoImage
                                anchors.fill: parent
                                source: Profile.avatarSource
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: 96
                                visible: false
                            }

                            OpacityMask {
                                anchors.fill: parent
                                visible: whoImage.status === Image.Ready
                                source: whoImage
                                maskSource: whoMask
                            }
                        }

                        Text {
                            text: LockEngine.displayName
                            color: Theme.textPrimary
                            font.family: Theme.fontText
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }

                // Glance chips, top right: not part of signing in, so out of the
                // column and dimmed while typing.
                Rectangle {
                    id: glance
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 28
                    visible: glanceRow.visibleChildren.length > 0
                    width: glanceRow.implicitWidth + 36
                    height: 44
                    radius: height / 2
                    color: Theme.glass
                    opacity: stage.dim * stage.slot(0.37)
                    transform: Translate { y: stage.rise(0.37, -1) }

                    RectangularShadow {
                        anchors.fill: parent
                        z: -1
                        radius: parent.radius
                        blur: 16
                        offset.y: 4
                        color: Theme.alpha(Theme.shadow, 0.3)
                    }

                    // One pill, like the bar's status pill.
                    RowLayout {
                        id: glanceRow
                        anchors.centerIn: parent
                        spacing: 16

                        Repeater {
                            model: [
                                {
                                    "show": LockEngine.netLabel.length > 0,
                                    "glyph": LockEngine.netGlyph === "ethernet" ? "\u{F0200}"
                                           : LockEngine.netGlyph === "wifi" ? "\u{F0928}"
                                           : "\u{F092F}",
                                    "label": LockEngine.netLabel,
                                    "alert": false
                                },
                                {
                                    "show": LockEngine.btOn && LockEngine.btLabel.length > 0,
                                    "glyph": "\u{F00AF}",
                                    "label": LockEngine.btLabel,
                                    "alert": false
                                },
                                {
                                    "show": LockEngine.hasBattery,
                                    "glyph": LockEngine.charging ? "\u{F0084}" : "\u{F0079}",
                                    "label": LockEngine.batteryPercent + "%",
                                    "alert": LockEngine.batteryLow
                                }
                            ]

                            RowLayout {
                                id: chip
                                required property var modelData
                                visible: chip.modelData.show
                                spacing: 7

                                IconGlyph {
                                    text: chip.modelData.glyph
                                    color: chip.modelData.alert ? Theme.error : Theme.textPrimary
                                    size: Theme.iconMedium
                                }

                                Text {
                                    text: chip.modelData.label
                                    color: chip.modelData.alert ? Theme.error : Theme.textSecondary
                                    font.family: Theme.fontText
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 150
                                }
                            }
                        }
                    }
                }

                // Power, bottom centre. The risky ones arm on the first tap and run on the second
                // (arming one disarms the last); suspend runs at once.
                RowLayout {
                    id: powerRow
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 36
                    spacing: 8
                    visible: pane.primary
                    opacity: stage.dim * stage.slot(0.45)
                    transform: Translate { y: stage.rise(0.45) }

                    property string armed: ""

                    Timer {
                        id: disarm
                        interval: 4000
                        onTriggered: powerRow.armed = ""
                    }

                    Repeater {
                        model: LockEngine.powerActions

                        Rectangle {
                            id: powerBtn
                            required property var modelData

                            readonly property bool isArmed: powerRow.armed === powerBtn.modelData.id

                            Layout.preferredWidth: powerBtn.isArmed ? confirmLabel.implicitWidth + 32 : 44
                            Layout.preferredHeight: 44
                            radius: height / 2
                            color: powerBtn.isArmed ? Theme.alpha(Theme.error, 0.9) : Theme.glass

                            RectangularShadow {
                                anchors.fill: parent
                                z: -1
                                radius: parent.radius
                                blur: 14
                                offset.y: 3
                                color: Theme.alpha(Theme.shadow, 0.3)
                            }

                            Behavior on Layout.preferredWidth {
                                Elastic { small: true }
                            }

                            Behavior on color { ColorAnimation { duration: Theme.durMedium } }

                            IconGlyph {
                                anchors.centerIn: parent
                                visible: !powerBtn.isArmed
                                text: {
                                    var id = powerBtn.modelData.id
                                    if (id === "suspend")   return "\u{F04B2}"
                                    if (id === "hibernate") return "\u{F0717}"
                                    if (id === "logout")    return "\u{F0343}"
                                    if (id === "reboot")    return "\u{F0709}"
                                    return "\u{F0425}"
                                }
                                color: Theme.textPrimary
                                size: Theme.iconMedium
                            }

                            Text {
                                id: confirmLabel
                                anchors.centerIn: parent
                                visible: powerBtn.isArmed
                                text: powerBtn.modelData.label + "?"
                                color: Theme.foreground
                                font.family: Theme.fontText
                                font.pixelSize: 12
                                font.bold: true
                            }

                            StateLayer {
                                onTapped: {
                                    if (!powerBtn.modelData.confirm || powerBtn.isArmed) {
                                        powerRow.armed = ""
                                        disarm.stop()
                                        LockEngine.runPower(powerBtn.modelData.id)
                                    } else {
                                        powerRow.armed = powerBtn.modelData.id
                                        disarm.restart()
                                    }
                                }
                            }
                        }
                    }
                }

                // Clicking anywhere focuses the field, as typing does; last child, so it
                // only takes unclaimed presses.
                TapHandler {
                    onTapped: {
                        LockEngine.engage()
                        if (pane.primary && LockEngine.acceptsInput)
                            field.forceActiveFocus()
                    }
                }
            }
        }
    }
}
