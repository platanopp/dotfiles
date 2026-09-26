import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

// Full-screen wallpaper picker, opened from the control panel or from the
// bind the config points at "quickshell:wallpapers".
//
// The control panel is 372px wide, which is why the picker is not in it: the
// depth effect below needs the centre item at full size with its neighbours
// scaled behind it, and at panel width that is a row of stamps. Structure
// follows KeybindsOverlay -- mapped for the life of the shell and hidden by
// cutting input, exclusive keyboard focus only while open, pinned to the
// screen it was summoned on.
PanelWindow {
    id: overlay

    property var bar: null
    screen: bar.screen

    // One copy per monitor, and only the one it was opened on shows. Focus
    // follows the mouse here, so matching against live focus would drag the
    // picker to whichever screen the pointer wandered onto.
    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (AppState.wallpapersScreen === "") return bar.monitor.focused
        return bar.monitor.name === AppState.wallpapersScreen
    }

    readonly property bool open: AppState.wallpapersOpen && overlay.onOpeningScreen

    // Unmapped while closed, not merely drawn empty.
    //
    // A layer surface that stays mapped sits above every window under it for
    // the life of the session, and Hyprland composites it each frame whether
    // or not it has anything in it. There were four of these, full-screen, on
    // every monitor.
    //
    // The timer is what lets it close politely: `open` goes false, the fade
    // inside starts, and the surface stays mapped long enough for that fade to
    // play. Without it the window would vanish on the first frame and the
    // fade-out would never be seen.
    //
    // Connections rather than an `onOpenChanged` here, because two of these
    // files already declare one and a second on the same object is a
    // "Property value set multiple times" error.
    visible: overlay.open || unmapDelay.running

    Timer {
        id: unmapDelay
        // The inner fades run on durMedium; the margin covers the frame the
        // Behavior needs to get going.
        interval: Theme.durMedium + 80

        // Recentre here rather than the moment `open` goes false.
        //
        // `visible` above keeps the surface mapped for this whole interval so
        // the fade-out can play, which means that at close time the view is
        // still on screen and mid-animation -- exactly the state the comment
        // on centerOnCurrent says desynchronises the row from its index. By
        // the time this fires the window really is gone, and the carousel can
        // take as long as it likes to travel.
        onTriggered: {
            overlay.section = overlay.sectionInUse()
            overlay.centerOnCurrent()
        }
    }

    Connections {
        target: overlay
        function onOpenChanged() {
            if (!overlay.open) unmapDelay.restart()
        }
    }

    color: "transparent"

    WlrLayershell.namespace: "quickshell:wallpapers"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.keyboardFocus: overlay.open ? WlrKeyboardFocus.Exclusive
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

    // ── Sections ─────────────────────────────────────────────────────────
    //
    // Images and videos share the folder and the carousel, and differ only in
    // what applying one does: an image goes through the cropper to hyprpaper,
    // a video to mpvpaper. So the row is one view over whichever list is
    // selected rather than two views -- everything below reads `files` and
    // `current` and never has to know which kind it is showing.
    property string section: "images"

    readonly property bool videos: overlay.section === "videos"

    readonly property var files: overlay.videos ? AppState.videoWallpaperFiles
                                                : AppState.wallpaperFiles

    // What is in use in this section. With a video playing, no image is: the
    // one underneath is only there for when the video stops, and ringing it
    // would say it is on screen when it is not.
    readonly property string current: overlay.videos
        ? AppState.activeVideoWallpaper
        : (AppState.activeVideoWallpaper === "" ? AppState.selectedWallpaper : "")

    function thumbFor(path) {
        return overlay.videos ? AppState.videoWallpaperThumb(path)
                              : AppState.wallpaperThumb(path)
    }

    // Opens on the section holding what is in use, so the picker lands on it
    // the same way it always has for images.
    function sectionInUse() {
        return AppState.activeVideoWallpaper !== "" ? "videos" : "images"
    }

    function showSection(name) {
        if (overlay.section === name) return
        overlay.framing = false
        overlay.section = name
        // After the model swap has landed, not in the same breath: the view
        // resets its index when the model changes, and setting one on a view
        // that is mid-rebuild is what the comment on centerOnCurrent warns
        // leaves the row and the caption a slot apart.
        Qt.callLater(overlay.centerOnCurrent)
    }

    // ── Geometry ─────────────────────────────────────────────────────────
    //
    // Tall, narrow panels rather than 16:9 cards, and the parallax is the
    // reason. A card shaped like the wallpaper already shows the whole
    // wallpaper, so sliding the photo inside its frame has nothing to
    // slide -- the effect was there and had no room to be seen. A portrait
    // window onto a landscape image is mostly crop, and the crop is what
    // moves.
    //
    // Sized off the screen height rather than its width, because height is
    // what a portrait panel runs out of first.
    readonly property int panelHeight: Math.max(240, Math.min(520, Math.round(overlay.height * 0.46)))
    readonly property int panelWidth: Math.round(panelHeight * 0.46)

    // A hair of a gap, so the row reads as a strip rather than as separate
    // tiles. The centre panel at full size takes the gap back and sits
    // slightly proud of its neighbours, which is what the z-order below is
    // there to resolve.
    readonly property int slotWidth: panelWidth + 8

    // How much a panel shrinks by the time it reaches the end of the row.
    // The far ones land at 0.74, which is enough to read as distance without
    // the row thinning out into stamps.
    readonly property real scaleFalloff: 0.26

    // How far the photo slides inside its panel between one end of the row
    // and the other, which works out at about a quarter of a panel per step.
    //
    // Raised once the travel was shortened: the pan is a thing you watch
    // happen, so cutting the time it happens in cut how much of it landed.
    // The ceiling is not taste, it is the crop -- at this height a 16:9
    // wallpaper fills 884px, and a box wider than that has to be scaled up
    // to cover. This keeps the box at 619.
    readonly property int parallaxRange: Math.round(panelWidth * 0.85)

    // How many panels are kept decoded at once. Past this the carousel goes
    // back to building them as they arrive, which is visible but bounded --
    // the alternative is a wallpaper folder deciding how much memory the
    // shell holds.
    readonly property int maxWarmPanels: 20

    // Odd, so there is always exactly one item in the middle. An even count
    // straddles the centre and the highlight has nowhere to land.
    readonly property int slotCount: {
        var fits = Math.floor(overlay.width / Math.max(1, slotWidth))
        var capped = Math.min(fits, 7, overlay.files.length)
        if (capped <= 1) return 1
        return capped % 2 === 0 ? capped - 1 : capped
    }

    // ── The panel at rest opens out ──────────────────────────────────────
    //
    // Once the row comes to rest, the panel in the middle widens to the
    // screen's own shape and shows the wallpaper whole, the way it will sit
    // on the desktop; its neighbours step aside to make room. The moment the
    // row moves again it folds back to a panel like the others.
    //
    // The width it opens to: the screen's aspect at the panel's height,
    // capped so a very wide screen does not push the row off its edges.
    readonly property int expandedWidth: Math.min(
        Math.round(overlay.width * 0.8),
        Math.round(overlay.panelHeight * overlay.width / Math.max(1, overlay.height)))
    readonly property int expandExtra: Math.max(0, overlay.expandedWidth - overlay.panelWidth)

    // Which panel is open, by index -- deliberately not "the current one".
    // The arrow keys change currentIndex at once and animate the row after,
    // so a panel that followed isCurrent would snap shut and its successor
    // would appear already wide. This one is only handed on once the old
    // panel has finished folding back.
    property int expandedIndex: -1
    property bool wantExpanded: false

    // 0 folded, 1 open. The one number every panel reads, animated here once
    // rather than per panel.
    property real expansion: overlay.wantExpanded && overlay.open && !overlay.framing ? 1 : 0

    Behavior on expansion {
        NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
    }

    // Anything that moves the row folds the panel and starts the wait over;
    // the panel opens again once nothing has moved for a moment. Longer than
    // the fold itself, so by the time it fires the old panel is fully shut
    // and handing the index on cannot make anything jump.
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

    // Opens out a beat after the picker itself has faded in, rather than
    // arriving already wide.
    Connections {
        target: overlay
        function onOpenChanged() {
            if (overlay.open) overlay.unsettle()
            else overlay.wantExpanded = false
        }
    }

    function close() {
        AppState.wallpapersOpen = false
    }

    // A click on a panel away from the middle: bring it there.
    function bringToCentre(index) {
        carousel.currentIndex = index
    }

    // ── Framing ──────────────────────────────────────────────────────────
    //
    // A second mode rather than a second window: it is the same decision as
    // picking a wallpaper, one step further in, and it acts on whichever one
    // the carousel has in the middle.
    property bool framing: false
    property string framingPath: ""

    // Where in the picture the crop sits, 0 to 1 along each axis. Held here
    // rather than in AppState because it is a draft -- nothing outside this
    // overlay should see it until it is applied.
    property real focusX: 0.5
    property real focusY: 0.5

    function startFraming() {
        // Videos are covered by mpv's own panscan; there is nothing to frame.
        if (overlay.videos) return
        var path = overlay.files[carousel.currentIndex]
        if (!path) return
        overlay.framingPath = path
        overlay.framing = true
        // Seeds focusX/focusY once the answer lands; until then the editor
        // says it is measuring rather than drawing a crop in the wrong place.
        AppState.probeWallpaperCrop(path)
    }

    function cancelFraming() {
        overlay.framing = false
    }

    function applyFraming() {
        if (overlay.framingPath.length === 0) return
        AppState.setWallpaperFraming(overlay.framingPath, overlay.focusX, overlay.focusY)
        overlay.framing = false
        overlay.close()
    }

    // Centre the crop on the pointer, along whichever axis has slack. An
    // axis with none keeps its value rather than being driven to a clamped
    // 0, which would look like the drag doing something it is not.
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
        target: AppState
        function onWallpaperCropInfoChanged() {
            var info = AppState.wallpaperCropInfo
            if (!info) return
            overlay.focusX = info.focusX
            overlay.focusY = info.focusY
        }
    }

    function apply() {
        if (carousel.currentIndex < 0) return
        var path = overlay.files[carousel.currentIndex]
        if (!path) return
        if (overlay.videos) AppState.setVideoWallpaper(path)
        else AppState.setWallpaper(path)
        overlay.close()
    }

    // Centre the carousel on the wallpaper that is actually up. Called on
    // the way open rather than bound, so browsing away from it does not get
    // yanked back.
    //
    // Remembered as a path and not as an index, because the thing it has to
    // survive is the model being rebuilt -- and a rebuild is exactly what
    // resets the index. The list is refreshed on the way open, so if it did
    // come back changed, PathView drops to item 0 and this puts it back.
    property string pendingFocus: ""

    function centerOnCurrent() {
        overlay.pendingFocus = overlay.current
        overlay.restoreFocus()
    }

    function restoreFocus() {
        if (overlay.pendingFocus === "") return
        var i = overlay.files.indexOf(overlay.pendingFocus)
        if (i < 0) return
        carousel.currentIndex = i

        // Once honoured it stops applying, so a refresh that lands later
        // does not drag the user back out of wherever they have browsed to.
        overlay.pendingFocus = ""
    }

    // Parked while shut, never on the way open.
    //
    // Setting currentIndex as it opened left the row a slot behind what the
    // caption said: StrictlyEnforceRange moves the view by animating it, and
    // starting that animation on a view that was mid-layout meant the middle
    // of the row and the index disagreed by one. Suppressing the animation
    // to hide the travel is what made it possible to end up out of sync.
    //
    // Closed, the view is invisible, so it can take all the time it wants to
    // get there -- and by the time it fades in it is already settled.
    onOpenChanged: {
        if (overlay.open) return
        overlay.framing = false
        // Centring is left to unmapDelay, once the surface is actually down.
    }
    Component.onCompleted: {
        overlay.section = overlay.sectionInUse()
        overlay.centerOnCurrent()
    }

    // Both of these land after the shell starts, and either can be the one
    // that finally makes the wallpaper in use findable in the list.
    Connections {
        target: AppState
        function onWallpaperFilesChanged() {
            if (!overlay.open) overlay.centerOnCurrent()
        }
        function onSelectedWallpaperChanged() {
            if (!overlay.open) overlay.centerOnCurrent()
        }
        function onVideoWallpaperFilesChanged() {
            if (!overlay.open) overlay.centerOnCurrent()
        }
        // The remembered video arrives a moment after the shell starts, and
        // is what says the picker should open on the video section at all.
        function onActiveVideoWallpaperChanged() {
            if (overlay.open) return
            overlay.section = overlay.sectionInUse()
            overlay.centerOnCurrent()
        }
    }

    // ── Backdrop ─────────────────────────────────────────────────────────
    //
    // Heavier than the cheatsheet's 0.38. That one sits over text the reader
    // may want to keep reading; this one sits over a wallpaper, and the
    // whole job is judging images against a neutral ground.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.background, 0.72)
        opacity: overlay.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        // Same stepping back as Escape, so clicking away from the editor
        // does not throw out the whole picker along with the framing.
        //
        // Not for a click that lands in the carousel's band, though. The
        // panels let a press through so a drag can reach the view (see their
        // gesturePolicy), and a press that is let through is also seen here:
        // a click on a panel at the side used to close the picker in the same
        // breath as it asked to be brought to the middle -- and closing
        // recentres the row, so it looked as if the click did nothing. By
        // height and not by the band's rectangle, because an opened-out
        // middle panel pushes its neighbours past the carousel's own edges.
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

    // Focus lives on an item rather than the window so the keys have
    // somewhere to land; released on close so the shell stops holding them.
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: overlay.open

        // Escape steps back one mode rather than always closing: from the
        // framing editor it returns to the row, and only from the row does
        // it leave.
        Keys.onEscapePressed: overlay.framing ? overlay.cancelFraming() : overlay.close()
        Keys.onReturnPressed: overlay.framing ? overlay.applyFraming() : overlay.apply()
        Keys.onEnterPressed: overlay.framing ? overlay.applyFraming() : overlay.apply()

        // In the row the arrows change wallpaper; in the editor they move the
        // crop, in steps fine enough to place it and coarse enough to cross
        // the picture without holding the key down.
        Keys.onLeftPressed: overlay.framing ? overlay.nudgeFraming(-0.02, 0)
                                            : carousel.decrementCurrentIndex()
        Keys.onRightPressed: overlay.framing ? overlay.nudgeFraming(0.02, 0)
                                             : carousel.incrementCurrentIndex()
        Keys.onTabPressed: if (!overlay.framing)
            overlay.showSection(overlay.videos ? "images" : "videos")
        Keys.onUpPressed: if (overlay.framing) overlay.nudgeFraming(0, -0.02)
        Keys.onDownPressed: if (overlay.framing) overlay.nudgeFraming(0, 0.02)
    }

    // ── Content ──────────────────────────────────────────────────────────

    Item {
        anchors.fill: parent

        // The wheel turns the carousel wherever the pointer is. It used to
        // work only over the row itself, a strip across the middle of a
        // full-screen picker that is easy to miss.
        //
        // One step per notch, not per event. A classic wheel sends 120 units
        // a notch in one event; a high-resolution one -- the Logitech here --
        // or a touchpad sends the same 120 in several small events, and
        // stepping on each of them made one flick of the finger run half the
        // row. So the deltas are summed and a step is taken per 120.
        WheelHandler {
            id: wheel
            target: null
            enabled: overlay.open && !overlay.framing

            property real pending: 0

            onWheel: event => {
                // Up or left goes back; down or right goes forward. Vertical
                // wins when both are present, as it does on a mouse.
                var d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
                if (d === 0) return
                // A change of direction starts afresh rather than first paying
                // off whatever was left over going the other way.
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
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        // Stepping into the framing editor and back.
        //
        // Both sides move the same way -- fading while growing slightly
        // towards the viewer -- and that one pair of bindings gives both
        // directions for free. Going in, the row grows past the viewer as
        // the editor rises from behind it; coming back, the same values run
        // the other way, so the editor recedes and the row settles forward
        // into place. Nothing has to know which way it is going.
        Column {
            id: carouselSide
            anchors.centerIn: parent
            spacing: 28

            opacity: overlay.framing ? 0 : 1
            scale: overlay.framing ? 1.06 : 1
            visible: opacity > 0
            // Input follows the mode, not the fade: a click landing during
            // the couple of hundred milliseconds either view is still
            // half-drawn should go to the one being opened.
            enabled: !overlay.framing

            Behavior on opacity {
                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }

            Behavior on scale {
                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }

            // The section switch, in the title's place. Two segments in one
            // pill, the selected one filled -- the same shape the control
            // panel uses for its choices, so it reads as a choice and not as
            // two buttons that happen to sit together.
            Rectangle {
                id: sectionSwitch
                anchors.horizontalCenter: parent.horizontalCenter
                width: sectionRow.implicitWidth + 8
                height: 40
                radius: height / 2
                color: Theme.surfaceContainer
                border.width: 1
                border.color: Theme.outline

                // The fill slides between the two rather than blinking from one
                // to the other, so the switch says which way it went.
                Rectangle {
                    y: 4
                    height: parent.height - 8
                    radius: height / 2
                    color: Theme.accent
                    x: 4 + (overlay.videos ? imagesTab.width : 0)
                    width: overlay.videos ? videosTab.width : imagesTab.width

                    Behavior on x {
                        NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
                    }
                    Behavior on width {
                        NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
                    }
                }

                Row {
                    id: sectionRow
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Repeater {
                        model: [
                            { name: "images", label: "Images", glyph: "\u{F02E9}",
                              count: AppState.wallpaperFiles.length },
                            { name: "videos", label: "Videos", glyph: "\u{F0567}",
                              count: AppState.videoWallpaperFiles.length }
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
                                    font.family: Theme.fontMono
                                    color: tab.selected ? Theme.accentText : Theme.textSecondary
                                    Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tab.modelData.count
                                    font.pixelSize: 11
                                    font.family: Theme.fontMono
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

                // Widths of the two segments, for the sliding fill. Filled in by
                // the delegates themselves; a Repeater's items are not reachable
                // by id from outside it.
                QtObject { id: imagesTab; property real width: 0 }
                QtObject { id: videosTab; property real width: 0 }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: overlay.files.length === 0
                text: overlay.videos
                    ? "No videos in ~/Pictures/Wallpapers  (.mp4 .webm .mkv .mov)"
                    : "No images in ~/Pictures/Wallpapers"
                color: Theme.textMuted
                font.pixelSize: 13
                font.family: Theme.fontMono
            }

            // ── The carousel ─────────────────────────────────────────────
            //
            // Depth comes from three things working together, and none of
            // them is a real parallax on its own:
            //
            //   1. The path is two straight lines with a PathAttribute for z
            //      running 0 -> 1 -> 0. It bends nothing; it only says who
            //      draws on top. Panels rise above their neighbours as they
            //      approach the middle and sink again on the way out.
            //   2. Size falls off with distance from the middle, so the row
            //      recedes rather than stepping down once.
            //   3. A shadow fades in under the middle panel alone.
            //
            // The parallax proper is in the delegate: the photo inside each
            // panel slides against the panel's own travel.
            Item {
                id: carouselArea
                anchors.horizontalCenter: parent.horizontalCenter
                visible: overlay.files.length > 0

                width: Math.min(overlay.width, overlay.slotCount * overlay.slotWidth)
                height: overlay.panelHeight + 48

                PathView {
                    id: carousel
                    anchors.fill: parent

                    model: overlay.files
                    pathItemCount: overlay.slotCount
                    // Enough to hold the whole folder, not a window around
                    // the visible seven.
                    //
                    // A PathView destroys the delegates that leave the row and
                    // builds new ones at the other end, and a new delegate is
                    // a new Image with nothing decoded yet -- which is the
                    // grey placeholder flicking past when an arrow key is held
                    // down. With room for every wallpaper, a panel is built
                    // once and then simply moves.
                    //
                    // Capped, because this is memory held for as long as the
                    // shell runs: these decode to about 2.8 MB each at the
                    // size the panels draw them, so the ceiling is roughly
                    // 55 MB for a very large folder and 39 MB for this one.
                    cacheItemCount: Math.min(overlay.files.length,
                                             overlay.maxWarmPanels)

                    snapMode: PathView.SnapToItem
                    preferredHighlightBegin: 0.5
                    preferredHighlightEnd: 0.5
                    highlightRangeMode: PathView.StrictlyEnforceRange
                    // Short enough that a held arrow key does not queue up a
                    // backlog of travel to sit through.
                    highlightMoveDuration: Theme.durMedium

                    // Fires when the model is rebuilt, which is the moment the
                    // index gets reset out from under the picker.
                    onCountChanged: overlay.restoreFocus()

                    // Both, because they do not always come together: a click
                    // on a far panel changes the index and then animates, a
                    // drag moves the offset without touching the index until
                    // it snaps. Offset changes every frame of the travel, so
                    // the settle wait only starts counting once it stops.
                    onCurrentIndexChanged: overlay.unsettle()
                    onOffsetChanged: overlay.unsettle()

                    // Grab anywhere on the row, not only near the path.
                    //
                    // PathView takes a drag only if the press lands within
                    // dragMargin of its path, and the path is a single
                    // horizontal line at half height -- so with the default of
                    // 0, a drag had to start on that line to do anything, and
                    // most of every panel was dead to it.
                    dragMargin: carousel.height / 2

                    // Two attributes ride the path. "depth" is the z-order that
                    // brings the middle item to the front. "shift" is where along
                    // the row an item is, -1 at the left end through 0 in the
                    // middle to 1 at the right, and it is what drives the photo
                    // inside each frame.
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

                        // Position along the row, -1 to 1. Undefined for an item
                        // that is off the path and not being drawn.
                        readonly property real shift: PathView.shift ?? 0

                        // Open, this panel widens by the full extra; everyone
                        // else steps half of it away, left or right, so the
                        // row stays symmetric around the wide one.
                        readonly property bool isExpanded: card.index === overlay.expandedIndex

                        width: overlay.panelWidth
                        height: overlay.panelHeight

                        // How far to step aside, as a fraction of half the
                        // extra. Continuous rather than a sign: a panel crossing
                        // the middle while the fold is still running would
                        // otherwise jump from one side to the other. Adjacent
                        // panels sit 2/n apart in shift, so they reach the full
                        // step and everything further out does too.
                        readonly property real side: {
                            var n = overlay.slotCount
                            if (card.isExpanded || n <= 1) return 0
                            return Math.max(-1, Math.min(1, card.shift * n / 2))
                        }

                        transform: Translate {
                            x: card.side * overlay.expandExtra / 2 * overlay.expansion
                        }

                        z: PathView.depth ?? 0

                        // Rebound on completion rather than declared: the
                        // attached properties these read are not available while
                        // the delegate is still being created.
                        scale: 1
                        opacity: 0

                        Component.onCompleted: {
                            // Size falls off with distance from the middle
                            // rather than in one step. The step version made the
                            // row read as one big panel with six identical ones
                            // beside it -- there was a centre, but no sense of
                            // the rest receding from it. shift already carries
                            // that distance, 0 in the middle out to 1 at either
                            // end, so the scale can just ride it.
                            card.scale = Qt.binding(() => card.PathView.onPath
                                ? 1 - overlay.scaleFalloff * Math.abs(card.shift)
                                : 0)
                            card.opacity = Qt.binding(() => card.PathView.onPath ? 1 : 0)
                        }

                        // No Behavior on scale, deliberately. shift is already
                        // an animated value -- the view eases its own offset,
                        // and the scale is a plain function of it, so it arrives
                        // animated for free. Easing it a second time meant the
                        // size was not following shift but chasing it a third of
                        // a second behind, which is what showed up as panels
                        // taking their time to reach the right size when the
                        // arrow keys were held down. Opacity below keeps its
                        // Behavior: that one really is a step, on and off the
                        // path, with nothing to interpolate it.
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
                        }

                        // The panel's face: everything the panel draws, and the
                        // part that opens out.
                        //
                        // The delegate itself keeps the panel's width and never
                        // changes it. PathView places a delegate by where its
                        // centre lands on the path when it lays the row out, and
                        // nothing says it lays the row out again because a
                        // delegate got wider -- a panel widening itself could
                        // just as well grow off to the right. Centred inside a
                        // box of fixed size, the face widens both ways by
                        // construction.
                        Item {
                            id: face
                            anchors.centerIn: parent
                            width: overlay.panelWidth
                                + (card.isExpanded ? overlay.expandExtra * overlay.expansion : 0)
                            height: parent.height

                            // Holds the corner radius the rest of the panel reads.
                            // It used to be the mask a MultiEffect cast the shadow
                            // from, with a layer under it -- see the shadow below
                            // for why that went.
                            Rectangle {
                                id: cardMask
                                anchors.fill: parent
                                radius: 12
                                color: "transparent"
                                visible: false
                            }

                            // Stands in until the image decodes, so the carousel has
                            // something with the right shape to lay out and animate.
                            Rectangle {
                                anchors.fill: parent
                                radius: cardMask.radius
                                color: Theme.surfaceContainerHigh
                                visible: thumb.status !== Image.Ready
                            }

                            // Shadow under the middle panel.
                            //
                            // RectangularShadow and not a MultiEffect over a layered
                            // mask. A layer is rendered only when its item is drawn,
                            // and panels get built while the picker is shut -- which
                            // is every time the section flips to videos, since that
                            // happens before it opens. The layer then held a texture
                            // that was never painted, and the shadow came out as a
                            // hard block of pure black under the panel. This draws
                            // the shape itself, analytically, with no texture to go
                            // stale.
                            RectangularShadow {
                                anchors.fill: parent
                                radius: cardMask.radius
                                offset.y: 10
                                blur: 28
                                color: "#000000"
                                opacity: card.isCurrent ? 0.55 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
                                }
                            }

                        // The parallax. The panel is a narrow window; the photo
                        // behind it is over twice as wide and slides the other way
                        // as the panel travels, so it covers less ground than its
                        // own frame does. That lag is the whole effect -- something
                        // moving slower than the thing in front of it reads as
                        // further away.
                        //
                        // ClippingRectangle rounds the corners by clipping, with no
                        // layer and no mask, so the photo is drawn straight and
                        // there is no texture to be captured at the wrong moment.
                        ClippingRectangle {
                            anchors.fill: parent
                            radius: cardMask.radius
                            color: "transparent"
                            visible: thumb.status === Image.Ready

                            Image {
                                id: thumb

                                // The slack the parallax slides through, gone once
                                // the panel is open: opened out, the frame is already
                                // the screen's shape, and any extra width would only
                                // make the cover crop zoom in and cut the top and
                                // bottom off the picture it is meant to show whole.
                                readonly property real slack: overlay.parallaxRange
                                    * (card.isExpanded ? 1 - overlay.expansion : 1)

                                width: parent.width + thumb.slack * 2
                                height: parent.height

                                // Centred at rest, hard left at one end of the row
                                // and hard right at the other.
                                x: -thumb.slack * (1 + card.shift)

                                // The cached thumbnail, not the original: see
                                // AppState.buildWallpaperThumbs. The framing editor
                                // below still opens the full file, because judging a
                                // crop wants every pixel.
                                source: {
                                    var t = overlay.thumbFor(card.modelData)
                                    return t.length > 0 ? "file://" + t : ""
                                }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true

                                // The panel is a tall crop of a wide picture, so
                                // height is what sets the decode -- a dozen of
                                // these are live at once.
                                sourceSize.height: Math.round(overlay.panelHeight * 1.3)
                            }
                        }

                        // Ring on the wallpaper that is currently up, so the one
                            // in the middle is not mistaken for the one in use.
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

                            // Marks a panel as a video, since the still in it looks
                            // exactly like an image. Bottom left, clear of the ring.
                            Rectangle {
                                visible: overlay.videos
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                width: 28
                                height: 28
                                radius: 14
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

                            // Clicking the middle card applies it; clicking any other
                            // brings it to the middle first. Applying straight from
                            // the edge of the row would mean setting a wallpaper the
                            // user has only seen shrunk behind another one.
                            StateLayer {
                                radius: cardMask.radius
                                // Let a drag through to the carousel. The default
                                // policy holds the press for itself until release,
                                // which is right for a button and meant a drag that
                                // started on a panel -- where anyone grabs a
                                // carousel -- never reached the view.
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

                // Framing, in the corner the carousel leaves free. It acts on
                // whichever wallpaper is in the middle, so it belongs to the
                // row rather than to any one panel -- a button per panel would
                // be six invitations to reframe something the user is not
                // looking at.
                IconButton {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    size: 34
                    icon: "󰆞"
                    // Given a fill of its own. A bare glyph over the dimmed
                    // desktop reads as a smudge rather than as something to
                    // press, and this one sits in a corner with nothing
                    // beside it to borrow context from.
                    color: Theme.surfaceContainerHigh
                    iconColor: Theme.textPrimary
                    interactive: overlay.files.length > 0
                    // No framing for a video: mpv covers the screen itself.
                    visible: !overlay.videos
                    onTapped: overlay.startFraming()
                }
            }

            // ── Caption ──────────────────────────────────────────────────

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: overlay.files.length > 0
                spacing: 6

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Sized off the carousel, not off the text. Bound to its
                    // own implicitWidth, a long file name is free to grow the
                    // column it sits in and shove everything else around.
                    width: carousel.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: {
                        var path = overlay.files[carousel.currentIndex] || ""
                        return path.split("/").pop()
                    }
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontMono
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (carousel.currentIndex + 1) + " / " + overlay.files.length
                        + "   ·   " + (overlay.files[carousel.currentIndex] === overlay.current
                                       ? "in use" : "Enter to apply")
                        + "   ·   Tab for " + (overlay.videos ? "images" : "videos")
                        + "   ·   Esc to close"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                }
            }
        }

        // ── Framing ──────────────────────────────────────────────────────
        //
        // Which part of the wallpaper the desktop actually shows. The whole
        // picture is on screen here and the bright rectangle is the piece
        // that survives -- the opposite of showing the crop and asking the
        // user to picture the rest.
        //
        // Only one axis ever moves. The crop keeps the screen's shape, so one
        // dimension always runs out first and is pinned; the script reports
        // how much of each axis the crop spans, and which way the drag goes
        // falls out of that rather than being hardcoded per wallpaper.
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
                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }

            readonly property var info: AppState.wallpaperCropInfo

            // The box the picture is fitted into, held whether or not there
            // is a picture yet. Measuring an 8K wallpaper takes the better
            // part of a second, and a column that grew when the answer
            // arrived would re-centre everything under the pointer.
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
                    color: Theme.textPrimary
                    font.pixelSize: 18
                    font.bold: true
                    font.family: Theme.fontMono
                }

                // Fixed-size stage. The picture inside it changes size from
                // one wallpaper to the next and starts out not existing at
                // all, and none of that is allowed to move the column.
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
                        font.family: Theme.fontMono
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

                        // Arrives with the measurement rather than snapping in
                        // behind the transition that is still running.
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
                            // The whole wallpaper is on screen at once here, and
                            // one of these is 7680 across.
                            sourceSize.width: Math.round(framingView.shownWidth * 1.2)
                        }

                        // Everything outside the crop, dimmed. Four rectangles
                        // rather than one with a hole in it, and on any given
                        // wallpaper two of them come out zero-sized -- the pinned
                        // axis has nothing left over to cover.
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
                            width: framingView.cropWidth
                            height: framingView.cropHeight
                            x: framingView.slackX * overlay.focusX
                            y: framingView.slackY * overlay.focusY
                        }

                        // Drag anywhere on the picture; the crop centres on the
                        // pointer along whichever axis has room. Grabbing the
                        // rectangle itself would mean aiming at it first, and it
                        // is usually most of the picture anyway.
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
                        font.family: Theme.fontMono
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            var how = framingView.slackX > 1 && framingView.slackY > 1 ? "Drag"
                                : framingView.slackX > 1 ? "Drag sideways"
                                : framingView.slackY > 1 ? "Drag up and down"
                                : "This image already matches the screen"
                            return how + "   ·   Enter to apply   ·   Esc to go back"
                        }
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                    }
                }
            }
        }
    }
}
