import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import qs.components
import qs.config
import qs.services

// The workspace overview (Super+Tab), on every screen at once: the shown workspace's windows spread
// out side by side, under a strip of every workspace grouped by monitor (DP-2 1-10, HDMI-A-1 11-20;
// 13 shows as 3). Closing sends every window back to its place.
//
// click a window              go to it
// drag onto a strip card      move it there and close; onto New, make a workspace and go there
// drag onto another screen    the same, into the workspace that screen shows or one in its strip
// click a card                go there; its × removes it (asks first when it has windows)
// arrows / Tab, Enter         choose a window, go to it (keys act on the screen under the pointer)
// Ctrl + ← →                  show the previous or next workspace here, without closing
// 1 - 9, 0                    go to that workspace of this monitor
// Shift + 1 - 9, 0 / N        move the chosen window there (N: to a new one) and close
// N                           a new workspace on this monitor
// Delete                      remove the workspace on screen
// Esc, Super+Tab              close
//
// Exclusive keyboard on every screen: with it on one alone, the others got no pointer (Hyprland
// 0.57). A window dragged off its screen keeps the pointer (implicit grab); the screen under it
// draws a copy. Cheap while closed: nothing is captured and the models are empty. MouseAreas, not
// TapHandlers: a passive TapHandler grab let a click on × also open the workspace.
PanelWindow {
    id: overview

    property var bar: null
    screen: bar.screen

    // The screen it was opened on, where the selection starts.
    readonly property bool home: {
        if (!bar.monitor) return true
        if (Panels.overviewScreen === "") return bar.monitor.focused
        return bar.monitor.name === Panels.overviewScreen
    }

    readonly property string screenName: bar.monitor ? bar.monitor.name : ""

    readonly property bool open: Panels.overviewOpen

    // Mapped from opening until the windows are home (a `shown` flag, see AppLauncher).
    property bool shown: false
    // Closing to go to a workspace: hidden and keyboard released at once, on every screen.
    readonly property bool leaving: Panels.overviewLeaving
    // While opening: windows leave from their screen places and the
    // strip doesn't animate its sizes.
    property bool opening: false
    // Windows are out of their places from opening until closing starts.
    readonly property bool spread: overview.open && !overview.leaving

    visible: overview.shown

    Timer {
        id: unmapDelay
        interval: Theme.durLong + 60
        onTriggered: {
            overview.shown = false
            overview.veil = 0
            cardModel.clear()
            tileModel.clear()
            overview.cardData = ({})
            overview.cardList = []
            overview.goingCards = []
            overview.tileData = ({})
            overview.tileList = []
            overview.goingTiles = []
            overview.slots = ({})
            overview.arrivals = ({})
            overview.selectedKey = ""
            // Focus the picked window now that the keyboard is free.
            if (overview.pending) actTimer.restart()
        }
    }

    Timer {
        id: openingDone
        interval: Theme.durSpring + Theme.durMedium
        onTriggered: overview.opening = false
    }

    Connections {
        target: overview
        function onOpenChanged() {
            if (overview.open) {
                unmapDelay.stop()
                closeAfterMove.stop()
                overview.followAddress = ""
                overview.chosenKey = ""
                overview.pending = null
                overview.confirmId = -2
                overview.dropKey = overview.noCard
                overview.draggingKey = ""
                overview.pointerSteers = false
                overview.lastPointer = Qt.point(-1, -1)
                overview.opening = true
                openingDone.restart()
                overview.shown = true
                overview.refresh()
                overview.rebuild()
                overview.selectedKey = overview.firstKey()
                // Again once the refresh answers: the first build may miss a window opened since.
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

    // Hyprland's corner rounding, so windows leave and land with their on-screen corners.
    readonly property int windowRounding: Panels.overviewRounding >= 0 ? Panels.overviewRounding : Theme.radiusXLarge

    // What is where

    // A monitor's box in the layout, in logical pixels.
    function geometryOf(monitor) {
        var o = monitor ? monitor.lastIpcObject : null
        if (!o || !o.width) return { x: 0, y: 0, w: 1920, h: 1080 }
        var s = o.scale || 1
        var rotated = o.transform % 2 === 1
        return { x: o.x, y: o.y, w: (rotated ? o.height : o.width) / s, h: (rotated ? o.width : o.height) / s }
    }

    // Quickshell fills in window positions only on request. Asked by the home
    // screen only: the answers are shared.
    function refresh() {
        if (!overview.home) return
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        Hyprland.refreshMonitors()
    }

    // The workspace this screen shows, read from the monitor: Hyprland.focusedWorkspace
    // is unknown until an event names it.
    function viewedId() {
        return bar.monitor && bar.monitor.activeWorkspace ? bar.monitor.activeWorkspace.id : -1
    }

    // Snapshots, not bindings, rebuilt on open and on Hyprland events: a binding re-read every
    // title and re-captured every window. Cards are keyed by workspace id (a monitor's new card by
    // -100 - block), tiles by address; leaving keys stay until goneTimer.
    property var cardData: ({})
    property var cardList: []
    property var goingCards: []
    property var tileData: ({})
    property var tileList: []
    property var goingTiles: []
    // Where each tile sits while spread out, by address.
    property var slots: ({})
    // Windows dropped here from another screen, by address: where they were let
    // go, for their tiles to start from.
    property var arrivals: ({})
    property int revision: 0
    property bool several: false

    ListModel { id: cardModel }
    ListModel { id: tileModel }

    function computeCards() {
        var viewed = overview.viewedId()
        var wss = Hyprland.workspaces.values.filter(function(w) { return w.id > 0 })
        // Grouped by monitor, left to right, then by number.
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
                wins.push({ toplevel: top, address: top.address, cls: o.class,
                            x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1],
                            floating: !!o.floating, fullscreen: (o.fullscreen || 0) > 0,
                            recency: o.focusHistoryID === undefined ? 99 : o.focusHistoryID })
            }
            // Tiled under floating, most recently used on top: the on-screen stacking order.
            wins.sort(function(a, b) {
                if (a.floating !== b.floating) return a.floating ? 1 : -1
                return b.recency - a.recency
            })
            var mon = ws.monitor
            out.push({ key: ws.id, id: ws.id, name: String(overview.slotOf(ws.id)), geom: overview.geometryOf(mon),
                       monitor: mon ? mon.name : "", monitorLabel: overview.monitorLabel(mon),
                       viewed: ws.id === viewed,
                       active: !!(mon && mon.activeWorkspace && mon.activeWorkspace.id === ws.id),
                       windows: wins, isNew: false })
        }
        // Each monitor's run ends in its own new card: the number after its highest, or its lowest
        // free one once 10 is taken; none when all ten are used. With workspaces numbered across
        // monitors, a new card skips any id another monitor uses, and monitors sharing a block get
        // keys of their own.
        var cards = []
        var used = {}
        for (var u = 0; u < out.length; u++) used[out[u].id] = true
        var group = 0
        for (var j = 0; j < out.length; j++) {
            cards.push(out[j])
            if (j + 1 < out.length && out[j + 1].monitor === out[j].monitor) continue
            var base = Math.floor((out[j].id - 1) / 10) * 10
            var next = overview.slotOf(out[j].id) < 10 && !used[out[j].id + 1] ? out[j].id + 1 : -1
            for (var s = 1; next < 0 && s <= 10; s++) if (!used[base + s]) next = base + s
            group++
            if (next < 0) continue
            cards.push({ key: -100 - base / 10 - 20 * group, id: next, name: String(overview.slotOf(next)), geom: out[j].geom,
                         monitor: out[j].monitor, monitorLabel: "", viewed: false, active: false,
                         windows: [], isNew: true })
        }
        // Each monitor's first card gets its name; its last gets a wider gap, except the very last.
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

    // The windows of the workspace on screen, each with its `home` rect: the overview covers the
    // monitor exactly, so screen coordinates are window coordinates.
    function computeTiles() {
        var viewed = overview.viewedId()
        var g = overview.geometryOf(bar.monitor)
        var tops = Hyprland.toplevels.values
        var out = []
        for (var t = 0; t < tops.length; t++) {
            var top = tops[t]
            if (!top.workspace || top.workspace.id !== viewed) continue
            var o = top.lastIpcObject || {}
            // A group's other tabs are hidden behind the one showing.
            if (!o.class || o.mapped === false || o.hidden === true || !o.at || !o.size) continue
            var full = (o.fullscreen || 0) > 0
            out.push({ key: top.address, toplevel: top, address: top.address, cls: o.class,
                       title: o.title || o.class, floating: !!o.floating,
                       home: full ? Qt.rect(0, 0, g.w, g.h)
                                  : Qt.rect(o.at[0] - g.x, o.at[1] - g.y, o.size[0], o.size[1]),
                       recency: o.focusHistoryID === undefined ? 99 : o.focusHistoryID })
        }
        out.sort(function(a, b) {
            if (a.floating !== b.floating) return a.floating ? 1 : -1
            return b.recency - a.recency
        })
        for (var i = 0; i < out.length; i++) out[i].order = i
        return out
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

    // The card for a workspace id: the workspace, or the new card that would create it.
    function cardFor(id) {
        var fresh = null
        for (var i = 0; i < overview.cardList.length; i++) {
            var c = overview.cardList[i]
            if (c.id !== id) continue
            if (!c.isNew) return c
            fresh = c
        }
        return fresh
    }

    function monitorLabel(monitor) {
        var o = monitor ? monitor.lastIpcObject : null
        return Display.shortName(o && o.description ? o : monitor)
    }

    function iconFor(cls) {
        var e = DesktopEntries.heuristicLookup(cls)
        return Quickshell.iconPath(e ? e.icon : String(cls).toLowerCase(), "application-x-executable")
    }

    // A card or tile as a string: builds that agree keep the first object, so views
    // aren't rebuilt and re-captured.
    function cardSignature(c) {
        return JSON.stringify([c.id, c.viewed, c.active, c.monitor, c.geom, c.groupStart, c.groupEnd, c.last,
                               c.windows.map(function(w) {
                                   return [w.address, w.x, w.y, w.w, w.h, w.floating, w.fullscreen]
                               })])
    }

    function tileSignature(t) {
        return JSON.stringify([t.home.x, t.home.y, t.home.width, t.home.height, t.floating, t.order, t.title])
    }

    // The keys a model holds that the next build does not.
    function leavingKeys(model, keys) {
        var out = []
        for (var r = 0; r < model.count; r++) {
            var k = model.get(r).key
            if (keys.indexOf(k) === -1) out.push(k)
        }
        return out
    }

    // Adds missing keys in order among the staying ones, so a staying view
    // keeps its delegate and capture.
    function insertKeys(model, keys, going) {
        var staying = []
        for (var s = 0; s < model.count; s++) {
            var ks = model.get(s).key
            if (going.indexOf(ks) === -1) staying.push(ks)
        }
        for (var k = 0; k < keys.length; k++) {
            if (staying.indexOf(keys[k]) !== -1) continue
            // Before the first staying one that comes after it.
            var at = model.count
            for (var m = 0; m < model.count; m++) {
                var km = model.get(m).key
                if (going.indexOf(km) !== -1) continue
                if (keys.indexOf(km) > k) { at = m; break }
            }
            model.insert(at, { key: keys[k] })
        }
    }

    function rebuild() {
        if (!overview.shown) return

        var cards = overview.computeCards()
        var cmap = {}
        for (var i = 0; i < cards.length; i++) {
            var old = overview.cardData[cards[i].key]
            if (old && overview.cardSignature(old) === overview.cardSignature(cards[i])) cards[i] = old
            cmap[cards[i].key] = cards[i]
        }
        var cardKeys = cards.map(function(c) { return c.key })
        var cardsGoing = overview.leavingKeys(cardModel, cardKeys)
        for (var g = 0; g < cardsGoing.length; g++)
            if (overview.cardData[cardsGoing[g]]) cmap[cardsGoing[g]] = overview.cardData[cardsGoing[g]]

        var tiles = overview.computeTiles()
        var tmap = {}
        for (var t = 0; t < tiles.length; t++) {
            var was = overview.tileData[tiles[t].key]
            if (was && overview.tileSignature(was) === overview.tileSignature(tiles[t])) tiles[t] = was
            tmap[tiles[t].key] = tiles[t]
        }
        var tileKeys = tiles.map(function(x) { return x.key })
        var tilesGoing = overview.leavingKeys(tileModel, tileKeys)
        for (var h = 0; h < tilesGoing.length; h++)
            if (overview.tileData[tilesGoing[h]]) tmap[tilesGoing[h]] = overview.tileData[tilesGoing[h]]

        // Data before models: a delegate created by the insert reads its data immediately.
        var monitors = {}
        for (var m = 0; m < cards.length; m++) monitors[cards[m].monitor] = true
        overview.several = Object.keys(monitors).length > 1
        overview.cardData = cmap
        overview.cardList = cards
        overview.goingCards = cardsGoing
        overview.tileData = tmap
        overview.tileList = tiles
        overview.goingTiles = tilesGoing
        overview.slots = overview.withGoing(overview.computeSlots(tiles))
        overview.insertKeys(cardModel, cardKeys, cardsGoing)
        overview.insertKeys(tileModel, tileKeys, tilesGoing)
        if (cardsGoing.length > 0 || tilesGoing.length > 0) goneTimer.restart()
        overview.revision++

        if (!tmap[overview.selectedKey] || tilesGoing.indexOf(overview.selectedKey) !== -1)
            overview.selectedKey = overview.firstKey()
        if (overview.confirmId > -2 && !cmap[overview.confirmId]) overview.confirmId = -2
    }

    // A tile on its way out keeps the place it had, and fades there.
    function withGoing(next) {
        for (var i = 0; i < overview.goingTiles.length; i++) {
            var k = overview.goingTiles[i]
            if (!next[k] && overview.slots[k]) next[k] = overview.slots[k]
        }
        return next
    }

    Timer {
        id: goneTimer
        interval: Theme.durLong
        onTriggered: {
            for (var r = cardModel.count - 1; r >= 0; r--)
                if (overview.goingCards.indexOf(cardModel.get(r).key) !== -1) cardModel.remove(r)
            for (var s = tileModel.count - 1; s >= 0; s--)
                if (overview.goingTiles.indexOf(tileModel.get(s).key) !== -1) tileModel.remove(s)
            overview.goingCards = []
            overview.goingTiles = []
        }
    }

    // Anything that moves a window or workspace: re-read a moment later, once Hyprland has settled.
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

    // Laying the windows out: rows between the strip and the key hints, each window
    // keeping its shape. Every row count is tried and the biggest windows win (fewer rows
    // on a near tie); never above maxWindowScale.
    readonly property real maxWindowScale: 0.7
    readonly property int columnGap: 40
    // Room under each row for the caption of the chosen window.
    readonly property int rowGap: 64

    readonly property rect area: {
        var top = overview.stripTop + overview.stripHeight(overview.thumbHeight) + 40
        var bottom = overview.height - overview.footerMargin - overview.footerHeight - 56
        return Qt.rect(Math.round(overview.width * 0.06), top,
                       Math.round(overview.width * 0.88), Math.max(80, bottom - top))
    }

    onAreaChanged: {
        if (!overview.shown) return
        overview.slots = overview.withGoing(overview.computeSlots(overview.tileList))
        overview.revision++
    }

    function computeSlots(tiles) {
        var out = {}
        var n = tiles.length
        if (n === 0) return out
        var A = overview.area
        var items = tiles.map(function(t) {
            return { key: t.key, w: Math.max(80, t.home.width), h: Math.max(60, t.home.height),
                     cx: t.home.x + t.home.width / 2, cy: t.home.y + t.home.height / 2 }
        })
        var byY = items.slice().sort(function(a, b) { return a.cy - b.cy || a.cx - b.cx })
        var best = null
        for (var rows = 1; rows <= n; rows++) {
            var per = Math.ceil(n / rows)
            var groups = []
            for (var i = 0; i < n; i += per)
                groups.push(byY.slice(i, i + per).sort(function(a, b) { return a.cx - b.cx }))
            var s = overview.maxWindowScale
            var heights = 0
            for (var g = 0; g < groups.length; g++) {
                var sumW = 0, maxH = 0
                for (var k = 0; k < groups[g].length; k++) {
                    sumW += groups[g][k].w
                    maxH = Math.max(maxH, groups[g][k].h)
                }
                s = Math.min(s, (A.width - overview.columnGap * (groups[g].length - 1)) / sumW)
                heights += maxH
            }
            s = Math.min(s, (A.height - overview.rowGap * (groups.length - 1)) / heights)
            if (!best || s > best.s * 1.04) best = { s: Math.max(0.04, s), groups: groups }
        }
        var rowHeights = best.groups.map(function(row) {
            var mh = 0
            for (var q = 0; q < row.length; q++) mh = Math.max(mh, row[q].h)
            return mh * best.s
        })
        var total = overview.rowGap * (best.groups.length - 1)
        for (var r = 0; r < rowHeights.length; r++) total += rowHeights[r]
        var y = A.y + (A.height - total) / 2
        for (var row = 0; row < best.groups.length; row++) {
            var line = best.groups[row]
            var rowW = overview.columnGap * (line.length - 1)
            for (var a = 0; a < line.length; a++) rowW += line[a].w * best.s
            var x = A.x + (A.width - rowW) / 2
            for (var b = 0; b < line.length; b++) {
                var w = line[b].w * best.s, hh = line[b].h * best.s
                out[line[b].key] = Qt.rect(Math.round(x), Math.round(y + (rowHeights[row] - hh) / 2),
                                           Math.round(w), Math.round(hh))
                x += w + overview.columnGap
            }
            y += rowHeights[row] + overview.rowGap
        }
        return out
    }

    // The strip's size

    readonly property int stripTop: 24
    readonly property int stripPadding: 14
    readonly property int thumbSpacing: 14
    // Between one monitor's workspaces and the next's.
    readonly property int groupSpacing: 36
    // Over each monitor's first workspace, its name, when there are several.
    readonly property int labelRoom: overview.several ? 22 : 0
    readonly property int chipGap: 8
    readonly property int chipHeight: 20
    readonly property int footerHeight: 38
    readonly property int footerMargin: 24

    function stripHeight(thumb) {
        return overview.stripPadding * 2 + overview.labelRoom + thumb + overview.chipGap + overview.chipHeight
    }

    // Every picture the same height at its monitor's aspect, small enough
    // for the strip to fit the screen.
    readonly property real thumbHeight: {
        var aspects = 0
        for (var i = 0; i < overview.cardList.length; i++)
            aspects += overview.cardList[i].geom.w / overview.cardList[i].geom.h
        var gaps = overview.stripPadding * 2
        for (var g = 0; g + 1 < overview.cardList.length; g++)
            gaps += overview.cardList[g].groupEnd ? overview.groupSpacing : overview.thumbSpacing
        var room = overview.width * 0.9 - gaps
        var most = Math.min(96, overview.height * 0.1)
        return Math.round(Math.max(40, Math.min(most, aspects > 0 ? room / aspects : most)))
    }
    // Eased as workspaces come and go, except while the strip first fills.
    property real shownThumb: overview.thumbHeight
    Behavior on shownThumb {
        enabled: !overview.opening
        Elastic {}
    }

    // Choosing

    // The window the keyboard is on, by address.
    property string selectedKey: ""

    // Hover picks a window only once the pointer has moved: a still pointer
    // stole the selection on open.
    property bool pointerSteers: false
    property point lastPointer: Qt.point(-1, -1)

    // The window last used, to start on.
    function mostRecent() {
        var best = null
        for (var i = 0; i < overview.tileList.length; i++) {
            var t = overview.tileList[i]
            if (!best || t.recency < best.recency) best = t
        }
        return best ? best.key : ""
    }

    // Starts on the last used window on the screen it opened on; elsewhere nowhere
    // until pointed at or a key is pressed.
    function firstKey() {
        return overview.home ? overview.mostRecent() : ""
    }

    // The nearest window in a direction; straight ahead counts more than off to the side.
    function step(dx, dy) {
        var cur = overview.slots[overview.selectedKey]
        if (!cur) { overview.selectedKey = overview.mostRecent(); return }
        var cx = cur.x + cur.width / 2, cy = cur.y + cur.height / 2
        var best = "", bestScore = Infinity
        for (var i = 0; i < overview.tileList.length; i++) {
            var k = overview.tileList[i].key
            var s = overview.slots[k]
            if (!s || k === overview.selectedKey) continue
            var vx = s.x + s.width / 2 - cx, vy = s.y + s.height / 2 - cy
            var ahead = dx !== 0 ? vx * dx : vy * dy
            if (ahead <= 1) continue
            var score = ahead + 2 * (dx !== 0 ? Math.abs(vy) : Math.abs(vx))
            if (score < bestScore) { bestScore = score; best = k }
        }
        if (best !== "") overview.selectedKey = best
    }

    // Tab's order: as the rows read.
    function cycle(dir) {
        var keys = overview.tileList.map(function(t) { return t.key }).filter(function(k) { return !!overview.slots[k] })
        if (keys.length === 0) return
        keys.sort(function(a, b) {
            var sa = overview.slots[a], sb = overview.slots[b]
            return Math.abs(sa.y - sb.y) > 8 ? sa.y - sb.y : sa.x - sb.x
        })
        var at = keys.indexOf(overview.selectedKey)
        overview.selectedKey = keys[((at + dir) % keys.length + keys.length) % keys.length]
    }

    // Dragging

    readonly property int noCard: -999
    // The card under a window being dragged; the strip lights it.
    property int dropKey: overview.noCard
    property string draggingKey: ""

    // Strip cards and tiles by key, registered by their delegates: drop
    // targets and what flies there.
    property var thumbs: ({})
    property var tileItems: ({})

    function cardKeyAt(p) {
        for (var i = 0; i < overview.cardList.length; i++) {
            var c = overview.cardList[i]
            var it = overview.thumbs[c.key]
            if (!it || overview.goingCards.indexOf(c.key) !== -1) continue
            var f = it.picture
            var q = f.mapFromItem(tilesLayer, p.x, p.y)
            if (q.x >= -6 && q.y >= -6 && q.x <= f.width + 6 && q.y <= f.height + 6) return c.key
        }
        return overview.noCard
    }

    // Whether a point (in this window's coordinates) is on this screen.
    function inside(p) {
        return p.x >= 0 && p.y >= 0 && p.x < overview.width && p.y < overview.height
    }

    // Off this screen, the screen under the pointer says where it would land.
    function dragMoved(p) {
        var g = overview.geometryOf(bar.monitor)
        Panels.overviewDragAt = Qt.point(g.x + p.x, g.y + p.y)
        overview.dropKey = overview.inside(p) ? overview.cardKeyAt(p) : overview.noCard
    }

    function endDrag() {
        Panels.overviewDrag = null
        Panels.overviewDropAt = null
    }

    // A floating window dropped on another screen lands where it was let go (the held
    // point under the pointer, clamped to that screen), on top. A tiled one goes
    // where that screen's layout puts it.
    function placeOn(name, tile) {
        if (!tile.d.floating) return ""
        var mon = Hyprland.monitors.values.filter(function(m) { return m.name === name })[0]
        if (!mon) return ""
        var g = overview.geometryOf(mon)
        var w = tile.d.home.width, h = tile.d.home.height
        var p = Panels.overviewDragAt
        var x = Math.round(Math.max(g.x, Math.min(g.x + g.w - w, p.x - tile.grabFx * w)))
        var y = Math.round(Math.max(g.y, Math.min(g.y + g.h - h, p.y - tile.grabFy * h)))
        var win = "window = 'address:0x" + tile.d.address + "'"
        return "hl.dispatch(hl.dsp.window.move({ x = " + x + ", y = " + y + ", " + win + " })); "
             + "hl.dispatch(hl.dsp.window.alter_zorder({ mode = 'top', " + win + " }))"
    }

    // Dropped on another workspace: the window moves there and the tile flies into its
    // picture. On another screen, into the workspace it shows or the card under it;
    // anywhere else the tile goes back.
    function dropped(tile) {
        var key = overview.dropKey
        var at = Panels.overviewDropAt
        var away = !overview.inside(tile.pointer)
        overview.dropKey = overview.noCard
        overview.draggingKey = ""
        if (away) {
            if (at && tile.d && at.screen !== overview.screenName && at.id > 0 && at.id !== overview.viewedId()) {
                // Before the drag ends, so that screen knows to keep its copy.
                Panels.overviewDropped = { address: tile.d.address, screen: at.screen, key: at.key }
                var place = at.key === overview.noCard ? overview.placeOn(at.screen, tile) : ""
                overview.endDrag()
                tile.handOff()
                overview.moveWindow(tile.d.address, at.id, place)
                overview.afterMove(tile.d.address, at.isNew)
            } else {
                overview.endDrag()
                tile.settle()
            }
            return
        }
        overview.endDrag()
        var card = overview.cardData[key]
        if (card && tile.d && overview.goingCards.indexOf(key) === -1 && card.id !== overview.viewedId()) {
            tile.sendInto(overview.thumbs[key] ? overview.thumbs[key].picture : null, card.geom)
            overview.moveWindow(tile.d.address, card.id)
            overview.afterMove(tile.d.address, card.isNew)
        } else {
            tile.settle()
        }
    }

    // A window carried here from another screen

    readonly property var visitor: {
        var d = Panels.overviewDrag
        return d && d.from !== overview.screenName && overview.shown ? d : null
    }
    // The pointer, in this window's coordinates.
    readonly property point visitorAt: {
        // Nothing read when there's no visitor, so nothing re-runs on monitor refreshes.
        if (!overview.visitor) return Qt.point(-1, -1)
        var g = overview.geometryOf(bar.monitor)
        return Qt.point(Panels.overviewDragAt.x - g.x, Panels.overviewDragAt.y - g.y)
    }
    readonly property bool hosting: overview.visitor !== null && overview.spread && overview.inside(overview.visitorAt)

    // The card under the visitor (a strip card, else the shown workspace), published only on
    // change since every screen reads it.
    function aimVisitor() {
        var at = Panels.overviewDropAt
        if (!overview.hosting) {
            if (overview.draggingKey === "") overview.dropKey = overview.noCard
            if (at && at.screen === overview.screenName) Panels.overviewDropAt = null
            return
        }
        var key = overview.cardKeyAt(overview.visitorAt)
        overview.dropKey = key
        var card = overview.cardData[key]
        var id = card ? card.id : overview.viewedId()
        var scale = ghost.scaleNow
        if (at && at.screen === overview.screenName && at.key === key && at.id === id && at.scale === scale) return
        Panels.overviewDropAt = { screen: overview.screenName, key: key, id: id,
                                  isNew: !!(card && card.isNew), scale: scale }
    }

    Connections {
        target: Panels
        enabled: overview.shown
        function onOverviewDroppedChanged() {
            var d = Panels.overviewDropped
            if (d && d.screen === overview.screenName) ghost.land(d.key)
        }
    }

    // The keyboard's way of doing the same.
    function sendWindow(key, id) {
        var tile = overview.tileItems[key]
        if (!tile || !tile.d || tile.sendTo || id < 1 || id === overview.viewedId()) return
        var card = overview.cardFor(id)
        var it = card ? overview.thumbs[card.key] : null
        tile.sendInto(it ? it.picture : null, card ? card.geom : null)
        overview.moveWindow(tile.d.address, id)
        // A number with no workspace yet makes one, as New does.
        overview.afterMove(tile.d.address, !card || card.isNew)
    }

    // Moving a window closes the overview once it has landed. Into an existing workspace
    // the rest fly home to their retiled places; into a new one the overview closes quickly
    // and focus follows the window there.
    property string followAddress: ""

    function afterMove(address, follow) {
        overview.followAddress = follow ? address : ""
        closeAfterMove.restart()
    }

    Timer {
        id: closeAfterMove
        interval: Theme.durLong
        onTriggered: {
            if (!overview.open) return
            var a = overview.followAddress
            overview.followAddress = ""
            if (a === "") {
                overview.close()
                return
            }
            overview.leaveThen(function() {
                overview.run("hl.dispatch(hl.dsp.focus({ window = 'address:0x" + a + "' }))")
            })
        }
    }

    // Acting

    function close() {
        Panels.overviewOpen = false
    }

    property var pending: null

    // Closes at once and runs `what` a moment later, once the keyboard is released,
    // or focus would move into the grab.
    function leaveThen(what) {
        Panels.overviewLeaving = true
        overview.pending = what
        overview.close()
        actTimer.restart()
    }

    // Closes the slow way, windows flying home, and runs `what` once they've
    // landed and the surface is gone.
    function dismissThen(what) {
        overview.pending = what
        overview.close()
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

    // A name as a Lua string, quotes and backslashes escaped.
    function luaString(s) {
        return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    }

    // Back to the shown workspace, the windows fly home; to any other, close quickly
    // and let Hyprland's animation play.
    function goToWorkspace(id) {
        if (id === overview.viewedId()) {
            overview.close()
            return
        }
        overview.leaveThen(function() { overview.run("hl.dispatch(hl.dsp.focus({ workspace = " + id + " }))") })
    }

    // Focused and raised: focusing alone left a floating window under the one it was behind.
    // It also lands on top on the way home.
    property string chosenKey: ""

    function chooseWindow(key) {
        var t = overview.tileData[key]
        if (!t) return
        overview.selectedKey = key
        overview.chosenKey = key
        overview.dismissThen(function() {
            var w = "window = 'address:0x" + t.address + "'"
            overview.run("hl.dispatch(hl.dsp.focus({ " + w + " })); "
                         + "hl.dispatch(hl.dsp.window.alter_zorder({ mode = 'top', " + w + " }))")
        })
    }

    // Switches this monitor to the previous or next workspace behind the overview, so closing
    // lands the windows where they now are.
    function viewWorkspace(delta) {
        var name = bar.monitor ? bar.monitor.name : ""
        var mine = overview.cardList.filter(function(c) { return !c.isNew && c.monitor === name })
        var at = -1
        for (var i = 0; i < mine.length; i++) if (mine[i].viewed) at = i
        var next = mine[at + delta]
        if (at < 0 || !next) return
        overview.run("hl.get_monitor(" + overview.luaString(name) + "):set_workspace({ workspace = " + next.id + " })")
    }

    // Without following it; `then` is Lua run right after, in the same call.
    function moveWindow(address, id, then) {
        overview.run("hl.dispatch(hl.dsp.window.move({ workspace = " + id
                     + ", follow = false, window = 'address:0x" + address + "' }))"
                     + (then ? "; " + then : ""))
    }

    function closeWindow(address) {
        overview.run("hl.dispatch(hl.dsp.window.close({ window = 'address:0x" + address + "' }))")
    }

    // Removing a workspace: Hyprland drops one once it has no windows and no monitor shows
    // it, so close its windows and show its monitor another workspace without moving focus.
    // A monitor's only workspace can't go.
    property int confirmId: -2          // the workspace asking "close N windows?"

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
            overview.run("hl.get_monitor(" + overview.luaString(card.monitor)
                         + "):set_workspace({ workspace = " + other.id + " })")
        }
    }

    // Drawing

    // How much of the backdrop is up, driven by hand: in quickly, out late over the whole flight
    // home, so the real windows show only as the pictures land.
    property real veil: 0

    NumberAnimation {
        id: veilAnim
        target: overview
        property: "veil"
    }

    onSpreadChanged: {
        veilAnim.stop()
        veilAnim.to = overview.spread ? 1 : 0
        veilAnim.duration = overview.spread ? Theme.durMedium : Theme.durLong
        veilAnim.easing.type = overview.spread ? Easing.OutQuad : Easing.InQuad
        veilAnim.start()
    }

    Item {
        id: stage
        anchors.fill: parent
        // Going to another workspace: gone at once so Hyprland's animation shows.
        opacity: overview.leaving ? 0 : 1

        HoverHandler {
            onPointChanged: {
                var p = point.position
                var last = overview.lastPointer
                overview.lastPointer = p
                if (last.x >= 0 && (Math.abs(p.x - last.x) >= 1 || Math.abs(p.y - last.y) >= 1))
                    overview.pointerSteers = true
            }
        }

        Item {
            id: keys
            focus: true

            // The number row by scan code, not symbol: Shift changes the symbol per layout. xkb
            // codes are evdev + 8, so 1-9 are 10-18 and 0 is 19.
            function digitOf(event) {
                var c = event.nativeScanCode
                if (c >= 10 && c <= 18) return c - 9
                if (c === 19) return 10
                if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) return event.key - Qt.Key_0
                if (event.key === Qt.Key_0) return 10
                return 0
            }

            Keys.onPressed: event => {
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
                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                var digit = keys.digitOf(event)
                if (event.key === Qt.Key_Escape) {
                    overview.close()
                } else if (ctrl && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                    overview.viewWorkspace(event.key === Qt.Key_Left ? -1 : 1)
                } else if (event.key === Qt.Key_Left) {
                    overview.step(-1, 0)
                } else if (event.key === Qt.Key_Right) {
                    overview.step(1, 0)
                } else if (event.key === Qt.Key_Up) {
                    overview.step(0, -1)
                } else if (event.key === Qt.Key_Down) {
                    overview.step(0, 1)
                } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && shift)) {
                    overview.cycle(-1)
                } else if (event.key === Qt.Key_Tab) {
                    overview.cycle(1)
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (overview.selectedKey !== "") overview.chooseWindow(overview.selectedKey)
                    else overview.close()
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    overview.removeWorkspace(overview.cardData[overview.viewedId()], false)
                } else if (event.key === Qt.Key_N) {
                    var fresh = overview.newCardFor(bar.monitor)
                    if (fresh && shift) overview.sendWindow(overview.selectedKey, fresh.id)
                    else if (fresh) overview.goToWorkspace(fresh.id)
                } else if (digit > 0) {
                    var id = overview.blockOf(bar.monitor) + digit
                    if (shift) overview.sendWindow(overview.selectedKey, id)
                    else overview.goToWorkspace(id)
                } else {
                    return
                }
                event.accepted = true
            }
        }

        // The backdrop: the dimmed wallpaper, opaque so the bar and real windows are hidden; a
        // plain fill covers the image's load.
        Item {
            anchors.fill: parent
            opacity: overview.veil

            Rectangle {
                anchors.fill: parent
                color: Theme.background
            }

            Image {
                anchors.fill: parent
                source: overview.shown && Wallpaper.wallpaperStill.length > 0 ? "file://" + Wallpaper.wallpaperStill : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: overview.width
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.scrim
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (overview.confirmId > -2) overview.confirmId = -2
                    else overview.close()
                }
            }
        }

        // The strip

        RectangularShadow {
            anchors.fill: strip
            radius: strip.radius
            blur: 30
            offset.y: 8
            color: Theme.alpha(Theme.shadow, 0.4)
            opacity: strip.opacity
        }

        Rectangle {
            id: strip
            anchors.horizontalCenter: parent.horizontalCenter
            y: overview.spread ? overview.stripTop : overview.stripTop - 16
            width: stripRow.width + overview.stripPadding * 2
            height: overview.stripHeight(overview.shownThumb)
            radius: Theme.radiusXLarge
            color: Theme.surface
            opacity: overview.spread ? 1 : 0

            Behavior on y { Elastic { small: true } }
            Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutQuad } }

            // Its own clicks: between the pictures is not the backdrop.
            MouseArea {
                anchors.fill: parent
            }

            // A Row, not a ListView: ListView lost track of its cards when one came
            // or went and the widths changed.
            Row {
                id: stripRow
                x: overview.stripPadding
                y: overview.stripPadding + overview.labelRoom

                Repeater {
                    model: cardModel

                    delegate: Item {
                        id: card
                        required property int key

                        readonly property var d: {
                            overview.revision
                            return overview.cardData[card.key] || { id: 0, name: "", geom: { x: 0, y: 0, w: 16, h: 9 },
                                                                     windows: [], isNew: true, monitor: "" }
                        }
                        readonly property var geom: card.d.geom
                        readonly property bool going: overview.goingCards.indexOf(card.key) !== -1
                        readonly property bool hovered: cardHover.hovered && overview.draggingKey === ""
                        readonly property bool aimed: overview.dropKey === card.key && !card.going
                        readonly property bool confirming: overview.confirmId === card.d.id && !card.d.isNew
                        // What a dragged window is measured against and flies into.
                        readonly property Item picture: face

                        // Each card carries the gap after it and hands over its whole width as it
                        // goes or comes, so the strip resizes smoothly.
                        readonly property real faceWidth: Math.round(overview.shownThumb * card.geom.w / card.geom.h)
                        property real grow: 1
                        width: Math.round((card.faceWidth + (card.d.last ? 0
                                           : card.d.groupEnd ? overview.groupSpacing : overview.thumbSpacing)) * card.grow)
                        height: overview.shownThumb + overview.chipGap + overview.chipHeight

                        opacity: 0
                        scale: 0.9

                        // Set once, not bound: a card that arrives after the strip
                        // filled grows in from nothing.
                        Component.onCompleted: {
                            overview.thumbs[card.key] = card
                            entrance.start()
                            if (!overview.opening) {
                                card.grow = 0
                                growIn.start()
                            }
                        }
                        Component.onDestruction: {
                            if (overview.thumbs[card.key] === card) delete overview.thumbs[card.key]
                        }

                        NumberAnimation {
                            id: growIn
                            target: card; property: "grow"; to: 1
                            duration: Theme.durLong; easing.type: Easing.OutCubic
                        }

                        ParallelAnimation {
                            id: entrance
                            NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.durMedium; easing.type: Easing.OutQuad }
                            Elastic { target: card; property: "scale"; to: 1 }
                        }

                        onGoingChanged: if (going) { entrance.stop(); exit.start() }

                        ParallelAnimation {
                            id: exit
                            NumberAnimation { target: card; property: "opacity"; to: 0; duration: Theme.durMedium; easing.type: Easing.OutQuad }
                            NumberAnimation { target: card; property: "scale"; to: 0.85; duration: Theme.durMedium; easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "grow"; to: 0; duration: Theme.durLong; easing.type: Easing.OutCubic }
                        }

                        // The monitor's name, over its first workspace.
                        Row {
                            visible: !!card.d.groupStart
                            x: 2
                            y: -overview.labelRoom
                            spacing: 6

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

                        // Lifts a little on hover, more under a held window.
                        Item {
                            id: face
                            width: card.faceWidth
                            height: overview.shownThumb
                            y: card.aimed ? -4 : card.hovered ? -2 : 0
                            scale: card.aimed ? 1.06 : card.hovered ? 1.02 : 1

                            Behavior on y { Elastic { small: true } }
                            Behavior on scale { Elastic { small: true } }

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusMedium
                                color: card.d.isNew ? Theme.alpha(Theme.foreground, card.hovered || card.aimed ? 0.08 : 0.04)
                                                    : Theme.surfaceContainerHigh

                                Behavior on color { ColorAnimation { duration: Theme.durShort } }
                            }

                            // The new card's dashed outline: a place for a workspace, not one yet.
                            Canvas {
                                anchors.fill: parent
                                visible: card.d.isNew
                                opacity: card.hovered || card.aimed ? 0.9 : 0.45
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var r = Theme.radiusMedium - 1, w = width - 2, h = height - 2
                                    ctx.strokeStyle = Theme.textSecondary
                                    ctx.lineWidth = 1.5
                                    ctx.setLineDash([5, 5])
                                    ctx.beginPath()
                                    ctx.moveTo(1 + r, 1)
                                    ctx.arcTo(1 + w, 1, 1 + w, 1 + h, r)
                                    ctx.arcTo(1 + w, 1 + h, 1, 1 + h, r)
                                    ctx.arcTo(1, 1 + h, 1, 1, r)
                                    ctx.arcTo(1, 1, 1 + w, 1, r)
                                    ctx.closePath()
                                    ctx.stroke()
                                }

                                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                            }

                            // Click on the card: go there. Declared first so the ×
                            // above takes its own click.
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (overview.confirmId > -2) overview.confirmId = -2
                                    else overview.goToWorkspace(card.d.id)
                                }
                            }

                            ClippingRectangle {
                                id: screenArea
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: Theme.radiusMedium - 3
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
                                    opacity: card.d.viewed ? 0.85 : 0.6

                                    Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }
                                }

                                // A new workspace: a plus where the windows would be.
                                IconGlyph {
                                    anchors.centerIn: parent
                                    visible: card.d.isNew
                                    text: "\u{F0415}"
                                    color: Theme.textSecondary
                                    size: Theme.iconLarge
                                    opacity: card.hovered || card.aimed ? 1 : 0.55

                                    Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                                }

                                Repeater {
                                    model: card.d.windows

                                    delegate: Item {
                                        id: win
                                        required property var modelData

                                        readonly property real sx: screenArea.width / card.geom.w
                                        readonly property real sy: screenArea.height / card.geom.h
                                        readonly property bool whole: win.modelData.fullscreen

                                        // Clamped so a window partly off its monitor
                                        // stays in the picture.
                                        x: whole ? 0 : Math.max(0, Math.min(parent.width - width,
                                                                             Math.round((win.modelData.x - card.geom.x) * sx)))
                                        y: whole ? 0 : Math.max(0, Math.min(parent.height - height,
                                                                             Math.round((win.modelData.y - card.geom.y) * sy)))
                                        width: whole ? parent.width : Math.min(parent.width, Math.max(10, Math.round(win.modelData.w * sx)))
                                        height: whole ? parent.height : Math.min(parent.height, Math.max(8, Math.round(win.modelData.h * sy)))
                                        // Fades in once the capture arrives, instead of
                                        // popping in over a blank.
                                        opacity: miniShot.hasContent ? 1 : 0

                                        Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutQuad } }

                                        ClippingRectangle {
                                            anchors.fill: parent
                                            radius: Theme.radiusSmall / 2
                                            color: Theme.surfaceContainerHigh

                                            ScreencopyView {
                                                id: miniShot
                                                anchors.fill: parent
                                                captureSource: overview.shown ? win.modelData.toplevel.wayland : null
                                                live: false
                                            }
                                        }

                                        // Its app icon, centred, when there's room.
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 22
                                            height: 22
                                            radius: height / 2
                                            color: Theme.alpha(Theme.shadow, 0.45)
                                            visible: win.width > 40 && win.height > 30

                                            IconImage {
                                                anchors.centerIn: parent
                                                implicitSize: 14
                                                mipmap: true
                                                source: overview.iconFor(win.modelData.cls)
                                            }
                                        }
                                    }
                                }
                            }

                            // Where a dragged window would go.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: Theme.radiusMedium + 4
                                color: "transparent"
                                border.width: 2
                                border.color: Theme.accent
                                opacity: card.aimed ? 1 : 0

                                Behavior on opacity { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad } }
                            }

                            // Remove the workspace; last, so it's on top and takes its click.
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: -7
                                anchors.rightMargin: -7
                                width: 20
                                height: 20
                                radius: height / 2
                                color: removeArea.containsMouse ? Theme.error : Theme.surface
                                border.width: 1
                                border.color: Theme.outline
                                visible: overview.canRemove(card.d)
                                opacity: card.hovered && !card.confirming ? 1 : 0
                                scale: opacity > 0.5 ? 1 : 0.6

                                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                                Behavior on scale { Elastic { small: true } }
                                Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                IconGlyph {
                                    anchors.centerIn: parent
                                    text: "\u{F0156}"
                                    color: Theme.textPrimary
                                    size: 10
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
                            }
                        }

                        // The number, accent-filled on the workspace whose windows are out.
                        Rectangle {
                            anchors.horizontalCenter: face.horizontalCenter
                            y: overview.shownThumb + overview.chipGap
                            width: Math.max(22, num.implicitWidth + 14)
                            height: overview.chipHeight
                            radius: height / 2
                            color: card.d.viewed ? Theme.accent
                                 : card.d.isNew ? "transparent" : Theme.alpha(Theme.foreground, 0.1)

                            Behavior on color { ColorAnimation { duration: Theme.durMedium } }

                            Text {
                                id: num
                                anchors.centerIn: parent
                                text: card.d.isNew ? "New" : card.d.name
                                color: card.d.viewed ? Theme.accentText
                                     : card.d.isNew ? Theme.textSecondary : Theme.textPrimary
                                font.pixelSize: 11
                                font.bold: !card.d.isNew
                                font.family: Theme.fontText
                                font.features: Theme.tabular

                                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                            }
                        }
                    }
                }
            }
        }

        // Nothing to spread out.
        Rectangle {
            x: overview.area.x + (overview.area.width - width) / 2
            y: overview.area.y + (overview.area.height - height) / 2
            width: emptyText.implicitWidth + 32
            height: 36
            radius: height / 2
            color: Theme.surface
            opacity: overview.spread && overview.shown && overview.tileList.length === 0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutQuad } }

            Text {
                id: emptyText
                anchors.centerIn: parent
                text: "No windows on this workspace"
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontText
            }
        }

        // The key hints on their own surface: the wallpaper under them can be any brightness.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: overview.footerMargin
            width: hints.implicitWidth + 32
            height: overview.footerHeight
            radius: height / 2
            color: Theme.surface
            opacity: overview.spread ? 1 : 0

            Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutQuad } }

            MouseArea {
                anchors.fill: parent
            }

            Row {
                id: hints
                anchors.centerIn: parent
                spacing: 14

                KeyHint { key: "← →"; label: "Choose" }
                KeyHint { key: "↵"; label: "Go" }
                KeyHint { key: "ctrl ← →"; label: "Workspace" }
                KeyHint { key: "1-9"; label: "Jump" }
                KeyHint { key: "shift 1-9"; label: "Move window" }
                KeyHint { key: "n"; label: "New" }
                KeyHint { key: "del"; label: "Remove" }
                KeyHint { key: "esc"; label: "Back" }
            }
        }

        // Drop target for a window carried from another screen: the workspace this screen
        // shows, outlined like a strip card.
        Rectangle {
            x: overview.area.x - 24
            y: overview.area.y - 24
            width: overview.area.width + 48
            height: overview.area.height + 48
            radius: Theme.radiusXLarge
            color: Theme.alpha(Theme.accent, 0.06)
            border.width: 2
            border.color: Theme.accent
            readonly property bool aimed: overview.hosting && overview.dropKey === overview.noCard
            opacity: aimed ? 1 : 0
            scale: aimed ? 1 : 0.98
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad } }
            Behavior on scale { Elastic { small: true } }
        }

        // The windows, above the strip so one dragged up there passes over it.
        Item {
            id: tilesLayer
            anchors.fill: parent

            Repeater {
                model: tileModel

                delegate: Item {
                    id: tile
                    required property string key

                    readonly property var d: {
                        overview.revision
                        return overview.tileData[tile.key] || null
                    }
                    readonly property rect slot: {
                        overview.revision
                        var s = overview.slots[tile.key]
                        return s ? s : (tile.d ? tile.d.home : Qt.rect(0, 0, 0, 0))
                    }
                    readonly property bool going: overview.goingTiles.indexOf(tile.key) !== -1
                    readonly property bool chosen: overview.selectedKey === tile.key && !tile.going

                    // Out of its place: set a beat after the tile is made at the window's spot, so
                    // it has somewhere to leave from.
                    property bool launched: false
                    // Moves are animated; off while it follows the pointer.
                    property bool animate: true
                    property bool dragging: false
                    // The strip picture it flies into once sent to another workspace.
                    property var sendTo: null
                    property real sent: 0
                    property real appear: 0
                    // A window that appears while the overview is up grows in
                    // place instead of flying out.
                    property bool popIn: true
                    property point pointer: Qt.point(0, 0)
                    // Where it was picked up, so that point stays under the
                    // pointer at any carry size.
                    property real grabFx: 0.5
                    property real grabFy: 0.5

                    // Carried at most 320px wide so it can be aimed; over a workspace, the
                    // size it would be in that picture.
                    readonly property real carryScale: Math.min(1, 320 / Math.max(1, tile.slot.width))
                    readonly property real miniScale: {
                        var it = overview.thumbs[overview.dropKey]
                        var c = overview.cardData[overview.dropKey]
                        if (!it || !c || !tile.d) return tile.carryScale
                        var w = it.picture.width * tile.d.home.width / c.geom.w
                        return Math.max(0.04, Math.min(tile.carryScale, w / Math.max(1, tile.slot.width)))
                    }
                    // Over another screen, the size that screen draws it at, so the
                    // two halves meet at the edge.
                    readonly property real remoteScale: {
                        var at = Panels.overviewDropAt
                        return tile.dragging && at && at.screen !== overview.screenName && at.scale > 0 ? at.scale : 0
                    }
                    property real carry: tile.dragging ? (overview.dropKey !== overview.noCard ? tile.miniScale
                                                          : tile.remoteScale > 0 ? tile.remoteScale : tile.carryScale) : 1
                    Behavior on carry { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }

                    readonly property rect goal: {
                        if (!tile.d) return Qt.rect(0, 0, 0, 0)
                        if (tile.dragging) {
                            var w = tile.slot.width * tile.carry, h = tile.slot.height * tile.carry
                            return Qt.rect(tile.pointer.x - tile.grabFx * w, tile.pointer.y - tile.grabFy * h, w, h)
                        }
                        if (tile.sendTo) return tile.sendTo
                        if (tile.launched && overview.spread) return tile.slot
                        return tile.d.home
                    }

                    // By hand, not Behaviors, so each move picks its curve: out on the soft spring,
                    // home and into the strip on a plain ease, none under the pointer.
                    onGoalChanged: tile.moveTo(tile.goal)

                    property bool springMove: true

                    function moveTo(r) {
                        motion.stop()
                        if (!tile.animate) {
                            tile.x = r.x
                            tile.y = r.y
                            tile.width = r.width
                            tile.height = r.height
                            return
                        }
                        tile.springMove = overview.spread && !tile.sendTo
                        mx.to = r.x
                        my.to = r.y
                        mw.to = r.width
                        mh.to = r.height
                        motion.start()
                    }

                    ParallelAnimation {
                        id: motion
                        NumberAnimation {
                            id: mx; target: tile; property: "x"
                            duration: tile.springMove ? Theme.durSpring : Theme.durLong
                            easing.type: tile.springMove ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: Theme.springOvershoot
                        }
                        NumberAnimation {
                            id: my; target: tile; property: "y"
                            duration: tile.springMove ? Theme.durSpring : Theme.durLong
                            easing.type: tile.springMove ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: Theme.springOvershoot
                        }
                        NumberAnimation {
                            id: mw; target: tile; property: "width"
                            duration: tile.springMove ? Theme.durSpring : Theme.durLong
                            easing.type: tile.springMove ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: Theme.springOvershoot
                        }
                        NumberAnimation {
                            id: mh; target: tile; property: "height"
                            duration: tile.springMove ? Theme.durSpring : Theme.durLong
                            easing.type: tile.springMove ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: Theme.springOvershoot
                        }
                    }

                    function startDrag(p) {
                        tile.animate = false
                        tile.pointer = p
                        tile.dragging = true
                        overview.draggingKey = tile.key
                        overview.selectedKey = tile.key
                        Panels.overviewDropped = null
                        Panels.overviewDropAt = null
                        // Where it is first, or other screens would read where the last drag ended.
                        var g = overview.geometryOf(bar.monitor)
                        Panels.overviewDragAt = Qt.point(g.x + p.x, g.y + p.y)
                        Panels.overviewDrag = { address: tile.d.address, toplevel: tile.d.toplevel, cls: tile.d.cls,
                                                from: overview.screenName, w: tile.slot.width, h: tile.slot.height,
                                                homeW: tile.d.home.width, homeH: tile.d.home.height,
                                                fx: tile.grabFx, fy: tile.grabFy }
                    }

                    // Back to its place.
                    function settle() {
                        tile.animate = true
                        tile.dragging = false
                    }

                    // Dropped on another screen, which draws the landing; the part
                    // still here fades in place.
                    function handOff() {
                        tile.sendTo = Qt.rect(tile.x, tile.y, tile.width, tile.height)
                        tile.dragging = false
                        tile.animate = true
                        sentAnim.restart()
                        sendGuard.restart()
                    }

                    // Into a workspace picture, fading as it lands; with no picture (not in the
                    // strip yet), up towards the strip.
                    function sendInto(picture, geom) {
                        var r
                        if (picture && tile.d) {
                            var p = picture.mapToItem(tilesLayer, 0, 0)
                            var w = Math.max(8, picture.width * tile.d.home.width / (geom ? geom.w : overview.width))
                            var h = Math.max(6, picture.height * tile.d.home.height / (geom ? geom.h : overview.height))
                            r = Qt.rect(p.x + (picture.width - w) / 2, p.y + (picture.height - h) / 2, w, h)
                        } else {
                            r = Qt.rect(tile.x + tile.width / 2 - 20, strip.y + strip.height / 2, 40, 24)
                        }
                        tile.animate = true
                        tile.sendTo = r
                        tile.dragging = false
                        sentAnim.restart()
                        sendGuard.restart()
                    }

                    z: tile.dragging ? 1000 : overview.chosenKey === tile.key ? 999 : (tile.d ? tile.d.order : 0)
                    opacity: tile.appear * tile.presence * (1 - tile.sent)

                    // Fades late over the flight home, so the real window takes over as it lands.
                    property real presence: overview.spread ? 1 : 0
                    Behavior on presence { NumberAnimation { duration: Theme.durLong; easing.type: Easing.InQuad } }

                    transform: Scale {
                        origin.x: tile.width / 2
                        origin.y: tile.height / 2
                        xScale: tile.popIn ? 0.92 + 0.08 * tile.appear : 1
                        yScale: tile.popIn ? 0.92 + 0.08 * tile.appear : 1
                    }

                    // Placed without a move: at its screen place while opening, at its layout
                    // place when it turns up later.
                    Component.onCompleted: {
                        overview.tileItems[tile.key] = tile
                        tile.capturedSize = tile.sizeKey
                        // Dropped here from another screen: starts whole where it was let go.
                        var from = overview.arrivals[tile.key]
                        if (from) {
                            delete overview.arrivals[tile.key]
                            tile.animate = false
                            tile.launched = true
                            tile.popIn = false
                            tile.moveTo(from)
                            tile.appear = 1
                            tile.animate = true
                            tile.moveTo(tile.goal)
                            if (ghost.held && ghost.held.address === tile.key) ghost.handOver()
                            return
                        }
                        tile.animate = false
                        tile.launched = !overview.opening
                        tile.popIn = !overview.opening
                        tile.moveTo(tile.goal)
                        tile.animate = true
                        if (overview.opening) launch.start()
                        appearAnim.start()
                    }
                    Component.onDestruction: {
                        if (overview.tileItems[tile.key] === tile) delete overview.tileItems[tile.key]
                    }

                    Timer {
                        id: launch
                        interval: 0
                        onTriggered: tile.launched = true
                    }

                    onGoingChanged: {
                        if (tile.going) {
                            if (!tile.sendTo) {
                                tile.popIn = true
                                appearAnim.stop()
                                vanish.start()
                            }
                        } else {
                            vanish.stop()
                            appearAnim.start()
                        }
                    }

                    // Quick on the way out, so the picture is solid before the
                    // backdrop hides the window.
                    NumberAnimation {
                        id: appearAnim
                        target: tile; property: "appear"; to: 1
                        duration: tile.popIn ? Theme.durMedium : Theme.durShort; easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        id: vanish
                        target: tile; property: "appear"; to: 0
                        duration: Theme.durMedium; easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        id: sentAnim
                        target: tile; property: "sent"; from: 0; to: 1
                        duration: Theme.durLong; easing.type: Easing.InQuad
                    }

                    // Hyprland didn't make the move: the window is still here,
                    // so the tile comes back.
                    Timer {
                        id: sendGuard
                        interval: 1500
                        onTriggered: {
                            if (tile.going) return
                            sentAnim.stop()
                            tile.sent = 0
                            tile.sendTo = null
                        }
                    }

                    // Captures are stills; when the window changes shape (retiling) it is
                    // re-captured after Hyprland's animation instead of stretched.
                    readonly property string sizeKey: tile.d ? tile.d.home.width + "x" + tile.d.home.height : ""
                    property string capturedSize: ""
                    onSizeKeyChanged: {
                        if (tile.sizeKey === tile.capturedSize || tile.sizeKey === "") return
                        tile.capturedSize = tile.sizeKey
                        recapture.restart()
                    }

                    Timer {
                        id: recapture
                        interval: Theme.durSpring + Theme.durShort
                        onTriggered: shot.captureFrame()
                    }

                    // Shadow while out; on the way home the window's own shadow takes over.
                    RectangularShadow {
                        anchors.fill: parent
                        radius: face.radius
                        blur: 30
                        offset.y: 10
                        color: Theme.alpha(Theme.shadow, 0.45)
                        opacity: tile.launched && overview.spread && !tile.sendTo ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }
                    }

                    ClippingRectangle {
                        id: face
                        anchors.fill: parent
                        // The window's own corners at home, card corners while out.
                        radius: tile.sendTo ? Theme.radiusSmall
                              : tile.launched && overview.spread ? Theme.radiusLarge : overview.windowRounding
                        color: Theme.surfaceContainerHigh

                        Behavior on radius { NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic } }

                        // Its app, until the capture arrives.
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 40
                            mipmap: true
                            visible: !shot.hasContent
                            source: tile.d ? overview.iconFor(tile.d.cls) : ""
                        }

                        ScreencopyView {
                            id: shot
                            anchors.fill: parent
                            captureSource: overview.shown && tile.d ? tile.d.toplevel.wayland : null
                            live: false
                            opacity: shot.hasContent ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutQuad } }
                        }
                    }

                    // Where the keyboard is.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -5
                        radius: face.radius + 5
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        opacity: tile.chosen && overview.spread && !tile.dragging && !tile.sendTo ? 1 : 0

                        Behavior on opacity { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad } }
                    }

                    // Picking it up, or going to it.
                    MouseArea {
                        id: grab
                        anchors.fill: parent
                        enabled: overview.spread && !tile.sendTo && !tile.going
                        preventStealing: true
                        cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                        property point pressAt: Qt.point(0, 0)
                        property bool moved: false

                        onPressed: mouse => {
                            grab.pressAt = grab.mapToItem(tilesLayer, mouse.x, mouse.y)
                            grab.moved = false
                            tile.grabFx = mouse.x / Math.max(1, grab.width)
                            tile.grabFy = mouse.y / Math.max(1, grab.height)
                        }
                        onPositionChanged: mouse => {
                            var p = grab.mapToItem(tilesLayer, mouse.x, mouse.y)
                            if (!tile.dragging) {
                                if (Math.abs(p.x - grab.pressAt.x) + Math.abs(p.y - grab.pressAt.y) < 8) return
                                grab.moved = true
                                tile.startDrag(p)
                            }
                            tile.pointer = p
                            overview.dragMoved(p)
                        }
                        onReleased: if (tile.dragging) overview.dropped(tile)
                        onCanceled: {
                            if (!tile.dragging) return
                            overview.dropKey = overview.noCard
                            overview.draggingKey = ""
                            overview.endDrag()
                            tile.settle()
                        }
                        onClicked: if (!grab.moved) overview.chooseWindow(tile.key)
                    }

                    HoverHandler {
                        onHoveredChanged: if (hovered && overview.pointerSteers && overview.spread
                                                  && overview.draggingKey === "" && !tile.going)
                                              overview.selectedKey = tile.key
                    }

                    // Caption for the chosen window only: one label reads, one under
                    // every window is a wall of text.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 14
                        readonly property real most: Math.max(tile.width + 60, 180)
                        width: Math.min(captionRow.implicitWidth + 24, most)
                        height: 28
                        radius: height / 2
                        color: Theme.surface
                        // Only once landed: in flight it trailed under the window
                        // and crossed the key hints.
                        opacity: tile.chosen && overview.spread && !tile.dragging && !tile.sendTo && !motion.running ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overview.chooseWindow(tile.key)
                        }

                        Row {
                            id: captionRow
                            anchors.centerIn: parent
                            spacing: 8

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 16
                                mipmap: true
                                source: tile.d ? overview.iconFor(tile.d.cls) : ""
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, parent.parent.most - 24 - 24)
                                text: tile.d ? tile.d.title : ""
                                color: Theme.textPrimary
                                font.pixelSize: 12
                                font.family: Theme.fontText
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // A window carried from another screen: the part past that screen's edge, drawn here
            // at the same scale. Dropped here, it flies into the card under it, or fades in
            // place while the window turns up here.
            Item {
                id: ghost

                // What is carried; kept after the drop, for the landing.
                property var held: null
                property bool landing: false
                property real fade: 0

                readonly property real carryScale: ghost.held ? Math.min(1, 320 / Math.max(1, ghost.held.w)) : 1
                readonly property real miniScale: {
                    var it = overview.thumbs[overview.dropKey]
                    var c = overview.cardData[overview.dropKey]
                    if (!ghost.held || !it || !c) return ghost.carryScale
                    var w = it.picture.width * ghost.held.homeW / c.geom.w
                    return Math.max(0.04, Math.min(ghost.carryScale, w / Math.max(1, ghost.held.w)))
                }
                readonly property real scaleNow: overview.dropKey !== overview.noCard ? ghost.miniScale : ghost.carryScale
                property real carry: ghost.scaleNow
                Behavior on carry { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
                onCarryChanged: ghost.follow()

                z: 2000
                visible: ghost.held !== null && (overview.hosting || ghost.landing)
                opacity: 1 - ghost.fade

                // Here rather than on the overview, so nothing calls into it before
                // it exists or after it's gone.
                Connections {
                    target: overview
                    function onVisitorChanged() {
                        if (overview.visitor) ghost.take(overview.visitor)
                        else ghost.release()
                        overview.aimVisitor()
                    }
                    function onVisitorAtChanged() {
                        overview.aimVisitor()
                        ghost.follow()
                    }
                    function onHostingChanged() { overview.aimVisitor() }
                }

                function take(d) {
                    landAnim.stop()
                    handOverAnim.stop()
                    arrivalGuard.stop()
                    ghost.landing = false
                    ghost.fade = 0
                    ghost.held = d
                    ghost.follow()
                }

                // The drag is over: gone, unless it was let go here.
                function release() {
                    if (!ghost.landing) ghost.held = null
                }

                function follow() {
                    if (!ghost.held || ghost.landing) return
                    var w = ghost.held.w * ghost.carry, h = ghost.held.h * ghost.carry
                    ghost.x = overview.visitorAt.x - ghost.held.fx * w
                    ghost.y = overview.visitorAt.y - ghost.held.fy * h
                    ghost.width = w
                    ghost.height = h
                }

                function land(key) {
                    if (!ghost.held || !overview.hosting) return
                    ghost.landing = true
                    var it = overview.thumbs[key]
                    var c = overview.cardData[key]
                    if (it && c) {
                        var pic = it.picture
                        var at = pic.mapToItem(tilesLayer, 0, 0)
                        var w = Math.max(8, pic.width * ghost.held.homeW / c.geom.w)
                        var h = Math.max(6, pic.height * ghost.held.homeH / c.geom.h)
                        lx.to = at.x + (pic.width - w) / 2
                        ly.to = at.y + (pic.height - h) / 2
                        lw.to = w
                        lh.to = h
                        landAnim.restart()
                        return
                    }
                    // Over this screen's windows: wait where dropped; the window's tile sets
                    // off from here when it appears.
                    overview.arrivals[ghost.held.address] = Qt.rect(ghost.x, ghost.y, ghost.width, ghost.height)
                    arrivalGuard.restart()
                }

                // The window's tile has taken over, or the window never came.
                function handOver() {
                    if (!ghost.held || handOverAnim.running) return
                    arrivalGuard.stop()
                    handOverAnim.restart()
                }

                Timer {
                    id: arrivalGuard
                    interval: 1500
                    onTriggered: ghost.handOver()
                }

                NumberAnimation {
                    id: handOverAnim
                    target: ghost; property: "fade"; to: 1
                    duration: Theme.durShort; easing.type: Easing.OutQuad
                    onFinished: {
                        ghost.landing = false
                        ghost.held = null
                        ghost.fade = 0
                    }
                }

                ParallelAnimation {
                    id: landAnim
                    NumberAnimation { id: lx; target: ghost; property: "x"; duration: Theme.durLong; easing.type: Easing.OutCubic }
                    NumberAnimation { id: ly; target: ghost; property: "y"; duration: Theme.durLong; easing.type: Easing.OutCubic }
                    NumberAnimation { id: lw; target: ghost; property: "width"; duration: Theme.durLong; easing.type: Easing.OutCubic }
                    NumberAnimation { id: lh; target: ghost; property: "height"; duration: Theme.durLong; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ghost; property: "fade"; from: 0; to: 1; duration: Theme.durLong; easing.type: Easing.InQuad }
                    onFinished: {
                        ghost.landing = false
                        ghost.held = null
                        ghost.fade = 0
                    }
                }

                RectangularShadow {
                    anchors.fill: parent
                    radius: ghostFace.radius
                    blur: 30
                    offset.y: 10
                    color: Theme.alpha(Theme.shadow, 0.45)
                    opacity: ghost.landing ? 0 : 1
                }

                ClippingRectangle {
                    id: ghostFace
                    anchors.fill: parent
                    radius: ghost.landing ? Theme.radiusSmall : Theme.radiusLarge
                    color: Theme.surfaceContainerHigh

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 40
                        mipmap: true
                        visible: !ghostShot.hasContent
                        source: ghost.held ? overview.iconFor(ghost.held.cls) : ""
                    }

                    // Taken as the drag starts, so it's ready when the window crosses the edge.
                    ScreencopyView {
                        id: ghostShot
                        anchors.fill: parent
                        captureSource: ghost.held ? ghost.held.toplevel.wayland : null
                        live: false
                    }
                }
            }
        }

        // The "Remove workspace N?" question, under its picture, asked only when it has windows.
        RectangularShadow {
            anchors.fill: confirmCard
            radius: confirmCard.radius
            blur: 30
            offset.y: 8
            color: Theme.alpha(Theme.shadow, 0.45)
            opacity: confirmCard.opacity
            visible: confirmCard.visible
        }

        Rectangle {
            id: confirmCard

            readonly property var card: {
                overview.revision
                return overview.confirmId > -2 ? overview.cardData[overview.confirmId] || null : null
            }
            readonly property point anchorPoint: {
                overview.revision
                var it = confirmCard.card ? overview.thumbs[confirmCard.card.key] : null
                if (!it) return Qt.point(stage.width / 2, overview.area.y)
                var f = it.picture
                return f.mapToItem(stage, f.width / 2, f.height + overview.chipGap + overview.chipHeight)
            }

            x: Math.round(Math.max(16, Math.min(stage.width - width - 16, anchorPoint.x - width / 2)))
            y: Math.round(anchorPoint.y + 16)
            width: confirmCol.implicitWidth + 40
            height: confirmCol.implicitHeight + 32
            radius: Theme.radiusLarge
            color: Theme.surface
            opacity: confirmCard.card ? 1 : 0
            visible: opacity > 0
            scale: confirmCard.card ? 1 : 0.96

            Behavior on opacity { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad } }
            Behavior on scale { Elastic { small: true } }

            // Its own clicks: a click on it is not one on the backdrop.
            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: confirmCol
                anchors.centerIn: parent
                spacing: 12

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: confirmCard.card ? "Remove workspace " + confirmCard.card.name + "?" : ""
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.bold: true
                        font.family: Theme.fontText
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property int n: confirmCard.card ? confirmCard.card.windows.length : 0
                        text: n === 1 ? "Its window will be closed." : "Its " + n + " windows will be closed."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontText
                    }
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

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

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
                                    if (btn.modelData.danger) overview.removeWorkspace(confirmCard.card, true)
                                    else overview.confirmId = -2
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
