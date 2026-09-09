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
        var capped = Math.min(fits, 7, AppState.wallpaperFiles.length)
        if (capped <= 1) return 1
        return capped % 2 === 0 ? capped - 1 : capped
    }

    function close() {
        AppState.wallpapersOpen = false
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
        var path = AppState.wallpaperFiles[carousel.currentIndex]
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
        var path = AppState.wallpaperFiles[carousel.currentIndex]
        if (!path) return
        AppState.setWallpaper(path)
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
        overlay.pendingFocus = AppState.selectedWallpaper
        overlay.restoreFocus()
    }

    function restoreFocus() {
        if (overlay.pendingFocus === "") return
        var i = AppState.wallpaperFiles.indexOf(overlay.pendingFocus)
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
        overlay.centerOnCurrent()
    }
    Component.onCompleted: overlay.centerOnCurrent()

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
        TapHandler {
            onTapped: overlay.framing ? overlay.cancelFraming() : overlay.close()
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
        Keys.onUpPressed: if (overlay.framing) overlay.nudgeFraming(0, -0.02)
        Keys.onDownPressed: if (overlay.framing) overlay.nudgeFraming(0, 0.02)
    }

    // ── Content ──────────────────────────────────────────────────────────

    Item {
        anchors.fill: parent

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

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Wallpaper"
                color: Theme.textPrimary
                font.pixelSize: 18
                font.bold: true
                font.family: Theme.fontMono
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: AppState.wallpaperFiles.length === 0
                text: "No images in ~/Pictures/Wallpapers"
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
                visible: AppState.wallpaperFiles.length > 0

                width: Math.min(overlay.width, overlay.slotCount * overlay.slotWidth)
                height: overlay.panelHeight + 48

                PathView {
                    id: carousel
                    anchors.fill: parent

                    model: AppState.wallpaperFiles
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
                    cacheItemCount: Math.min(AppState.wallpaperFiles.length,
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

                    // A mouse has no fling. Without this the carousel could only
                    // be driven by dragging it, which is the one input a picker
                    // like this will rarely get.
                    WheelHandler {
                        onWheel: event => {
                            if (event.angleDelta.y > 0 || event.angleDelta.x < 0)
                                carousel.decrementCurrentIndex()
                            else
                                carousel.incrementCurrentIndex()
                        }
                    }

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
                        readonly property bool isActive: card.modelData === AppState.selectedWallpaper

                        // Position along the row, -1 to 1. Undefined for an item
                        // that is off the path and not being drawn.
                        readonly property real shift: PathView.shift ?? 0

                        width: overlay.panelWidth
                        height: overlay.panelHeight

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

                        // Mask only. Nothing is ever cast from this rectangle
                        // now, so its colour is arbitrary -- a mask is read for
                        // its alpha. It used to double as the shadow's source,
                        // and since a MultiEffect draws its source as well as
                        // its shadow, the plate itself kept showing: first as a
                        // grey halo, then, painted black to hide it, as a black
                        // outline standing between the photo and its edge.
                        Rectangle {
                            id: cardMask
                            anchors.fill: parent
                            radius: 12
                            color: "#000000"
                            visible: false
                            layer.enabled: true
                        }

                        // Stands in until the image decodes, so the carousel has
                        // something with the right shape to lay out and animate.
                        Rectangle {
                            anchors.fill: parent
                            radius: cardMask.radius
                            color: Theme.surfaceContainerHigh
                            visible: thumb.status !== Image.Ready
                        }

                        // Shadow under the middle panel, cast from the plate
                    // above rather than from the photo.
                    //
                    // The plate is static, which is the point: a layer only
                    // renders when its item does, and an item that is off the
                    // path is scaled to nothing and never drawn. A photo that
                    // finishes loading in that state leaves its layer holding
                    // the empty texture it was given, and the panel comes back
                    // blank -- which is exactly what happened once the whole
                    // folder was kept warm off-path. A solid rectangle has
                    // nothing to arrive late.
                    MultiEffect {
                        anchors.fill: parent
                        source: cardMask
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowBlur: 0.9
                        shadowVerticalOffset: 10
                        autoPaddingEnabled: true
                        shadowOpacity: card.isCurrent ? 0.55 : 0

                        Behavior on shadowOpacity {
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
                            width: parent.width + overlay.parallaxRange * 2
                            height: parent.height

                            // Centred at rest, hard left at one end of the row
                            // and hard right at the other.
                            x: -overlay.parallaxRange * (1 + card.shift)

                            source: "file://" + card.modelData
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

                        // Clicking the middle card applies it; clicking any other
                        // brings it to the middle first. Applying straight from
                        // the edge of the row would mean setting a wallpaper the
                        // user has only seen shrunk behind another one.
                        StateLayer {
                            radius: cardMask.radius
                            onTapped: {
                                if (card.isCurrent) overlay.apply()
                                else carousel.currentIndex = card.index
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
                    interactive: AppState.wallpaperFiles.length > 0
                    onTapped: overlay.startFraming()
                }
            }

            // ── Caption ──────────────────────────────────────────────────

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: AppState.wallpaperFiles.length > 0
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
                        var path = AppState.wallpaperFiles[carousel.currentIndex] || ""
                        return path.split("/").pop()
                    }
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontMono
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (carousel.currentIndex + 1) + " / " + AppState.wallpaperFiles.length
                        + "   ·   " + (AppState.wallpaperFiles[carousel.currentIndex] === AppState.selectedWallpaper
                                       ? "in use" : "Enter to apply")
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
