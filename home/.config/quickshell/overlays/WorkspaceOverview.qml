import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import qs.components
import qs.config
import qs.services

// The workspace overview (Super+Tab): every workspace side by side, each a
// small picture of its monitor -- the wallpaper, and its windows where they
// sit, drawn from a capture of each window. Grouped by monitor, each with its
// own block of ten numbered 1-10, the way Super+N counts them (hyprland.lua:
// DP-2 has 1-10, HDMI-A-1 11-20; 13 shows as 3).
//
//   click a workspace     go there; each monitor's last card, +, is a new one there
//   ×, or Delete          remove a workspace (asks first if it has windows)
//   arrows / Tab, Enter   choose a workspace, go there
//   N                     a new workspace on this monitor
//   1 - 9                 go straight to that workspace of this monitor
//   Esc, or Super+Tab     close
//
// Workspaces only: the windows in a card are a picture of what is there,
// not things to click, close or drag -- a click anywhere on a card goes to
// that workspace.
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
//
// The clickable things on a card are MouseAreas, not TapHandlers: a
// TapHandler's grab is passive, so a click on a card's × was also a click on
// the card under it, which went to that workspace and closed the overview
// before the × could do anything. A MouseArea keeps the click it takes.
PanelWindow {
    id: overview

    property var bar: null
    screen: bar.screen

    // A key and what it does -- the launcher's footer, the same keycaps.
    component KeyHint: Row {
        id: hint
        property string key: ""
        property string label: ""
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(20, keyText.implicitWidth + 12)
            height: 20
            radius: Theme.radiusSmall
            color: Theme.surface
            border.width: 1
            border.color: Theme.outline

            Text {
                id: keyText
                anchors.centerIn: parent
                text: hint.key
                color: Theme.textSecondary
                font.pixelSize: 10
                font.family: Theme.fontMono
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.label
            color: Theme.textMuted
            font.pixelSize: 10
            font.family: Theme.fontText
        }
    }

    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (Panels.overviewScreen === "") return bar.monitor.focused
        return bar.monitor.name === Panels.overviewScreen
    }

    readonly property bool open: Panels.overviewOpen && overview.onOpeningScreen

    // Mapped from opening until the fade out has played (see AppLauncher's
    // `shown` for why this is not `open || timer.running`).
    property bool shown: false
    // Closing to go somewhere: hidden at once, keyboard let go at once.
    property bool leaving: false
    // Set while the cards come in, so they come in one after another and
    // the row does not animate its sizes while it fills.
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
            overview.goingKeys = []
        }
    }

    Timer {
        id: openingDone
        interval: 650
        onTriggered: overview.opening = false
    }

    Connections {
        target: overview
        function onOpenChanged() {
            if (overview.open) {
                unmapDelay.stop()
                overview.leaving = false
                overview.confirmId = -2
                overview.goingKeys = []
                overview.pointerSteers = false
                overview.lastPointer = Qt.point(-1, -1)
                overview.opening = true
                openingDone.restart()
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

    // The cards: one per workspace, in order, and a new one at the end of
    // each monitor's run (key -100 - its block). A snapshot, not a binding: rebuilt on opening and when
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
        // Grouped by monitor, left to right as they stand, and by number
        // within each: a workspace lives on one monitor, and the row says so.
        var monX = function(w) { var g = overview.geometryOf(w.monitor); return g.x }
        wss.sort(function(a, b) {
            var dx = monX(a) - monX(b)
            return dx !== 0 ? dx : a.id - b.id
        })
        var tops = Hyprland.toplevels.values
        var out = []
        for (var i = 0; i < wss.length; i++) {
            var ws = wss[i]
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
            // The apps in it, each once, most recently used first.
            var apps = []
            var byRecency = wins.slice().sort(function(a, b) { return a.recency - b.recency })
            for (var a = 0; a < byRecency.length; a++)
                if (apps.indexOf(byRecency[a].cls) === -1) apps.push(byRecency[a].cls)
            out.push({ key: ws.id, id: ws.id, name: String(overview.slotOf(ws.id)), geom: overview.geometryOf(mon),
                       monitor: mon ? mon.name : "", monitorLabel: overview.monitorLabel(mon), apps: apps,
                       focused: ws.id === focusedId,
                       active: !!(mon && mon.activeWorkspace && mon.activeWorkspace.id === ws.id),
                       windows: wins, isNew: false })
        }
        // Each monitor's run ends in a new card of its own: the number after
        // its highest, or its lowest free one once 10 is taken; none when
        // all ten are in use.
        var cards = []
        for (var j = 0; j < out.length; j++) {
            cards.push(out[j])
            if (j + 1 < out.length && out[j + 1].monitor === out[j].monitor) continue
            var base = Math.floor((out[j].id - 1) / 10) * 10
            var used = {}
            for (var u = j; u >= 0 && out[u].monitor === out[j].monitor; u--) used[out[u].id] = true
            var next = overview.slotOf(out[j].id) < 10 ? out[j].id + 1 : -1
            for (var s = 1; next < 0 && s <= 10; s++) if (!used[base + s]) next = base + s
            if (next < 0) continue
            cards.push({ key: -100 - base / 10, id: next, name: String(overview.slotOf(next)), geom: out[j].geom,
                         monitor: out[j].monitor, monitorLabel: "", apps: [], focused: false, active: false,
                         windows: [], isNew: true })
        }
        // Where each monitor's run of cards starts and ends: the first gets
        // the monitor's name over it, the last a wider gap after it; the
        // very last none.
        var monitors = {}
        for (var m = 0; m < cards.length; m++) monitors[cards[m].monitor] = true
        var several = Object.keys(monitors).length > 1
        for (var k = 0; k < cards.length; k++) {
            cards[k].groupStart = several && !cards[k].isNew && (k === 0 || cards[k - 1].monitor !== cards[k].monitor)
            cards[k].groupEnd = k + 1 < cards.length && cards[k + 1].monitor !== cards[k].monitor
            cards[k].last = k + 1 === cards.length
        }
        return cards
    }

    // A workspace's number within its monitor's block of ten: 13 is 3.
    function slotOf(id) {
        return (id - 1) % 10 + 1
    }

    // The id before a monitor's first workspace (0 or 10), off the one it shows.
    function blockOf(monitor) {
        var id = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
        return id > 0 ? Math.floor((id - 1) / 10) * 10 : 0
    }

    // This monitor's new card, if its block has room.
    function newCardFor(monitor) {
        var name = monitor ? monitor.name : ""
        for (var i = 0; i < overview.cardList.length; i++)
            if (overview.cardList[i].isNew && overview.cardList[i].monitor === name) return overview.cardList[i]
        return null
    }

    // "Samsung Odyssey G40B" for "Samsung Electric Company Odyssey G40B".
    function monitorLabel(monitor) {
        var o = monitor ? monitor.lastIpcObject : null
        var d = o && o.description ? o.description : (monitor ? monitor.name : "")
        return d.replace(/ (Electric Company|Corporation|Technologies|Technology|Inc\.?|Co\.?,? ?Ltd\.?)/g, "")
    }

    // What a card shows, as a string: two builds that agree on it keep the
    // first card object, so its windows are not rebuilt and re-captured.
    function signature(c) {
        return JSON.stringify([c.id, c.focused, c.active, c.monitor, c.geom, c.groupStart, c.groupEnd, c.last, c.windows.map(function(w) {
            return [w.address, w.x, w.y, w.w, w.h, w.floating, w.fullscreen]
        })])
    }

    // Cards on their way out: they shrink and fade in place, and only then
    // leave the row, which closes up behind them.
    property var goingKeys: []

    function rebuild() {
        if (!overview.shown) return
        var cards = overview.computeCards()
        var map = {}
        for (var i = 0; i < cards.length; i++) {
            var old = overview.cardData[cards[i].key]
            if (old && overview.signature(old) === overview.signature(cards[i])) cards[i] = old
            map[cards[i].key] = cards[i]
        }
        var keys = cards.map(function(c) { return c.key })
        // A card that is going stays in the data until it has gone.
        var going = []
        for (var r = 0; r < cardModel.count; r++) {
            var k0 = cardModel.get(r).key
            if (keys.indexOf(k0) === -1) {
                going.push(k0)
                if (overview.cardData[k0]) map[k0] = overview.cardData[k0]
            }
        }
        overview.cardData = map
        overview.cardList = cards
        overview.goingKeys = going
        // The rest row by row, so a card that stays keeps its view (and its
        // capture); new ones go in where they belong among those staying.
        var staying = []
        for (var s = 0; s < cardModel.count; s++) {
            var ks = cardModel.get(s).key
            if (going.indexOf(ks) === -1) staying.push(ks)
        }
        for (var k = 0; k < keys.length; k++) {
            if (staying.indexOf(keys[k]) !== -1) continue
            // Before the first staying card that comes after it.
            var at = cardModel.count
            for (var m = 0; m < cardModel.count; m++) {
                var km = cardModel.get(m).key
                if (going.indexOf(km) !== -1) continue
                if (keys.indexOf(km) > k) { at = m; break }
            }
            cardModel.insert(at, { key: keys[k] })
        }
        if (going.length > 0) goneTimer.restart()
        overview.revision++
        if (overview.selected >= cards.length) overview.selected = cards.length - 1
        if (overview.confirmId > -2 && !map[overview.confirmId]) overview.confirmId = -2
    }

    Timer {
        id: goneTimer
        interval: 300
        onTriggered: {
            for (var r = cardModel.count - 1; r >= 0; r--)
                if (overview.goingKeys.indexOf(cardModel.get(r).key) !== -1) cardModel.remove(r)
            overview.goingKeys = []
        }
    }

    // The card at a row position, as the keyboard and the pointer count
    // them: the ones on their way out are skipped.
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
        var gaps = 0
        for (var g = 0; g + 1 < overview.cardList.length; g++)
            gaps += overview.cardList[g].groupEnd ? overview.groupSpacing : overview.cardSpacing
        var room = overview.width * 0.9 - gaps
        return Math.round(Math.max(60, Math.min(overview.height * 0.3, 300, aspects > 0 ? room / aspects : 300)))
    }
    // Eased when a card comes or goes, so the row grows and shrinks rather
    // than snapping; not while the row first fills.
    property real shownHeight: overview.cardHeight
    Behavior on shownHeight {
        enabled: !overview.opening
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    readonly property int cardSpacing: 26
    // Between one monitor's workspaces and the next's.
    readonly property int groupSpacing: 64
    readonly property int cardRadius: 18

    property int selected: 0

    // Whether the pointer has moved since the overview opened. Only then
    // does hovering pick a card: opening under a pointer that sat still put
    // the selection on whichever card came up beneath it.
    property bool pointerSteers: false
    property point lastPointer: Qt.point(-1, -1)

    // ── Acting ───────────────────────────────────────────────────────────

    function close() {
        Panels.overviewOpen = false
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
        // The selection stays near: on the card before the one going.
        var cur = overview.cardList[overview.selected]
        if (cur && cur.key === card.key) overview.selected = Math.max(0, overview.selected - 1)
        for (var i = 0; i < card.windows.length; i++)
            overview.closeWindow(card.windows[i].address)
        if (card.active) {
            var other = overview.fallbackFor(card)
            overview.run("hl.get_monitor('" + card.monitor + "'):set_workspace({ workspace = " + other.id + " })")
        }
    }

    // ── Drawing ──────────────────────────────────────────────────────────

    // The desktop behind, almost hidden. Not blurred -- the compositor blur
    // stays on the bar's glass -- and with no card of its own under the
    // labels and key hints, the other overlays' 0.6 scrim let a terminal's
    // text show through and cross them. The wallpaper picker's 0.88 does not.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.background, 0.88)
        opacity: overview.open && !overview.leaving ? 1 : 0

        Behavior on opacity {
            enabled: !overview.leaving
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (overview.confirmId > -2) overview.confirmId = -2
                else overview.close()
            }
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
                var n = overview.cardList.length
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
                } else if (event.key === Qt.Key_N) {
                    var fresh = overview.newCardFor(bar.monitor)
                    if (fresh) overview.goToWorkspace(fresh.id)
                } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    overview.goToWorkspace(overview.blockOf(bar.monitor) + event.key - Qt.Key_0)
                } else {
                    return
                }
                event.accepted = true
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -overview.height * 0.03
            spacing: 44

            // The panels' section label.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Workspaces"
                color: Theme.textSecondary
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.family: Theme.fontText
            }

            // A plain row: it always knows where its cards are. (A ListView
            // here, with its transitions and a sliding highlight, lost track
            // when the cards changed width as one came or went -- cards
            // piled up on each other and the ring drifted off them.)
            Row {
                id: cardRow
                anchors.horizontalCenter: parent.horizontalCenter
                height: overview.shownHeight + 52

                Repeater {
                    id: cardRepeater
                    model: cardModel

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
                        readonly property bool going: overview.goingKeys.indexOf(card.key) !== -1
                        // Its place among the cards the keyboard walks.
                        readonly property int place: {
                            overview.revision
                            for (var i = 0; i < overview.cardList.length; i++)
                                if (overview.cardList[i].key === card.key) return i
                            return -1
                        }
                        readonly property bool chosen: !card.going && overview.selected === card.place
                        readonly property bool hovered: cardHover.hovered
                        readonly property bool confirming: overview.confirmId === card.d.id && !card.d.isNew

                        // Each card carries the gap after it (the last,
                        // "New", has none), and hands over its whole width as
                        // it goes -- or takes it as it comes -- so the row
                        // closes up and opens out smoothly while the others
                        // resize, instead of jumping once it is gone.
                        readonly property real faceWidth: Math.round(overview.shownHeight * card.geom.w / card.geom.h)
                        property real grow: 1
                        width: Math.round((card.faceWidth + (card.d.last ? 0
                                           : card.d.groupEnd ? overview.groupSpacing : overview.cardSpacing)) * card.grow)
                        height: overview.shownHeight + 52

                        // Comes in one after another on opening, rises into
                        // place; goes by shrinking where it is.
                        opacity: 0
                        scale: 0.9
                        property real rise: 26

                        // Set once, not bound: a card that arrives after the
                        // row has filled grows in from nothing.
                        Component.onCompleted: {
                            entrance.start()
                            if (!overview.opening) {
                                card.grow = 0
                                growIn.start()
                            }
                        }

                        NumberAnimation {
                            id: growIn
                            target: card; property: "grow"; to: 1
                            duration: 300; easing.type: Easing.OutCubic
                        }

                        SequentialAnimation {
                            id: entrance
                            PauseAnimation { duration: overview.opening ? Math.max(0, card.index) * 40 : 0 }
                            ParallelAnimation {
                                NumberAnimation { target: card; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuad }
                                NumberAnimation { target: card; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                                NumberAnimation { target: card; property: "rise"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                            }
                        }

                        onGoingChanged: if (going) { entrance.stop(); exit.start() }

                        ParallelAnimation {
                            id: exit
                            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 180; easing.type: Easing.OutQuad }
                            NumberAnimation { target: card; property: "scale"; to: 0.85; duration: 220; easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "grow"; to: 0; duration: 280; easing.type: Easing.OutCubic }
                        }

                        transform: Translate { y: card.rise }

                        // The monitor's name, over its first workspace.
                        Row {
                            visible: !!card.d.groupStart
                            x: 4
                            y: -30
                            spacing: 7

                            IconGlyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{F0379}"
                                color: Theme.textMuted
                                size: Theme.iconTiny
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.d.monitorLabel || ""
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.family: Theme.fontText
                            }
                        }

                        // Lifts a little under the pointer.
                        Item {
                            id: face
                            width: card.faceWidth
                            height: overview.shownHeight
                            y: card.hovered ? -4 : 0
                            scale: card.hovered ? 1.015 : 1

                            Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            // One cheap shadow (a signed-distance rectangle,
                            // not a blurred layer), deeper when lifted.
                            // The chosen card glows in the accent, softly,
                            // under the ring.
                            RectangularShadow {
                                anchors.fill: parent
                                radius: overview.cardRadius
                                blur: 34
                                spread: 2
                                color: Theme.alpha(Theme.accent, 0.4)
                                opacity: card.chosen ? 1 : 0

                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                            }

                            RectangularShadow {
                                anchors.fill: parent
                                radius: overview.cardRadius
                                blur: card.hovered ? 30 : 20
                                offset.y: card.hovered ? 10 : 6
                                color: Theme.alpha(Theme.shadow, 0.45)

                                Behavior on blur { NumberAnimation { duration: 200 } }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: overview.cardRadius
                                color: card.d.isNew ? Theme.alpha(Theme.background, card.hovered ? 0.5 : 0.3) : Theme.surface

                                Behavior on color { ColorAnimation { duration: 180 } }
                            }

                            // The new card's outline, dashed: a place for a
                            // workspace, not one yet.
                            Canvas {
                                anchors.fill: parent
                                visible: card.d.isNew
                                opacity: card.hovered || card.chosen ? 0.9 : 0.45
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var r = overview.cardRadius - 1, w = width - 2, h = height - 2
                                    ctx.strokeStyle = Theme.textSecondary
                                    ctx.lineWidth = 1.5
                                    ctx.setLineDash([6, 6])
                                    ctx.beginPath()
                                    ctx.moveTo(1 + r, 1)
                                    ctx.arcTo(1 + w, 1, 1 + w, 1 + h, r)
                                    ctx.arcTo(1 + w, 1 + h, 1, 1 + h, r)
                                    ctx.arcTo(1, 1 + h, 1, 1, r)
                                    ctx.arcTo(1, 1, 1 + w, 1, r)
                                    ctx.closePath()
                                    ctx.stroke()
                                }

                                Behavior on opacity { NumberAnimation { duration: 180 } }
                            }

                            // A click anywhere on the card that nothing on it
                            // takes: go to that workspace. First, so every
                            // button and window above it gets its click first.
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (card.confirming) overview.confirmId = -2
                                    else overview.goToWorkspace(card.d.id)
                                }
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
                                    source: Wallpaper.wallpaperStill.length > 0 ? "file://" + Wallpaper.wallpaperStill : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 512
                                    opacity: card.d.focused ? 0.85 : 0.6

                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }

                                // Nothing on it.
                                Text {
                                    anchors.centerIn: parent
                                    visible: !card.d.isNew && card.d.windows.length === 0
                                    text: "Empty"
                                    color: Theme.textSecondary
                                    font.pixelSize: 12
                                    font.family: Theme.fontText
                                    style: Text.Raised
                                    styleColor: Theme.alpha(Theme.shadow, 0.4)
                                }

                                // A new workspace: a plus where the windows would be.
                                Column {
                                    anchors.centerIn: parent
                                    visible: card.d.isNew
                                    spacing: 6
                                    opacity: card.hovered || card.chosen ? 1 : 0.55

                                    Behavior on opacity { NumberAnimation { duration: 180 } }

                                    IconGlyph {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "\u{F0415}"
                                        color: Theme.textSecondary
                                        size: 26
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "New"
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        font.family: Theme.fontText
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

                                        // Clamped to the card: a window partly
                                        // off its monitor stays inside the picture.
                                        x: whole ? 0 : Math.max(0, Math.min(parent.width - width,
                                                                             Math.round((win.modelData.x - card.geom.x) * sx)))
                                        y: whole ? 0 : Math.max(0, Math.min(parent.height - height,
                                                                             Math.round((win.modelData.y - card.geom.y) * sy)))
                                        width: whole ? parent.width : Math.min(parent.width, Math.max(14, Math.round(win.modelData.w * sx)))
                                        height: whole ? parent.height : Math.min(parent.height, Math.max(10, Math.round(win.modelData.h * sy)))
                                        // Fades in when its capture has arrived,
                                        // rather than popping in over a blank.
                                        opacity: shot.hasContent ? 1 : 0

                                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

                                        ClippingRectangle {
                                            anchors.fill: parent
                                            radius: Theme.radiusSmall
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
                                            radius: height / 2
                                            color: Theme.alpha(Theme.shadow, 0.45)
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
                                            radius: Theme.radiusSmall
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Theme.alpha(Theme.knob, 0.1)
                                        }

                                    }
                                }

                                // "Close N windows?" -- the one question asked
                                // before a workspace goes.
                                Rectangle {
                                    anchors.fill: parent
                                    color: Theme.alpha(Theme.shadow, 0.62)
                                    opacity: card.confirming ? 1 : 0
                                    visible: opacity > 0

                                    Behavior on opacity { NumberAnimation { duration: 160 } }

                                    // Takes the clicks on the dim: a click
                                    // there says no, not "go to this workspace".
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: overview.confirmId = -2
                                    }

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
                                            font.family: Theme.fontText
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
                                                    radius: height / 2
                                                    color: btn.modelData.danger
                                                           ? Theme.alpha(Theme.error, btnArea.containsMouse ? 0.9 : 0.7)
                                                           : Theme.alpha(Theme.foreground, btnArea.containsMouse ? 0.2 : 0.12)

                                                    Behavior on color { ColorAnimation { duration: 120 } }

                                                    Text {
                                                        id: btnText
                                                        anchors.centerIn: parent
                                                        text: btn.modelData.label
                                                        color: Theme.knob
                                                        font.pixelSize: 11
                                                        font.bold: true
                                                        font.family: Theme.fontText
                                                    }

                                                    MouseArea {
                                                        id: btnArea
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
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

                            // Where the keyboard is: a ring on the card
                            // itself, so it lifts and resizes with it.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -5
                                radius: overview.cardRadius + 5
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.accent
                                opacity: card.chosen ? 0.95 : 0
                                scale: opacity > 0 ? 1 : 0.97

                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }

                            // Remove the workspace. Last, so it is on top of
                            // everything the card holds and takes its click.
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -8
                                anchors.rightMargin: -8
                                width: 24
                                height: 24
                                radius: height / 2
                                color: removeArea.containsMouse ? Theme.error : Theme.surface
                                border.width: 1
                                border.color: Theme.outline
                                visible: overview.canRemove(card.d)
                                opacity: (card.hovered || card.chosen) && !card.confirming ? 1 : 0
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

                                MouseArea {
                                    id: removeArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    enabled: parent.opacity > 0.5
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: overview.removeWorkspace(card.d, false)
                                }
                            }

                            HoverHandler {
                                id: cardHover
                                onHoveredChanged: if (hovered && overview.pointerSteers && card.place >= 0)
                                                      overview.selected = card.place
                            }
                        }

                        // The number in a chip, a dot for the one you are on.
                        Row {
                            anchors.horizontalCenter: face.horizontalCenter
                            anchors.top: face.bottom
                            anchors.topMargin: 14
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(24, num.implicitWidth + 16)
                                height: 22
                                radius: height / 2
                                color: card.chosen ? Theme.accent : Theme.alpha(Theme.foreground, 0.1)

                                Behavior on color { ColorAnimation { duration: 180 } }

                                Text {
                                    id: num
                                    anchors.centerIn: parent
                                    text: card.d.isNew ? "+" : card.d.name
                                    color: card.chosen ? Theme.accentText : Theme.textPrimary
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: Theme.fontText

                                    Behavior on color { ColorAnimation { duration: 180 } }
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: Theme.accent
                                visible: !!card.d.focused
                            }

                            // Its apps, up to four, then how many more.
                            Repeater {
                                model: (card.d.apps || []).slice(0, 4)

                                delegate: IconImage {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitSize: 16
                                    mipmap: true
                                    source: {
                                        var e = DesktopEntries.heuristicLookup(modelData)
                                        return Quickshell.iconPath(e ? e.icon : String(modelData).toLowerCase(),
                                                                   "application-x-executable")
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: (card.d.apps || []).length > 4
                                text: "+" + ((card.d.apps || []).length - 4)
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontText
                            }
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18

                KeyHint { key: "\u2190\u2192"; label: "Choose" }
                KeyHint { key: "\u21B5"; label: "Go" }
                KeyHint { key: "del"; label: "Close" }
                KeyHint { key: "n"; label: "New" }
                KeyHint { key: "1-9"; label: "Jump" }
                KeyHint { key: "esc"; label: "Back" }
            }
        }
    }
}
