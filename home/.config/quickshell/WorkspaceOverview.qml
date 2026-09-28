import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

// The workspace overview (Super+Tab): every workspace side by side, each a
// small picture of its monitor -- the wallpaper, and its windows where they
// sit, drawn from a capture of each window taken as the overview opens.
//
//   click a window        go to it (its workspace comes with it)
//   click a workspace     go there; the last card, +, is a new one
//   drag a window         move it to the workspace it is dropped on
//   arrows / Tab, Enter   choose a workspace, go there
//   1 - 9                 go straight to that workspace
//   Esc, or Super+Tab     close
//
// Same house pattern as the launcher: mapped only while up, exclusive
// keyboard while up, pinned to the screen it opened on. The keyboard grab is
// held through the fade out when dismissed (changing it mid-fade drops the
// surface for two frames -- see AppLauncher), and let go at once when the
// overview closes to go somewhere, so the window gone to gets the keyboard.
PanelWindow {
    id: overview

    property var bar: null
    screen: bar.screen

    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (AppState.overviewScreen === "") return bar.monitor.focused
        return bar.monitor.name === AppState.overviewScreen
    }

    readonly property bool open: AppState.overviewOpen && overview.onOpeningScreen

    // Mapped from opening until the fade out has played (see AppLauncher's
    // `shown` for why this is not `open || timer.running`).
    property bool shown: false
    // Closing to go somewhere: hidden at once, keyboard let go at once.
    property bool leaving: false

    visible: overview.shown

    Timer {
        id: unmapDelay
        interval: 170 + 60
        onTriggered: overview.shown = false
    }

    Connections {
        target: overview
        function onOpenChanged() {
            if (overview.open) {
                unmapDelay.stop()
                overview.leaving = false
                overview.dragged = null
                overview.pointerSteers = false
                overview.lastPointer = Qt.point(-1, -1)
                // Where every window is, fresh: the positions below are read
                // from these, and Quickshell only fills them in on request.
                Hyprland.refreshWorkspaces()
                Hyprland.refreshToplevels()
                Hyprland.refreshMonitors()
                overview.shown = true
                overview.selected = Math.max(0, overview.indexOfFocused())
                keys.forceActiveFocus()
            } else {
                unmapDelay.restart()
            }
        }
    }

    color: "transparent"

    WlrLayershell.namespace: "quickshell:overview"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: overview.open || (overview.shown && !overview.leaving)
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // ── What is where ────────────────────────────────────────────────────

    // A monitor's box in the layout, in logical pixels.
    function geometryOf(monitor) {
        var o = monitor ? monitor.lastIpcObject : null
        if (!o || !o.width) return { x: 0, y: 0, w: 1920, h: 1080 }
        var s = o.scale || 1
        var rotated = o.transform % 2 === 1
        return { x: o.x, y: o.y, w: (rotated ? o.height : o.width) / s, h: (rotated ? o.width : o.height) / s }
    }

    // One entry per workspace, in order, and a last one to make a new
    // workspace with. Built only while the overview is up.
    readonly property var cards: {
        if (!overview.shown) return []
        // The workspace on this screen's monitor: the overview opens on the
        // focused one. Hyprland.focusedWorkspace is only known once an event
        // has named it, and was null here; the monitor's is what the bar's
        // workspace pill reads too.
        var focusedId = bar.monitor && bar.monitor.activeWorkspace ? bar.monitor.activeWorkspace.id : -1
        var wss = Hyprland.workspaces.values.filter(function(w) { return w.id > 0 })
        wss.sort(function(a, b) { return a.id - b.id })
        var tops = Hyprland.toplevels.values
        var out = []
        var maxId = 0
        for (var i = 0; i < wss.length; i++) {
            var ws = wss[i]
            maxId = Math.max(maxId, ws.id)
            var wins = []
            for (var t = 0; t < tops.length; t++) {
                var top = tops[t]
                if (!top.workspace || top.workspace.id !== ws.id) continue
                var o = top.lastIpcObject || {}
                if (!o.class || o.mapped === false || !o.at || !o.size) continue
                wins.push({ toplevel: top, address: top.address, cls: o.class, title: o.title || "",
                            x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1],
                            floating: !!o.floating, fullscreen: (o.fullscreen || 0) > 0,
                            recency: o.focusHistoryID === undefined ? 99 : o.focusHistoryID })
            }
            // Tiled under floating, and within each the most recently used on
            // top -- the order they are stacked on screen.
            wins.sort(function(a, b) {
                if (a.floating !== b.floating) return a.floating ? 1 : -1
                return b.recency - a.recency
            })
            out.push({ id: ws.id, name: ws.name, geom: overview.geometryOf(ws.monitor),
                       monitor: ws.monitor ? ws.monitor.name : "",
                       focused: ws.id === focusedId,
                       active: ws.monitor && ws.monitor.activeWorkspace ? ws.monitor.activeWorkspace.id === ws.id : false,
                       windows: wins, isNew: false })
        }
        var here = overview.geometryOf(bar.monitor)
        out.push({ id: maxId + 1, name: String(maxId + 1), geom: here, monitor: "",
                   focused: false, active: false, windows: [], isNew: true })
        return out
    }

    function indexOfFocused() {
        for (var i = 0; i < overview.cards.length; i++)
            if (overview.cards[i].focused) return i
        return 0
    }

    // One row, as tall as fits: every card as high as the others, as wide as
    // its monitor is for that height.
    readonly property real cardHeight: {
        var aspects = 0
        for (var i = 0; i < overview.cards.length; i++)
            aspects += overview.cards[i].geom.w / overview.cards[i].geom.h
        var room = overview.width * 0.92 - overview.cardSpacing * Math.max(0, overview.cards.length - 1)
        return Math.max(60, Math.min(overview.height * 0.3, 320, aspects > 0 ? room / aspects : 320))
    }
    readonly property int cardSpacing: 22

    property int selected: 0

    // Whether the pointer has moved since the overview opened. Only then
    // does hovering pick a card: opening under a pointer that sat still put
    // the selection on whichever card came up beneath it, not the workspace
    // you are on (the launcher had the same trouble).
    property bool pointerSteers: false
    property point lastPointer: Qt.point(-1, -1)

    // ── Acting ───────────────────────────────────────────────────────────

    function close() {
        AppState.overviewOpen = false
    }

    property var pending: null

    // Closes at once and does `what` a moment later, once the keyboard has
    // been let go -- or focus would be asked to move into the grab.
    function leaveThen(what) {
        overview.leaving = true
        overview.pending = what
        overview.close()
        actTimer.restart()
    }

    Timer {
        id: actTimer
        interval: 30
        onTriggered: {
            var f = overview.pending
            overview.pending = null
            if (f) f()
        }
    }

    function dispatch(lua) {
        Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(" + lua + ")"])
    }

    function goToWorkspace(id) {
        overview.leaveThen(function() { overview.dispatch("hl.dsp.focus({ workspace = " + id + " })") })
    }

    function goToWindow(address) {
        overview.leaveThen(function() {
            overview.dispatch("hl.dsp.focus({ window = 'address:0x" + address + "' })")
        })
    }

    // Moved without following it: the overview stays, and shows it arrive.
    function moveWindow(address, id) {
        overview.dispatch("hl.dsp.window.move({ workspace = " + id
                          + ", window = 'address:0x" + address + "', follow = false })")
        refreshAfterMove.restart()
    }

    Timer {
        id: refreshAfterMove
        interval: 120
        onTriggered: {
            Hyprland.refreshWorkspaces()
            Hyprland.refreshToplevels()
        }
    }

    // ── Dragging a window ────────────────────────────────────────────────
    property var dragged: null          // the window's entry, while dragged
    property point dragPoint: Qt.point(0, 0)
    property size dragSize: Qt.size(0, 0)

    function cardAt(point) {
        for (var i = 0; i < cardRepeater.count; i++) {
            var card = cardRepeater.itemAt(i)
            if (!card) continue
            var p = card.mapFromItem(content, point.x, point.y)
            if (p.x >= 0 && p.y >= 0 && p.x <= card.width && p.y <= card.height) return i
        }
        return -1
    }

    readonly property int dropTarget: overview.dragged ? overview.cardAt(overview.dragPoint) : -1

    // ── Drawing ──────────────────────────────────────────────────────────

    // The desktop behind, dimmed (and blurred by Hyprland's layer rule).
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: overview.open && !overview.leaving ? 1 : 0

        Behavior on opacity {
            enabled: !overview.leaving
            NumberAnimation { duration: 170; easing.type: Easing.OutQuad }
        }

        TapHandler {
            onTapped: overview.close()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: overview.open && !overview.leaving ? 1 : 0
        scale: overview.open ? 1 : 0.96

        Behavior on opacity {
            enabled: !overview.leaving
            NumberAnimation { duration: 170; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        HoverHandler {
            onPointChanged: {
                var p = point.position
                var last = overview.lastPointer
                overview.lastPointer = p
                if (last.x >= 0 && (Math.abs(p.x - last.x) >= 1 || Math.abs(p.y - last.y) >= 1))
                    overview.pointerSteers = true
            }
        }

        // Keyboard.
        Item {
            id: keys
            focus: true
            Keys.onPressed: event => {
                var n = overview.cards.length
                if (event.key === Qt.Key_Escape) {
                    overview.close()
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab
                           || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    overview.selected = ((overview.selected - 1) % n + n) % n
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    overview.selected = (overview.selected + 1) % n
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (overview.cards[overview.selected]) overview.goToWorkspace(overview.cards[overview.selected].id)
                } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    overview.goToWorkspace(event.key - Qt.Key_0)
                } else {
                    return
                }
                event.accepted = true
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -overview.height * 0.04
            spacing: 26

            // The same small caps the panels label their sections with.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Workspaces"
                color: Theme.textSecondary
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1.6
                font.capitalization: Font.AllUppercase
                font.family: Theme.fontMono
            }

            Row {
                id: cardRow
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: overview.cardSpacing

                Repeater {
                    id: cardRepeater
                    model: overview.cards

                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index

                        readonly property var geom: card.modelData.geom
                        readonly property bool chosen: overview.selected === card.index
                        readonly property bool dropping: overview.dropTarget === card.index
                                                         && overview.dragged
                                                         && overview.dragged.workspace !== card.modelData.id

                        width: Math.round(overview.cardHeight * card.geom.w / card.geom.h)
                        height: overview.cardHeight + labelRow.height + 10

                        // The card itself: glass, the pills' shadow.
                        Item {
                            id: face
                            width: parent.width
                            height: overview.cardHeight
                            scale: cardHover.hovered || card.dropping ? 1.03 : 1

                            Behavior on scale {
                                NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutCubic }
                            }

                            Rectangle {
                                id: faceGlass
                                anchors.fill: parent
                                radius: 16
                                color: Theme.glass
                                visible: false
                                layer.enabled: true
                            }

                            MultiEffect {
                                source: faceGlass
                                anchors.fill: faceGlass
                                shadowEnabled: true
                                shadowColor: "#000000"
                                shadowOpacity: 0.5
                                shadowBlur: 0.8
                                shadowVerticalOffset: 6
                                autoPaddingEnabled: true
                            }

                            ClippingRectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 13
                                color: "transparent"

                                // The desktop the windows sit on.
                                Image {
                                    anchors.fill: parent
                                    visible: !card.modelData.isNew
                                    source: AppState.wallpaperStill.length > 0 ? "file://" + AppState.wallpaperStill : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 480
                                    opacity: 0.75
                                }

                                // A new workspace: a plus, where the windows would be.
                                IconGlyph {
                                    anchors.centerIn: parent
                                    visible: card.modelData.isNew
                                    text: "\u{F0415}"
                                    color: Theme.textMuted
                                    size: 28
                                }

                                Repeater {
                                    model: card.modelData.windows

                                    delegate: Item {
                                        id: win
                                        required property var modelData

                                        readonly property real sx: face.width / card.geom.w
                                        readonly property real sy: face.height / card.geom.h
                                        readonly property bool whole: win.modelData.fullscreen

                                        x: whole ? 0 : (win.modelData.x - card.geom.x) * sx
                                        y: whole ? 0 : (win.modelData.y - card.geom.y) * sy
                                        width: whole ? parent.width : Math.max(12, win.modelData.w * sx)
                                        height: whole ? parent.height : Math.max(10, win.modelData.h * sy)
                                        opacity: overview.dragged && overview.dragged.address === win.modelData.address ? 0.3 : 1

                                        ClippingRectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: Theme.surfaceContainerHigh

                                            ScreencopyView {
                                                id: shot
                                                anchors.fill: parent
                                                captureSource: overview.shown ? win.modelData.toplevel.wayland : null
                                                live: false
                                            }
                                        }

                                        // Its app, over the middle -- small
                                        // windows are otherwise hard to tell apart.
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: Qt.rgba(0, 0, 0, 0.45)
                                            visible: win.width > 44 && win.height > 36

                                            IconImage {
                                                anchors.centerIn: parent
                                                implicitSize: 20
                                                mipmap: true
                                                source: {
                                                    var e = DesktopEntries.heuristicLookup(win.modelData.cls)
                                                    return Quickshell.iconPath(e ? e.icon : win.modelData.cls.toLowerCase(),
                                                                               "application-x-executable")
                                                }
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 6
                                            color: "transparent"
                                            border.width: winHover.hovered ? 2 : 1
                                            border.color: winHover.hovered ? AppState.themeAccent : Qt.rgba(1, 1, 1, 0.12)
                                        }

                                        HoverHandler {
                                            id: winHover
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        TapHandler {
                                            onTapped: overview.goToWindow(win.modelData.address)
                                        }

                                        DragHandler {
                                            id: drag
                                            target: null
                                            onActiveChanged: {
                                                if (active) {
                                                    overview.dragSize = Qt.size(win.width, win.height)
                                                    overview.dragged = Object.assign({}, win.modelData,
                                                                                     { workspace: card.modelData.id })
                                                } else if (overview.dragged) {
                                                    var to = overview.dropTarget
                                                    var w = overview.dragged
                                                    overview.dragged = null
                                                    if (to >= 0 && overview.cards[to].id !== w.workspace)
                                                        overview.moveWindow(w.address, overview.cards[to].id)
                                                }
                                            }
                                            onCentroidChanged: {
                                                if (active)
                                                    overview.dragPoint = win.mapToItem(content, centroid.position.x, centroid.position.y)
                                            }
                                        }
                                    }
                                }
                            }

                            // Where you are, where the keyboard is, where a
                            // window would drop.
                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: "transparent"
                                border.width: card.chosen || card.dropping || card.modelData.focused ? 2 : 1
                                border.color: card.dropping ? AppState.themeAccent
                                            : card.chosen ? AppState.themeAccent
                                            : card.modelData.focused ? Theme.alpha(AppState.themeAccent, 0.5)
                                            : Theme.outline

                                Behavior on border.color {
                                    ColorAnimation { duration: Theme.durShort }
                                }
                            }

                            HoverHandler {
                                id: cardHover
                                onHoveredChanged: if (hovered && overview.pointerSteers) overview.selected = card.index
                            }

                            TapHandler {
                                onTapped: overview.goToWorkspace(card.modelData.id)
                            }
                        }

                        Row {
                            id: labelRow
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: face.bottom
                            anchors.topMargin: 10
                            spacing: 8

                            Text {
                                text: card.modelData.isNew ? "New" : card.modelData.name
                                color: card.chosen ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: 13
                                font.bold: true
                                font.family: Theme.fontMono
                            }

                            Text {
                                visible: !card.modelData.isNew
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.modelData.windows.length === 1 ? "1 window"
                                    : card.modelData.windows.length + " windows"
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontMono
                            }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "click to go  ·  drag a window to move it  ·  1-9  ·  esc"
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontMono
            }
        }

        // The window being dragged, under the pointer.
        Item {
            visible: overview.dragged !== null
            x: overview.dragPoint.x - width / 2
            y: overview.dragPoint.y - height / 2
            width: overview.dragSize.width
            height: overview.dragSize.height
            opacity: 0.9

            ClippingRectangle {
                anchors.fill: parent
                radius: 6
                color: Theme.surfaceContainerHigh
                border.width: 2
                border.color: AppState.themeAccent

                ScreencopyView {
                    anchors.fill: parent
                    captureSource: overview.dragged ? overview.dragged.toplevel.wayland : null
                    live: false
                }
            }
        }
    }
}
