import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

// The workspace overview (Super+Tab): every workspace side by side, each a
// small picture of its monitor -- the wallpaper, and its windows where they
// sit, drawn from a capture of each window.
//
//   click a window        go to it (its workspace comes with it)
//   click a workspace     go there; the last card, +, is a new one
//   drag a window         move it to the workspace it is dropped on
//   ×, or Delete          remove a workspace (asks first if it has windows)
//   × on a window, or     close that window
//     middle click
//   arrows / Tab, Enter   choose a workspace, go there
//   1 - 9                 go straight to that workspace
//   Esc, or Super+Tab     close
//
// Same house pattern as the launcher: mapped only while up, exclusive
// keyboard while up, pinned to the screen it opened on. The keyboard grab is
// held through the fade out when dismissed (changing it mid-fade drops the
// surface for two frames -- see AppLauncher), and let go at once when the
// overview closes to go somewhere, so the window gone to gets the keyboard.
//
// Cheap while it is not up: nothing is captured, the card list is empty and
// its views destroyed. While up, each window is captured once, when its card
// is built, not streamed.
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
    // Set while the cards come in, so they come in one after another.
    property bool opening: false

    visible: overview.shown

    Timer {
        id: unmapDelay
        interval: 200 + 60
        onTriggered: {
            overview.shown = false
            cardModel.clear()
            overview.cardData = ({})
            overview.cardList = []
        }
    }

    // The selection ring waits for the first cards to be on their way in.
    Timer {
        id: ringIn
        property bool done: false
        interval: 140
        onTriggered: done = true
    }

    Timer {
        id: openingDone
        interval: 600
        onTriggered: overview.opening = false
    }

    Connections {
        target: overview
        function onOpenChanged() {
            if (overview.open) {
                unmapDelay.stop()
                overview.leaving = false
                overview.dragged = null
                overview.confirmId = -2
                overview.pointerSteers = false
                overview.lastPointer = Qt.point(-1, -1)
                overview.opening = true
                openingDone.restart()
                ringIn.done = false
                ringIn.restart()
                cardModel.clear()
                overview.shown = true
                overview.refresh()
                overview.rebuild()
                overview.selected = Math.max(0, overview.indexOfFocused())
                // Once more when the refresh has answered: the first build
                // used what Quickshell last knew, which misses a window
                // opened since.
                eventRebuild.restart()
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

    // Quickshell fills in where windows are only on request; asked on
    // opening and again after anything moves.
    function refresh() {
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
    }

    // The cards: one per workspace, in order, and the new one at the end
    // (key -1). A snapshot, not a binding: rebuilt on opening and when
    // Hyprland says something moved -- a binding re-read every window title
    // as it changed, and re-captured every window each time.
    property var cardData: ({})
    property var cardList: []
    property int revision: 0

    ListModel { id: cardModel }

    function computeCards() {
        // The workspace on this screen's monitor: the overview opens on the
        // focused one. (Hyprland.focusedWorkspace is only known once an event
        // has named it; the monitor's is what the bar's pill reads too.)
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
            var mon = ws.monitor
            out.push({ key: ws.id, id: ws.id, name: ws.name, geom: overview.geometryOf(mon),
                       monitor: mon ? mon.name : "",
                       focused: ws.id === focusedId,
                       active: !!(mon && mon.activeWorkspace && mon.activeWorkspace.id === ws.id),
                       windows: wins, isNew: false })
        }
        out.push({ key: -1, id: maxId + 1, name: String(maxId + 1), geom: overview.geometryOf(bar.monitor),
                   monitor: "", focused: false, active: false, windows: [], isNew: true })
        return out
    }

    // What a card shows, as a string: two builds that agree on it keep the
    // first card object, so its windows are not rebuilt and re-captured.
    function signature(c) {
        return JSON.stringify([c.id, c.focused, c.active, c.monitor, c.geom, c.windows.map(function(w) {
            return [w.address, w.x, w.y, w.w, w.h, w.floating, w.fullscreen]
        })])
    }

    function rebuild() {
        if (!overview.shown) return
        var cards = overview.computeCards()
        var map = {}
        for (var i = 0; i < cards.length; i++) {
            var old = overview.cardData[cards[i].key]
            if (old && overview.signature(old) === overview.signature(cards[i])) cards[i] = old
            map[cards[i].key] = cards[i]
        }
        overview.cardData = map
        overview.cardList = cards
        // Row by row, so a card that stays keeps its view (and its capture),
        // and the ones that come and go get their transitions.
        var keys = cards.map(function(c) { return c.key })
        for (var r = cardModel.count - 1; r >= 0; r--)
            if (keys.indexOf(cardModel.get(r).key) === -1) cardModel.remove(r)
        for (var k = 0; k < keys.length; k++) {
            var at = -1
            for (var m = 0; m < cardModel.count; m++)
                if (cardModel.get(m).key === keys[k]) { at = m; break }
            if (at === -1) cardModel.insert(k, { key: keys[k] })
            else if (at !== k) cardModel.move(at, k, 1)
        }
        overview.revision++
        if (overview.selected >= cards.length) overview.selected = cards.length - 1
        if (overview.confirmId > -2 && !map[overview.confirmId]) overview.confirmId = -2
    }

    function indexOfFocused() {
        for (var i = 0; i < overview.cardList.length; i++)
            if (overview.cardList[i].focused) return i
        return 0
    }

    // Anything that moves a window or a workspace: read again, a moment
    // later, once Hyprland has settled and answered.
    Connections {
        target: Hyprland
        enabled: overview.shown
        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow": case "closewindow": case "movewindowv2":
            case "createworkspacev2": case "destroyworkspacev2": case "workspacev2":
            case "changefloatingmode": case "fullscreen": case "moveworkspacev2":
                eventRefresh.restart()
            }
        }
    }

    Timer {
        id: eventRefresh
        interval: 60
        onTriggered: {
            overview.refresh()
            eventRebuild.restart()
        }
    }

    Timer {
        id: eventRebuild
        interval: 120
        onTriggered: overview.rebuild()
    }

    // One row, as tall as fits: every card as high as the others, as wide as
    // its monitor is for that height.
    readonly property real cardHeight: {
        var aspects = 0
        for (var i = 0; i < overview.cardList.length; i++)
            aspects += overview.cardList[i].geom.w / overview.cardList[i].geom.h
        var room = overview.width * 0.9 - overview.cardSpacing * Math.max(0, overview.cardList.length - 1)
        return Math.round(Math.max(60, Math.min(overview.height * 0.3, 300, aspects > 0 ? room / aspects : 300)))
    }
    readonly property int cardSpacing: 26
    readonly property int cardRadius: 18

    property int selected: 0

    // Whether the pointer has moved since the overview opened. Only then
    // does hovering pick a card: opening under a pointer that sat still put
    // the selection on whichever card came up beneath it.
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

    function run(lua) {
        Quickshell.execDetached(["hyprctl", "eval", lua])
    }

    function goToWorkspace(id) {
        overview.leaveThen(function() { overview.run("hl.dispatch(hl.dsp.focus({ workspace = " + id + " }))") })
    }

    function goToWindow(address) {
        overview.leaveThen(function() {
            overview.run("hl.dispatch(hl.dsp.focus({ window = 'address:0x" + address + "' }))")
        })
    }

    // Moved without following it: the overview stays, and shows it arrive.
    function moveWindow(address, id) {
        overview.run("hl.dispatch(hl.dsp.window.move({ workspace = " + id
                     + ", window = 'address:0x" + address + "', follow = false }))")
    }

    function closeWindow(address) {
        overview.run("hl.dispatch(hl.dsp.window.close({ window = 'address:0x" + address + "' }))")
    }

    // ── Removing a workspace ─────────────────────────────────────────────
    //
    // Hyprland keeps a workspace for as long as it has windows or a monitor
    // shows it, and drops it the moment neither is true. So removing one is
    // closing its windows and, if it is on screen, showing that monitor
    // another of its workspaces -- without moving focus there. A monitor's
    // only workspace cannot go: a monitor always shows one.
    property int confirmId: -2          // the card asking "close N windows?"

    function fallbackFor(card) {
        var best = null
        for (var i = 0; i < overview.cardList.length; i++) {
            var c = overview.cardList[i]
            if (c.isNew || c.id === card.id || c.monitor !== card.monitor) continue
            // The nearest lower one, else the nearest higher.
            if (!best || (c.id < card.id && (best.id > card.id || c.id > best.id))
                    || (c.id > card.id && best.id > card.id && c.id < best.id)) best = c
        }
        return best
    }

    function canRemove(card) {
        return !!card && !card.isNew && (!card.active || overview.fallbackFor(card) !== null)
    }

    function removeWorkspace(card, confirmed) {
        if (!overview.canRemove(card)) return
        if (card.windows.length > 0 && !confirmed) {
            overview.confirmId = card.id
            return
        }
        overview.confirmId = -2
        for (var i = 0; i < card.windows.length; i++)
            overview.closeWindow(card.windows[i].address)
        if (card.active) {
            var other = overview.fallbackFor(card)
            overview.run("hl.get_monitor('" + card.monitor + "'):set_workspace({ workspace = " + other.id + " })")
        }
    }

    // ── Dragging a window ────────────────────────────────────────────────
    property var dragged: null          // the window's entry, while dragged
    property point dragPoint: Qt.point(0, 0)
    property size dragSize: Qt.size(0, 0)

    function cardAt(point) {
        for (var i = 0; i < cardModel.count; i++) {
            var card = cardView.itemAtIndex(i)
            if (!card) continue
            var p = card.mapFromItem(content, point.x, point.y)
            if (p.x >= 0 && p.y >= 0 && p.x <= card.width && p.y <= overview.cardHeight) return i
        }
        return -1
    }

    readonly property int dropTarget: overview.dragged ? overview.cardAt(overview.dragPoint) : -1

    // ── Drawing ──────────────────────────────────────────────────────────

    // The desktop behind, dimmed (and blurred by Hyprland's layer rule).
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: overview.open && !overview.leaving ? 1 : 0

        Behavior on opacity {
            enabled: !overview.leaving
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }

        TapHandler {
            onTapped: overview.close()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: overview.open && !overview.leaving ? 1 : 0
        scale: overview.open ? 1 : 0.97

        Behavior on opacity {
            enabled: !overview.leaving
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
        Behavior on scale {
            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
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
                var n = cardModel.count
                var card = overview.cardList[overview.selected]
                if (overview.confirmId > -2) {
                    // The "close N windows?" question has the keys.
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Delete) {
                        overview.removeWorkspace(overview.cardData[overview.confirmId], true)
                    } else if (event.key === Qt.Key_Escape) {
                        overview.confirmId = -2
                    }
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_Escape) {
                    overview.close()
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab
                           || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    overview.selected = ((overview.selected - 1) % n + n) % n
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    overview.selected = (overview.selected + 1) % n
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (card) overview.goToWorkspace(card.id)
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    overview.removeWorkspace(card, false)
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
            anchors.verticalCenterOffset: -overview.height * 0.03
            spacing: 30

            // The panels' section label.
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

            ListView {
                id: cardView
                anchors.horizontalCenter: parent.horizontalCenter
                width: contentWidth
                height: overview.cardHeight + 52
                orientation: ListView.Horizontal
                spacing: overview.cardSpacing
                interactive: false
                model: cardModel
                currentIndex: overview.selected
                // Never scrolled: the row is always as wide as its cards.
                // (Animating that width let the view scroll to keep the
                // chosen card in sight while it was narrower, and the cards
                // before it were left piled up at the left.)
                contentX: 0

                // The selection: one ring that slides from card to card, the
                // way the workspace pill's highlight does.
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 240
                highlightMoveVelocity: -1
                highlightResizeDuration: 240
                highlightResizeVelocity: -1
                highlight: Item {
                    z: 2
                    Rectangle {
                        width: parent.width + 10
                        height: overview.cardHeight + 10
                        x: -5
                        y: -5
                        radius: overview.cardRadius + 5
                        color: "transparent"
                        border.width: 2
                        border.color: AppState.themeAccent
                        // In with the cards rather than ahead of them.
                        opacity: overview.dragged || overview.opening && !ringIn.done ? 0 : 0.95

                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }

                // Coming in one after another on opening; one at a time
                // after that, as workspaces are made and removed.
                add: Transition {
                    id: addT
                    SequentialAnimation {
                        PropertyAction { property: "opacity"; value: 0 }
                        PropertyAction { property: "scale"; value: 0.9 }
                        PauseAnimation { duration: overview.opening ? addT.ViewTransition.index * 40 : 0 }
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuad }
                            NumberAnimation { property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                            NumberAnimation { property: "y"; from: 26; to: 0; duration: 380; easing.type: Easing.OutCubic }
                        }
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0; duration: 200; easing.type: Easing.OutQuad }
                        NumberAnimation { property: "scale"; to: 0.85; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 300; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; to: 1; duration: 150 }
                    NumberAnimation { property: "scale"; to: 1; duration: 150 }
                }

                delegate: Item {
                    id: card
                    required property int key
                    required property int index

                    readonly property var d: {
                        overview.revision
                        return overview.cardData[card.key] || { id: 0, name: "", geom: { x: 0, y: 0, w: 16, h: 9 },
                                                                 windows: [], isNew: true, monitor: "" }
                    }
                    readonly property var geom: card.d.geom
                    readonly property bool chosen: overview.selected === card.index
                    readonly property bool hovered: cardHover.hovered
                    readonly property bool dropping: overview.dropTarget === card.index
                                                     && !!overview.dragged
                                                     && overview.dragged.workspace !== card.d.id
                    readonly property bool confirming: overview.confirmId === card.d.id && !card.d.isNew

                    width: Math.round(overview.cardHeight * card.geom.w / card.geom.h)
                    height: cardView.height

                    // Lifts a little under the pointer or a dragged window.
                    Item {
                        id: face
                        width: parent.width
                        height: overview.cardHeight
                        y: card.hovered || card.dropping ? -4 : 0
                        scale: card.dropping ? 1.04 : card.hovered ? 1.015 : 1

                        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        // One cheap shadow (a signed-distance rectangle, not
                        // a blurred layer), deeper when lifted.
                        RectangularShadow {
                            anchors.fill: parent
                            radius: overview.cardRadius
                            blur: card.hovered || card.dropping ? 30 : 20
                            offset.y: card.hovered || card.dropping ? 10 : 6
                            color: Qt.rgba(0, 0, 0, 0.45)

                            Behavior on blur { NumberAnimation { duration: 200 } }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: overview.cardRadius
                            color: Theme.glass
                        }

                        ClippingRectangle {
                            id: screenArea
                            anchors.fill: parent
                            anchors.margins: 4
                            radius: overview.cardRadius - 4
                            color: "transparent"

                            // The desktop the windows sit on.
                            Image {
                                anchors.fill: parent
                                visible: !card.d.isNew
                                source: AppState.wallpaperStill.length > 0 ? "file://" + AppState.wallpaperStill : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize.width: 512
                                opacity: card.d.focused ? 0.85 : 0.6

                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }

                            // A new workspace: a plus where the windows would be.
                            Column {
                                anchors.centerIn: parent
                                visible: card.d.isNew
                                spacing: 6
                                opacity: card.hovered || card.chosen || card.dropping ? 1 : 0.55

                                Behavior on opacity { NumberAnimation { duration: 180 } }

                                IconGlyph {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "\u{F0415}"
                                    color: Theme.textSecondary
                                    size: 26
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: overview.dragged ? "Drop here" : "New"
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.family: Theme.fontMono
                                }
                            }

                            Repeater {
                                model: card.d.windows

                                delegate: Item {
                                    id: win
                                    required property var modelData

                                    readonly property real sx: screenArea.width / card.geom.w
                                    readonly property real sy: screenArea.height / card.geom.h
                                    readonly property bool whole: win.modelData.fullscreen
                                    readonly property bool held: !!overview.dragged
                                                                 && overview.dragged.address === win.modelData.address

                                    x: whole ? 0 : Math.round((win.modelData.x - card.geom.x) * sx)
                                    y: whole ? 0 : Math.round((win.modelData.y - card.geom.y) * sy)
                                    width: whole ? parent.width : Math.max(14, Math.round(win.modelData.w * sx))
                                    height: whole ? parent.height : Math.max(10, Math.round(win.modelData.h * sy))
                                    // Fades in when its capture has arrived,
                                    // rather than popping in over a blank.
                                    opacity: win.held ? 0.25 : shot.hasContent ? 1 : 0
                                    scale: winHover.hovered && !overview.dragged ? 1.03 : 1

                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                    ClippingRectangle {
                                        anchors.fill: parent
                                        radius: 7
                                        color: Theme.surfaceContainerHigh

                                        ScreencopyView {
                                            id: shot
                                            anchors.fill: parent
                                            captureSource: overview.shown ? win.modelData.toplevel.wayland : null
                                            live: false
                                        }
                                    }

                                    // Its app, over the middle.
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Qt.rgba(0, 0, 0, 0.45)
                                        visible: win.width > 48 && win.height > 40

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
                                        radius: 7
                                        color: "transparent"
                                        border.width: winHover.hovered ? 2 : 1
                                        border.color: winHover.hovered ? AppState.themeAccent : Qt.rgba(1, 1, 1, 0.1)

                                        Behavior on border.color { ColorAnimation { duration: 140 } }
                                    }

                                    // Close this window.
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 4
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: winClose.hovered ? Theme.error : Qt.rgba(0, 0, 0, 0.55)
                                        visible: win.width > 60 && win.height > 40
                                        opacity: winHover.hovered && !overview.dragged ? 1 : 0

                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        IconGlyph {
                                            anchors.centerIn: parent
                                            text: "\u{F0156}"
                                            color: "#ffffff"
                                            size: 9
                                        }

                                        HoverHandler { id: winClose }
                                        TapHandler {
                                            enabled: parent.opacity > 0.5
                                            onTapped: overview.closeWindow(win.modelData.address)
                                        }
                                    }

                                    HoverHandler {
                                        id: winHover
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    TapHandler {
                                        onTapped: overview.goToWindow(win.modelData.address)
                                    }

                                    TapHandler {
                                        acceptedButtons: Qt.MiddleButton
                                        onTapped: overview.closeWindow(win.modelData.address)
                                    }

                                    DragHandler {
                                        target: null
                                        onActiveChanged: {
                                            if (active) {
                                                overview.dragSize = Qt.size(win.width, win.height)
                                                overview.dragged = Object.assign({}, win.modelData,
                                                                                 { workspace: card.d.id })
                                            } else if (overview.dragged) {
                                                var to = overview.dropTarget
                                                var w = overview.dragged
                                                overview.dragged = null
                                                var target = overview.cardList[to]
                                                if (target && target.id !== w.workspace)
                                                    overview.moveWindow(w.address, target.id)
                                            }
                                        }
                                        onCentroidChanged: {
                                            if (active)
                                                overview.dragPoint = win.mapToItem(content, centroid.position.x,
                                                                                   centroid.position.y)
                                        }
                                    }
                                }
                            }

                            // "Close N windows?" -- the one question asked
                            // before a workspace goes.
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(0, 0, 0, 0.62)
                                opacity: card.confirming ? 1 : 0
                                visible: opacity > 0

                                Behavior on opacity { NumberAnimation { duration: 160 } }

                                // Swallows clicks, so a click on the dim is
                                // not a click on the workspace under it.
                                TapHandler { onTapped: overview.confirmId = -2 }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 12

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: card.d.windows.length === 1 ? "Close its window?"
                                            : "Close its " + card.d.windows.length + " windows?"
                                        color: Theme.textPrimary
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.family: Theme.fontMono
                                    }

                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 8

                                        Repeater {
                                            model: [{ label: "Remove", danger: true }, { label: "Keep", danger: false }]

                                            delegate: Rectangle {
                                                id: btn
                                                required property var modelData
                                                width: btnText.implicitWidth + 26
                                                height: 28
                                                radius: 14
                                                color: btn.modelData.danger ? Theme.alpha(Theme.error, btnHover.hovered ? 0.9 : 0.7)
                                                                            : Theme.alpha(Theme.foreground, btnHover.hovered ? 0.2 : 0.12)

                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                Text {
                                                    id: btnText
                                                    anchors.centerIn: parent
                                                    text: btn.modelData.label
                                                    color: "#ffffff"
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    font.family: Theme.fontMono
                                                }

                                                HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: {
                                                        if (btn.modelData.danger) overview.removeWorkspace(card.d, true)
                                                        else overview.confirmId = -2
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Remove the workspace.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -8
                            anchors.rightMargin: -8
                            width: 24
                            height: 24
                            radius: 12
                            color: removeHover.hovered ? Theme.error : Theme.glass
                            border.width: 1
                            border.color: Theme.outline
                            visible: overview.canRemove(card.d)
                            opacity: (card.hovered || card.chosen) && !card.confirming && !overview.dragged ? 1 : 0
                            scale: opacity > 0.5 ? 1 : 0.6

                            Behavior on opacity { NumberAnimation { duration: 160 } }
                            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 120 } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: "\u{F0156}"
                                color: Theme.textPrimary
                                size: 11
                            }

                            HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                enabled: parent.opacity > 0.5
                                onTapped: overview.removeWorkspace(card.d, false)
                            }
                        }

                        HoverHandler {
                            id: cardHover
                            onHoveredChanged: if (hovered && overview.pointerSteers) overview.selected = card.index
                        }

                        TapHandler {
                            onTapped: overview.goToWorkspace(card.d.id)
                        }
                    }

                    // The number in a chip, a dot for the one you are on.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: face.bottom
                        anchors.topMargin: 14
                        spacing: 8

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(24, num.implicitWidth + 16)
                            height: 22
                            radius: 11
                            color: card.chosen ? AppState.themeAccent : Theme.alpha(Theme.foreground, 0.1)

                            Behavior on color { ColorAnimation { duration: 180 } }

                            Text {
                                id: num
                                anchors.centerIn: parent
                                text: card.d.isNew ? "+" : card.d.name
                                color: card.chosen ? Theme.accentText : Theme.textPrimary
                                font.pixelSize: 12
                                font.bold: true
                                font.family: Theme.fontMono

                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: AppState.themeAccent
                            visible: !!card.d.focused
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !card.d.isNew
                            text: card.d.windows.length === 0 ? "empty"
                                : card.d.windows.length === 1 ? "1 window"
                                : card.d.windows.length + " windows"
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontMono
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "click to go  ·  drag a window to move it  ·  del removes  ·  1-9  ·  esc"
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontMono
            }
        }

        // The window being dragged, under the pointer.
        Item {
            id: ghost
            visible: overview.dragged !== null
            x: overview.dragPoint.x - width / 2
            y: overview.dragPoint.y - height / 2
            width: overview.dragSize.width
            height: overview.dragSize.height
            scale: visible ? 1.06 : 0.9

            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

            RectangularShadow {
                anchors.fill: parent
                radius: 7
                blur: 24
                offset.y: 8
                color: Qt.rgba(0, 0, 0, 0.5)
            }

            ClippingRectangle {
                anchors.fill: parent
                radius: 7
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
