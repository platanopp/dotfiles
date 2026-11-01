import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import qs.components
import qs.config
import qs.services

// Full-screen wallpaper picker, opened from the control panel or the "quickshell:wallpapers" bind.
// Not in the 372px control panel: the depth effect needs the centre panel at full size.
PanelWindow {
    id: overlay

    property var bar: null
    screen: bar.screen

    // Pinned to the screen it was opened on, so it does not follow the
    // pointer to the other monitor.
    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (Panels.wallpapersScreen === "") return bar.monitor.focused
        return bar.monitor.name === Panels.wallpapersScreen
    }

    readonly property bool open: Panels.wallpapersOpen && overlay.onOpeningScreen

    // Unmapped while closed: a mapped full-screen layer is composited every frame, even when empty.
    // A `shown` flag, not `open || unmapDelay.running`, which blinked on close (see AppLauncher).
    // Connections instead of `onOpenChanged`: this object already declares one.
    property bool shown: false
    visible: overlay.shown

    Timer {
        id: unmapDelay
        // The inner fades run on durMedium; the margin covers the frame
        // the Behavior needs to start.
        interval: Theme.durMedium + 80

        // Recentre only once the surface is gone: mid-fade, setting the
        // index left the row a slot off.
        onTriggered: {
            overlay.shown = false
            overlay.section = overlay.sectionInUse()
            overlay.centerOnCurrent()
        }
    }

    Connections {
        target: overlay
        function onOpenChanged() {
            if (overlay.open) {
                unmapDelay.stop()
                // Always opens on the wallpaper in use: set before the row is built so the build
                // lands on it, and again after, for a picker reopened mid-fade.
                overlay.section = overlay.sectionInUse()
                overlay.pendingFocus = overlay.current
                overlay.shown = true
                overlay.restoreFocus()
            } else {
                unmapDelay.restart()
            }
        }
    }

    color: "transparent"

    WlrLayershell.namespace: "quickshell:wallpapers"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Held until the picker is gone: changing it on a visible surface drops
    // two frames (see AppLauncher).
    WlrLayershell.keyboardFocus: overlay.shown ? WlrKeyboardFocus.Exclusive
                                               : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: overlay.open ? null : blankMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Sections. Images and videos share the folder and the carousel and differ only in
    // how they apply (image: cropper -> hyprpaper, video: mpvpaper), so everything
    // below reads `files` and `current`.
    property string section: "images"

    readonly property bool videos: overlay.section === "videos"

    readonly property var files: overlay.videos ? Wallpaper.videoWallpaperFiles
                                                : Wallpaper.wallpaperFiles

    // With a video playing no image is in use: the one underneath only shows when the video stops.
    readonly property string current: overlay.videos
        ? Wallpaper.activeVideoWallpaper
        : (Wallpaper.activeVideoWallpaper === "" ? Wallpaper.selectedWallpaper : "")

    function thumbFor(path) {
        return overlay.videos ? Wallpaper.videoWallpaperThumb(path)
                              : Wallpaper.wallpaperThumb(path)
    }

    // Opens on the section holding what is in use.
    function sectionInUse() {
        return Wallpaper.activeVideoWallpaper !== "" ? "videos" : "images"
    }

    function showSection(name) {
        if (overlay.section === name) return
        overlay.framing = false
        overlay.section = name
        // After the model swap lands: the view resets its index on a model change.
        Qt.callLater(overlay.centerOnCurrent)
    }

    // Geometry. Tall, narrow panels rather than 16:9 cards, so the parallax has crop to slide
    // through. Sized off the screen height, which a portrait panel runs out of first.
    readonly property int panelHeight: Math.max(240, Math.min(520, Math.round(overlay.height * 0.46)))
    readonly property int panelWidth: Math.round(panelHeight * 0.46)

    // A hair of a gap so the row reads as a strip; the full-size centre
    // panel overlaps it (see z below).
    readonly property int slotWidth: panelWidth + 8

    // How much a panel shrinks by the end of the row: the far ones land at 0.74.
    readonly property real scaleFalloff: 0.26

    // How far the photo slides inside its panel across the row, about a quarter
    // panel per step. Capped by the crop: a 16:9 wallpaper fills 884px at this
    // height, and this keeps the box at 619.
    readonly property int parallaxRange: Math.round(panelWidth * 0.85)

    // Panels kept decoded at once; past this they are built as they arrive, so a
    // big folder cannot grow memory.
    readonly property int maxWarmPanels: 20

    // Odd, so exactly one item sits in the middle.
    readonly property int slotCount: {
        var fits = Math.floor(overlay.width / Math.max(1, slotWidth))
        var capped = Math.min(fits, 7, overlay.files.length)
        if (capped <= 1) return 1
        return capped % 2 === 0 ? capped - 1 : capped
    }

    // The panel at rest opens out: once the row stops, the middle panel widens to the
    // screen's shape and its neighbours step aside; it folds back as soon as the row
    // moves. Capped for very wide screens.
    readonly property int expandedWidth: Math.min(
        Math.round(overlay.width * 0.8),
        Math.round(overlay.panelHeight * overlay.width / Math.max(1, overlay.height)))
    readonly property int expandExtra: Math.max(0, overlay.expandedWidth - overlay.panelWidth)

    // The open panel by index, not isCurrent: the arrow keys change currentIndex before the row
    // moves, so the index is handed on only once the old panel has folded back.
    property int expandedIndex: -1
    property bool wantExpanded: false

    // 0 folded, 1 open: animated here once rather than per panel.
    property real expansion: overlay.wantExpanded && overlay.open && !overlay.framing ? 1 : 0

    Behavior on expansion {
        Elastic {}
    }

    // Anything that moves the row folds the panel and restarts the wait, which outlasts the fold so
    // handing the index on cannot make anything jump.
    function unsettle() {
        overlay.wantExpanded = false
        settleTimer.restart()
    }

    Timer {
        id: settleTimer
        interval: Theme.durLong + 60
        onTriggered: {
            if (!overlay.open || overlay.framing) return
            overlay.expandedIndex = carousel.currentIndex
            overlay.wantExpanded = true
        }
    }

    // Opens out a beat after the picker has faded in.
    Connections {
        target: overlay
        function onOpenChanged() {
            if (overlay.open) overlay.unsettle()
            else overlay.wantExpanded = false
        }
    }

    function close() {
        Panels.wallpapersOpen = false
    }

    // A click on a panel away from the middle: bring it there.
    function bringToCentre(index) {
        carousel.currentIndex = index
    }

    // Framing: a second mode, not a second window; it acts on the wallpaper in the middle.
    property bool framing: false
    property string framingPath: ""

    // Where the crop sits, 0 to 1 per axis. A draft, so it lives here
    // until applied, not in Wallpaper.
    property real focusX: 0.5
    property real focusY: 0.5

    function startFraming() {
        // Videos are covered by mpv's own panscan; there is nothing to frame.
        if (overlay.videos) return
        var path = overlay.files[carousel.currentIndex]
        if (!path) return
        overlay.framingPath = path
        overlay.framing = true
        // Seeds focusX/focusY once the answer lands; until then the editor shows it is measuring.
        Wallpaper.probeWallpaperCrop(path)
    }

    function cancelFraming() {
        overlay.framing = false
    }

    function applyFraming() {
        if (overlay.framingPath.length === 0) return
        Wallpaper.setWallpaperFraming(overlay.framingPath, overlay.focusX, overlay.focusY)
        overlay.framing = false
        overlay.close()
    }

    // Centre the crop on the pointer along whichever axis has slack; an
    // axis with none keeps its value.
    function aimFraming(px, py, slackX, slackY, cropW, cropH) {
        if (slackX > 1)
            overlay.focusX = Math.max(0, Math.min(1, (px - cropW / 2) / slackX))
        if (slackY > 1)
            overlay.focusY = Math.max(0, Math.min(1, (py - cropH / 2) / slackY))
    }

    function nudgeFraming(dx, dy) {
        overlay.focusX = Math.max(0, Math.min(1, overlay.focusX + dx))
        overlay.focusY = Math.max(0, Math.min(1, overlay.focusY + dy))
    }

    Connections {
        target: Wallpaper
        function onWallpaperCropInfoChanged() {
            var info = Wallpaper.wallpaperCropInfo
            if (!info) return
            overlay.focusX = info.focusX
            overlay.focusY = info.focusY
        }
    }

    function apply() {
        if (carousel.currentIndex < 0) return
        var path = overlay.files[carousel.currentIndex]
        if (!path) return
        if (overlay.videos) Wallpaper.setVideoWallpaper(path)
        else Wallpaper.setWallpaper(path)
        overlay.close()
    }

    // Centre the carousel on the wallpaper in use, on open only (not bound) so browsing isn't
    // yanked back. Kept as a path, not an index, because a model rebuild resets the index.
    property string pendingFocus: ""

    function centerOnCurrent() {
        overlay.pendingFocus = overlay.current
        overlay.restoreFocus()
    }

    function restoreFocus() {
        if (overlay.pendingFocus === "") return
        // Not while the row is empty (it is built only while up): kept until the
        // row exists (onCountChanged).
        if (carousel.count === 0) return
        var i = overlay.files.indexOf(overlay.pendingFocus)
        if (i < 0) return
        // Jump, not travel: animating across a row just built left the middle
        // and the index a slot apart.
        carousel.highlightMoveDuration = 0
        carousel.currentIndex = i
        Qt.callLater(function() { carousel.highlightMoveDuration = Theme.durMedium })

        // Spent once honoured, so a later refresh does not drag the user back.
        overlay.pendingFocus = ""
    }

    // Parked while shut, never on the way open: StrictlyEnforceRange animates to the index, and
    // doing it mid-layout left the row a slot behind the caption.
    onOpenChanged: {
        if (overlay.open) return
        overlay.framing = false
        // Centring is left to unmapDelay, once the surface is actually down.
    }
    Component.onCompleted: {
        overlay.section = overlay.sectionInUse()
        overlay.centerOnCurrent()
    }

    // Both land after startup, and either can be what makes the wallpaper in use findable.
    Connections {
        target: Wallpaper
        function onWallpaperFilesChanged() {
            if (!overlay.open) overlay.centerOnCurrent()
        }
        function onSelectedWallpaperChanged() {
            if (!overlay.open) overlay.centerOnCurrent()
        }
        function onVideoWallpaperFilesChanged() {
            if (!overlay.open) overlay.centerOnCurrent()
        }
        // The remembered video arrives after startup and decides whether to
        // open on the video section.
        function onActiveVideoWallpaperChanged() {
            if (overlay.open) return
            overlay.section = overlay.sectionInUse()
            overlay.centerOnCurrent()
        }
    }

    // Backdrop: darker than the other overlays, since judging images needs a neutral ground.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.background, 0.88)
        opacity: overlay.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        // Steps back like Escape. Ignores clicks in the carousel's band: the panels let
        // presses through for dragging, so a click on a side panel also closed the picker.
        // By height, not the band's rect, because an opened-out panel pushes its
        // neighbours past the carousel's edges.
        TapHandler {
            onTapped: eventPoint => {
                if (overlay.framing) {
                    overlay.cancelFraming()
                    return
                }
                var p = carouselArea.mapFromItem(null, eventPoint.scenePosition.x,
                                                 eventPoint.scenePosition.y)
                if (carouselArea.visible && p.y >= 0 && p.y < carouselArea.height) return
                overlay.close()
            }
        }
    }

    // Focus lives on an item so the keys have somewhere to land; released on close.
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: overlay.shown

        // Escape steps back one mode: from the framing editor to the row,
        // and only from the row out.
        Keys.onEscapePressed: overlay.framing ? overlay.cancelFraming() : overlay.close()
        Keys.onReturnPressed: overlay.framing ? overlay.applyFraming() : overlay.apply()
        Keys.onEnterPressed: overlay.framing ? overlay.applyFraming() : overlay.apply()

        // In the row the arrows change wallpaper; in the editor they nudge the crop.
        Keys.onLeftPressed: overlay.framing ? overlay.nudgeFraming(-0.02, 0)
                                            : carousel.decrementCurrentIndex()
        Keys.onRightPressed: overlay.framing ? overlay.nudgeFraming(0.02, 0)
                                             : carousel.incrementCurrentIndex()
        Keys.onTabPressed: if (!overlay.framing)
            overlay.showSection(overlay.videos ? "images" : "videos")
        Keys.onUpPressed: if (overlay.framing) overlay.nudgeFraming(0, -0.02)
        Keys.onDownPressed: if (overlay.framing) overlay.nudgeFraming(0, 0.02)
        // F frames the image in the middle, as the Frame button does.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F && !overlay.framing && !overlay.videos) {
                overlay.startFraming()
                event.accepted = true
            }
        }
    }

    // Content

    Item {
        anchors.fill: parent

        // The wheel turns the carousel anywhere on screen, one step per 120 units: high-resolution
        // wheels and touchpads split a notch into several small events.
        WheelHandler {
            id: wheel
            target: null
            enabled: overlay.open && !overlay.framing

            property real pending: 0

            onWheel: event => {
                // Up or left goes back, down or right forward; vertical wins when both are present.
                var d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
                if (d === 0) return
                // A change of direction starts afresh.
                if ((d > 0) !== (wheel.pending > 0)) wheel.pending = 0
                wheel.pending += d
                while (wheel.pending >= 120) {
                    carousel.decrementCurrentIndex()
                    wheel.pending -= 120
                }
                while (wheel.pending <= -120) {
                    carousel.incrementCurrentIndex()
                    wheel.pending += 120
                }
            }
        }

        opacity: overlay.open ? 1 : 0
        scale: overlay.open ? 1 : 0.94
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            Elastic { small: true }
        }

        // Into the framing editor and back: both views fade and grow towards the viewer, so one
        // pair of bindings animates both directions.
        Column {
            id: carouselSide
            anchors.centerIn: parent
            spacing: 28

            opacity: overlay.framing ? 0 : 1
            scale: overlay.framing ? 1.06 : 1
            visible: opacity > 0
            // Input follows the mode, not the fade, so a click mid-transition
            // goes to the view being opened.
            enabled: !overlay.framing

            Behavior on opacity {
                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }

            Behavior on scale {
                Elastic { small: true }
            }

            // The section switch, in the title's place: one pill, the selected segment filled,
            // like the control panel's choices.
            Rectangle {
                id: sectionSwitch
                anchors.horizontalCenter: parent.horizontalCenter
                width: sectionRow.implicitWidth + 8
                height: 40
                radius: height / 2
                color: Theme.surface
                border.width: 1
                border.color: Theme.outline

                RectangularShadow {
                    anchors.fill: parent
                    z: -1
                    radius: parent.radius
                    blur: 20
                    offset.y: 5
                    color: Theme.alpha(Theme.shadow, 0.4)
                }

                // The fill slides between the two, so the switch shows which way it went.
                Rectangle {
                    y: 4
                    height: parent.height - 8
                    radius: height / 2
                    color: Theme.accent
                    x: 4 + (overlay.videos ? imagesTab.width : 0)
                    width: overlay.videos ? videosTab.width : imagesTab.width

                    Behavior on x {
                        Elastic { small: true }
                    }
                    Behavior on width {
                        Elastic { small: true }
                    }
                }

                Row {
                    id: sectionRow
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: [
                            { name: "images", label: "Images", glyph: "\u{F02E9}",
                              count: Wallpaper.wallpaperFiles.length },
                            { name: "videos", label: "Videos", glyph: "\u{F0567}",
                              count: Wallpaper.videoWallpaperFiles.length }
                        ]

                        Item {
                            id: tab
                            required property var modelData
                            required property int index
                            readonly property bool selected: overlay.section === tab.modelData.name

                            width: tabRow.implicitWidth + 32
                            height: sectionSwitch.height - 8

                            Component.onCompleted: {
                                if (tab.index === 0) imagesTab.width = Qt.binding(() => tab.width)
                                else videosTab.width = Qt.binding(() => tab.width)
                            }

                            Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 8

                                IconGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tab.modelData.glyph
                                    size: Theme.iconSmall
                                    color: tab.selected ? Theme.accentText : Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tab.modelData.label
                                    font.pixelSize: 13
                                    font.bold: tab.selected
                                    font.family: Theme.fontText
                                    color: tab.selected ? Theme.accentText : Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tab.modelData.count
                                    font.pixelSize: 11
                                    font.family: Theme.fontText
                                    font.features: Theme.tabular
                                    color: tab.selected ? Theme.alpha(Theme.accentText, 0.6) : Theme.textMuted
                                    Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                }
                            }

                            StateLayer {
                                radius: height / 2
                                interactive: !tab.selected
                                onTapped: overlay.showSection(tab.modelData.name)
                            }
                        }
                    }
                }

                // Segment widths for the sliding fill, set by the delegates: a Repeater's
                // items aren't reachable by id.
                QtObject { id: imagesTab; property real width: 0 }
                QtObject { id: videosTab; property real width: 0 }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: overlay.files.length === 0
                text: overlay.videos
                    ? "No videos yet. Put .mp4, .webm, .mkv or .mov files in ~/Pictures/Wallpapers"
                    : "No images yet. Put pictures in ~/Pictures/Wallpapers to pick one here"
                color: Theme.textMuted
                font.pixelSize: 13
                font.family: Theme.fontText
            }

            // The carousel. Depth comes from z along the path (0 -> 1 -> 0, the middle on
            // top), size falling off with distance, and a shadow under the middle panel.
            // The parallax is in the delegate.
            Item {
                id: carouselArea
                anchors.horizontalCenter: parent.horizontalCenter
                visible: overlay.files.length > 0

                width: Math.min(overlay.width, overlay.slotCount * overlay.slotWidth)
                height: overlay.panelHeight + 48

                PathView {
                    id: carousel
                    anchors.fill: parent

                    // Only while the picker is up: held all session, the warm panels
                    // cost about 40 MB per monitor.
                    model: overlay.visible ? overlay.files : []
                    pathItemCount: overlay.slotCount
                    // Room for the whole folder: a PathView rebuilds delegates that leave the row,
                    // and a fresh Image flashes grey while it decodes. ~2.8 MB per panel, so ~55 MB
                    // for a large folder, only while open.
                    cacheItemCount: Math.min(overlay.files.length,
                                             overlay.maxWarmPanels)

                    snapMode: PathView.SnapToItem
                    preferredHighlightBegin: 0.5
                    preferredHighlightEnd: 0.5
                    highlightRangeMode: PathView.StrictlyEnforceRange
                    // Short enough that a held arrow key does not queue up travel.
                    highlightMoveDuration: Theme.durMedium

                    // Fires when the model is rebuilt, which resets the index.
                    onCountChanged: overlay.restoreFocus()

                    // Both: a click changes the index then animates, a drag moves the offset first.
                    // Offset changes every frame, so the settle wait starts only once it stops.
                    onCurrentIndexChanged: overlay.unsettle()
                    onOffsetChanged: overlay.unsettle()

                    // Grab anywhere on the row: PathView takes a drag only within
                    // dragMargin of its one-line path.
                    dragMargin: carousel.height / 2

                    // Two attributes ride the path: "depth" (z-order, middle in front) and "shift"
                    // (-1 left to 1 right, drives the photo).
                    path: Path {
                        startX: 0
                        startY: carousel.height / 2

                        PathAttribute { name: "depth"; value: 0 }
                        PathAttribute { name: "shift"; value: -1 }
                        PathLine { x: carousel.width / 2; relativeY: 0 }
                        PathAttribute { name: "depth"; value: 1 }
                        PathAttribute { name: "shift"; value: 0 }
                        PathLine { x: carousel.width; relativeY: 0 }
                        PathAttribute { name: "depth"; value: 0 }
                        PathAttribute { name: "shift"; value: 1 }
                    }

                    delegate: Item {
                        id: card

                        required property string modelData
                        required property int index

                        readonly property bool isCurrent: PathView.isCurrentItem
                        readonly property bool isActive: card.modelData === overlay.current

                        // Position along the row, -1 to 1; undefined for an item off the path.
                        readonly property real shift: PathView.shift ?? 0

                        // Open, this panel widens by the full extra and the others step half of it
                        // aside, keeping the row symmetric.
                        readonly property bool isExpanded: card.index === overlay.expandedIndex

                        width: overlay.panelWidth
                        height: overlay.panelHeight

                        // How far to step aside, continuous rather than a sign, so a panel crossing
                        // the middle mid-fold does not jump.
                        readonly property real side: {
                            var n = overlay.slotCount
                            if (card.isExpanded || n <= 1) return 0
                            return Math.max(-1, Math.min(1, card.shift * n / 2))
                        }

                        transform: Translate {
                            x: card.side * overlay.expandExtra / 2 * overlay.expansion
                        }

                        z: PathView.depth ?? 0

                        // Bound on completion: the attached properties it reads are not ready
                        // while the delegate is created.
                        scale: 1
                        opacity: 0

                        Component.onCompleted: {
                            // Size falls off with distance from the middle
                            // (shift), not in one step.
                            card.scale = Qt.binding(() => card.PathView.onPath
                                ? 1 - overlay.scaleFalloff * Math.abs(card.shift)
                                : 0)
                            card.opacity = Qt.binding(() => card.PathView.onPath ? 1 : 0)
                        }

                        // No Behavior on scale: shift is already animated, and easing it
                        // again made the size lag behind while an arrow key was held. Opacity
                        // keeps one: it really is a step.
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
                        }

                        // The panel's face, which opens out. The delegate keeps a fixed width,
                        // since PathView doesn't re-lay the row when a delegate grows; centred in
                        // it, the face widens both ways.
                        Item {
                            id: face
                            anchors.centerIn: parent
                            width: overlay.panelWidth
                                + (card.isExpanded ? overlay.expandExtra * overlay.expansion : 0)
                            height: parent.height

                            // Holds the corner radius the rest of the panel reads.
                            Rectangle {
                                id: cardMask
                                anchors.fill: parent
                                radius: Theme.radiusLarge
                                color: "transparent"
                                visible: false
                            }

                            // Stands in until the image decodes, so the carousel has
                            // the right shape to lay out.
                            Rectangle {
                                anchors.fill: parent
                                radius: cardMask.radius
                                color: Theme.surfaceContainerHigh
                                visible: thumb.status !== Image.Ready
                            }

                            // Shadow under the middle panel. RectangularShadow, not MultiEffect
                            // over a layer: panels built while the picker was shut had a
                            // never-painted layer, and the shadow came out solid black.
                            RectangularShadow {
                                anchors.fill: parent
                                radius: cardMask.radius
                                offset.y: 10
                                blur: 28
                                color: Theme.shadow
                                opacity: card.isCurrent ? 0.55 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
                                }
                            }

                        // The parallax: the photo behind the narrow panel is over twice as wide and
                        // slides against its travel. ClippingRectangle rounds the corners with no
                        // layer, so there is no texture to capture at the wrong moment.
                        ClippingRectangle {
                            anchors.fill: parent
                            radius: cardMask.radius
                            color: "transparent"
                            visible: thumb.status === Image.Ready

                            Image {
                                id: thumb

                                // No slack once open: the frame already has the screen's shape, and
                                // extra width would crop the picture.
                                readonly property real slack: overlay.parallaxRange
                                    * (card.isExpanded ? 1 - overlay.expansion : 1)

                                width: parent.width + thumb.slack * 2
                                height: parent.height

                                // Centred at rest, hard left at one end of the row and
                                // hard right at the other.
                                x: -thumb.slack * (1 + card.shift)

                                // The cached thumbnail (Wallpaper.buildWallpaperThumbs); the
                                // framing editor opens the full file.
                                source: {
                                    var t = overlay.thumbFor(card.modelData)
                                    return t.length > 0 ? "file://" + t : ""
                                }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true

                                // Height sets the decode: the panel is a tall crop, and a
                                // dozen are live at once.
                                sourceSize.height: Math.round(overlay.panelHeight * 1.3)
                            }
                        }

                        // Ring on the wallpaper in use, so the middle one is not mistaken for it.
                            Rectangle {
                                anchors.fill: parent
                                radius: cardMask.radius
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.accent
                                opacity: card.isActive ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.durMedium }
                                }
                            }

                            // "In use" label: the ring alone read as one more highlight.
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: 10
                                width: inUseRow.implicitWidth + 16
                                height: 24
                                radius: height / 2
                                color: Theme.accent
                                opacity: card.isActive ? 1 : 0
                                scale: card.isActive ? 1 : 0.8
                                visible: opacity > 0

                                Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }
                                Behavior on scale { Elastic { small: true } }

                                Row {
                                    id: inUseRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\u{F012C}"
                                        size: Theme.iconTiny
                                        color: Theme.accentText
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "In use"
                                        color: Theme.accentText
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: Theme.fontText
                                    }
                                }
                            }

                            // Video badge, since its still looks exactly like an image.
                            // Bottom left, clear of the ring.
                            Rectangle {
                                visible: overlay.videos
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                width: 28
                                height: 28
                                radius: height / 2
                                color: Theme.alpha(Theme.background, 0.7)

                                IconGlyph {
                                    anchors.centerIn: parent
                                    // Nudged right: a triangle's visual centre sits
                                    // left of its box's.
                                    anchors.horizontalCenterOffset: 1
                                    text: "\u{F040A}"
                                    size: Theme.iconSmall
                                    color: Theme.textPrimary
                                }
                            }

                            // Clicking the middle card applies it; any other is
                            // brought to the middle first.
                            StateLayer {
                                radius: cardMask.radius
                                // Let drags through to the carousel; the default policy kept
                                // the press until release.
                                gesturePolicy: TapHandler.DragThreshold
                                onTapped: {
                                    if (card.isCurrent) {
                                        overlay.apply()
                                        return
                                    }
                                    overlay.bringToCentre(card.index)
                                }
                            }
                        }
                    }
                }

                // Framing button: acts on the wallpaper in the middle, so it belongs
                // to the row, not to each panel.
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: frameRow.implicitWidth + 24
                    height: 34
                    radius: height / 2
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.outline
                    // No framing for a video: mpv covers the screen itself.
                    visible: !overlay.videos && overlay.files.length > 0

                    Row {
                        id: frameRow
                        anchors.centerIn: parent
                        spacing: 8

                        IconGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰆞"
                            size: Theme.iconSmall
                            color: Theme.textPrimary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Frame"
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontText
                        }
                        KeyCap { anchors.verticalCenter: parent.verticalCenter; key: "f" }
                    }

                    StateLayer {
                        radius: parent.radius
                        onTapped: overlay.startFraming()
                    }
                }
            }

            // Caption

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: overlay.files.length > 0
                spacing: 14

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10

                    // Where in the folder, in a chip.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: countText.implicitWidth + 16
                        height: 22
                        radius: height / 2
                        color: Theme.alpha(Theme.foreground, 0.1)

                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: (carousel.currentIndex + 1) + " / " + overlay.files.length
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }
                    }

                    // The name without the extension, and with underscores and dashes as spaces.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // Capped, so a long name cannot widen the column.
                        width: Math.min(implicitWidth, carousel.width * 0.7)
                        elide: Text.ElideMiddle
                        text: {
                            var path = overlay.files[carousel.currentIndex] || ""
                            return path.split("/").pop().replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").trim()
                        }
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.family: Theme.fontText
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 14

                    KeyHint { key: "\u2190 \u2192"; label: "Browse" }
                    KeyHint {
                        key: "\u21B5"
                        label: overlay.files[carousel.currentIndex] === overlay.current ? "In use" : "Apply"
                    }
                    KeyHint { key: "tab"; label: overlay.videos ? "Images" : "Videos" }
                    KeyHint { key: "f"; label: "Frame"; visible: !overlay.videos }
                    KeyHint { key: "esc"; label: "Close" }
                }
            }
        }

        // Framing editor: the whole picture with the surviving crop lit. Only one axis moves,
        // since the crop keeps the screen's shape; the script reports each axis's span, so
        // nothing is hardcoded per wallpaper.
        Item {
            id: framingView
            anchors.fill: parent

            opacity: overlay.framing ? 1 : 0
            scale: overlay.framing ? 1 : 0.94
            visible: opacity > 0
            enabled: overlay.framing

            Behavior on opacity {
                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }

            Behavior on scale {
                Elastic { small: true }
            }

            readonly property var info: Wallpaper.wallpaperCropInfo

            // Box held whether or not there is a picture yet: measuring an 8K
            // image takes most of a second.
            readonly property real boxWidth: Math.round(overlay.width * 0.62)
            readonly property real boxHeight: Math.round(overlay.height * 0.58)

            readonly property real fit: info
                ? Math.min(boxWidth / info.width, boxHeight / info.height)
                : 1
            readonly property real shownWidth: info ? Math.round(info.width * fit) : 0
            readonly property real shownHeight: info ? Math.round(info.height * fit) : 0
            readonly property real cropWidth: info ? shownWidth * info.coverX : 0
            readonly property real cropHeight: info ? shownHeight * info.coverY : 0
            readonly property real slackX: shownWidth - cropWidth
            readonly property real slackY: shownHeight - cropHeight

            Column {
                anchors.centerIn: parent
                spacing: 22

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Framing"
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: Theme.fontText
                }

                // Fixed-size stage, so the picture changing size (or not existing
                // yet) never moves the column.
                Item {
                    id: canvasBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: framingView.boxWidth
                    height: framingView.boxHeight

                    Text {
                        anchors.centerIn: parent
                        text: "Measuring the image…"
                        color: Theme.textMuted
                        font.pixelSize: 12
                        font.family: Theme.fontText
                        opacity: framingView.info === null ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durShort }
                        }
                    }

                    Item {
                        id: canvas
                        anchors.centerIn: parent
                        width: framingView.shownWidth
                        height: framingView.shownHeight

                        // Fades in with the measurement instead of snapping in mid-transition.
                        opacity: framingView.info === null ? 0 : 1

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
                        }

                        Image {
                            anchors.fill: parent
                            source: overlay.framingPath.length > 0
                                ? "file://" + overlay.framingPath : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            // The whole wallpaper is on screen here, and some are 7680 wide.
                            sourceSize.width: Math.round(framingView.shownWidth * 1.2)
                        }

                        // Everything outside the crop, dimmed: four rectangles, two of them
                        // zero-sized on the pinned axis.
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                color: Theme.alpha(Theme.background, 0.66)
                                x: index === 3 ? cropFrame.x + cropFrame.width : 0
                                y: index === 1 ? cropFrame.y + cropFrame.height
                                               : index >= 2 ? cropFrame.y : 0
                                width: index < 2 ? canvas.width
                                     : index === 2 ? cropFrame.x
                                     : canvas.width - cropFrame.x - cropFrame.width
                                height: index === 0 ? cropFrame.y
                                      : index === 1 ? canvas.height - cropFrame.y - cropFrame.height
                                      : cropFrame.height
                            }
                        }

                        Rectangle {
                            id: cropFrame
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.accent
                            radius: 4
                            width: framingView.cropWidth
                            height: framingView.cropHeight
                            x: framingView.slackX * overlay.focusX
                            y: framingView.slackY * overlay.focusY
                        }

                        // Drag anywhere on the picture; the crop centres on the pointer
                        // along the axis with room.
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeAllCursor
                            onPressed: mouse => overlay.aimFraming(mouse.x, mouse.y,
                                framingView.slackX, framingView.slackY,
                                framingView.cropWidth, framingView.cropHeight)
                            onPositionChanged: mouse => {
                                if (pressed)
                                    overlay.aimFraming(mouse.x, mouse.y,
                                        framingView.slackX, framingView.slackY,
                                        framingView.cropWidth, framingView.cropHeight)
                            }
                        }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: framingView.boxWidth
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: overlay.framingPath.split("/").pop()
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontText
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: framingView.slackX > 1 && framingView.slackY > 1 ? "Drag the picture to place the crop"
                            : framingView.slackX > 1 ? "Drag sideways to place the crop"
                            : framingView.slackY > 1 ? "Drag up and down to place the crop"
                            : "This image already matches the screen"
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontText
                    }

                    Item { width: 1; height: 6 }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14

                        KeyHint { key: "\u2190 \u2191 \u2192 \u2193"; label: "Move" }
                        KeyHint { key: "\u21B5"; label: "Apply" }
                        KeyHint { key: "esc"; label: "Back" }
                    }
                }
            }
        }
    }
}
