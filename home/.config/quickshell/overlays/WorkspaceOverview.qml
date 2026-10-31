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

// The workspace overview (Super+Tab), on the screen it was opened on.
//
// The windows of the workspace on screen leave their places and spread out,
// side by side and none over another, so each can be seen whole and picked.
// Across the top runs a strip with a picture of every workspace -- the
// wallpaper and its windows where they sit -- grouped by monitor, each with
// its own block of ten numbered 1-10 the way Super+N counts them
// (hyprland.lua: DP-2 has 1-10, HDMI-A-1 11-20; 13 shows as 3). Closing
// sends every window back to its place, so a picture and the window it
// stood for never come apart.
//
//   click a window              go to it
//   drag a window onto a        move it there and close; the workspace on
//   workspace in the strip      screen stays. Onto a monitor's New, a new
//                               workspace is made for it and gone to
//   click a workspace           go there; its × removes it (asks first when
//                               it has windows)
//   arrows / Tab, Enter         choose a window, go to it
//   Ctrl + ← →                  show the workspace before or after, here,
//                               without closing
//   1 - 9, 0                    go to that workspace of this monitor
//   Shift + 1 - 9, 0            move the chosen window there and close,
//                               going along when the workspace is a new
//                               one; Shift + N, to a new workspace
//   N                           a new workspace on this monitor
//   Delete                      remove the workspace on screen
//   Esc, or Super+Tab           close
//
// Same house pattern as the launcher: mapped only while up, exclusive
// keyboard while up, pinned to the screen it opened on. The keyboard grab is
// held while the windows fly home (changing it while the surface is up
// drops it for two frames -- see AppLauncher), and let go at once when the
// overview closes to go to another workspace, so the window gone to gets
// the keyboard.
//
// Cheap while it is not up: nothing is captured, the models are empty and
// their views destroyed. While up, each window is captured when its view is
// built, and again only when its size changes; nothing is streamed.
//
// The clickable things are MouseAreas, not TapHandlers: a TapHandler's grab
// is passive, so a click on a workspace's × was also a click on the
// workspace under it, which went there before the × could do anything.
PanelWindow {
    id: overview

    property var bar: null
    screen: bar.screen

    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (Panels.overviewScreen === "") return bar.monitor.focused
        return bar.monitor.name === Panels.overviewScreen
    }

    readonly property bool open: Panels.overviewOpen && overview.onOpeningScreen

    // Mapped from opening until the windows are home (see AppLauncher's
    // `shown` for why this is not `open || timer.running`).
    property bool shown: false
    // Closing to go to another workspace: hidden at once, keyboard let go at
    // once.
    property bool leaving: false
    // Set while everything comes in, so the windows leave from where they
    // are on screen and the strip does not animate its sizes while it fills.
    property bool opening: false
    // The windows are out of their places: from opening until the overview
    // starts to close, when each heads back to where it is on screen.
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
            overview.selectedKey = ""
            // Whatever was waiting for the windows to land: focusing the
            // one picked, now that the keyboard is free to go to it.
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
                overview.leaving = false
                overview.pending = null
                overview.confirmId = -2
                overview.dropKey = overview.noCard
                overview.draggingKey = ""
                overview.pointerSteers = false
                overview.lastPointer = Qt.point(-1, -1)
                overview.opening = true
                openingDone.restart()
                overview.shown = true
                roundingProc.running = true
                overview.refresh()
                overview.rebuild()
                overview.selectedKey = overview.mostRecent()
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

    // Hyprland's corner rounding, so a window leaves and lands with the
    // corners it has on screen. Asked on every opening -- it is a setting
    // (Settings -> Look) -- with the last answer kept meanwhile.
    property int windowRounding: Theme.radiusXLarge

    Process {
        id: roundingProc
        command: ["hyprctl", "getoption", "decoration:rounding", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var v = JSON.parse(text).int
                    if (typeof v === "number" && v >= 0) overview.windowRounding = v
                } catch (e) {}
            }
        }
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

    // The workspace this screen shows: the one whose windows are spread out.
    // (Hyprland.focusedWorkspace is only known once an event has named it;
    // the monitor's is what the bar's pill reads too.)
    function viewedId() {
        return bar.monitor && bar.monitor.activeWorkspace ? bar.monitor.activeWorkspace.id : -1
    }

    // Snapshots, not bindings: rebuilt on opening and when Hyprland says
    // something moved. A binding re-read every window title as it changed,
    // and re-captured every window each time.
    //
    // Cards are the strip's workspaces, keyed by workspace id (each
    // monitor's new one by -100 - its block); tiles are the windows spread
    // out, keyed by address. A key that leaves stays in its model, on its
    // way out, until goneTimer takes it.
    property var cardData: ({})
    property var cardList: []
    property var goingCards: []
    property var tileData: ({})
    property var tileList: []
    property var goingTiles: []
    // Where each tile sits while spread out, by address.
    property var slots: ({})
    property int revision: 0
    property bool several: false

    ListModel { id: cardModel }
    ListModel { id: tileModel }

    function computeCards() {
        var viewed = overview.viewedId()
        var wss = Hyprland.workspaces.values.filter(function(w) { return w.id > 0 })
        // Grouped by monitor, left to right as they stand, and by number
        // within each: a workspace lives on one monitor, and the strip says so.
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
            // Tiled under floating, and within each the most recently used on
            // top -- the order they are stacked on screen.
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
                         monitor: out[j].monitor, monitorLabel: "", viewed: false, active: false,
                         windows: [], isNew: true })
        }
        // Where each monitor's run starts and ends: the first card gets the
        // monitor's name over it, the last a wider gap after it; the very
        // last none.
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

    // The windows of the workspace on screen, each with where it is on it
    // (`home`, in this window's coordinates: the overview covers the monitor
    // exactly, so a window's place on screen is its place here).
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

    // The card that stands for a workspace id: the workspace itself, or the
    // new card that would make it.
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

    // "Samsung Odyssey G40B" for "Samsung Electric Company Odyssey G40B".
    function monitorLabel(monitor) {
        var o = monitor ? monitor.lastIpcObject : null
        var d = o && o.description ? o.description : (monitor ? monitor.name : "")
        return d.replace(/ (Electric Company|Corporation|Technologies|Technology|Inc\.?|Co\.?,? ?Ltd\.?)/g, "")
    }

    function iconFor(cls) {
        var e = DesktopEntries.heuristicLookup(cls)
        return Quickshell.iconPath(e ? e.icon : String(cls).toLowerCase(), "application-x-executable")
    }

    // What a card or a tile shows, as a string: two builds that agree on it
    // keep the first object, so its views are not rebuilt and re-captured.
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

    // Adds the keys a model lacks, each where it belongs among those
    // staying, so a view that stays keeps its delegate (and its capture).
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

        // The data first, then the models: a delegate made by the insert
        // reads its data as it is made.
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
            overview.selectedKey = overview.mostRecent()
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

    // ── Laying the windows out ───────────────────────────────────────────
    //
    // Between the strip and the key hints, the windows in rows, each keeping
    // its shape and the size it has next to the others. Every row count
    // from one to one per window is tried, windows going into rows by where
    // they sit on screen (top to bottom, then left to right), and the count
    // that lets them be biggest wins; one with fewer rows wins a near tie,
    // since a row reads more easily than a grid. A window is never shown
    // above `maxWindowScale` of its size, so a workspace with one window
    // still visibly steps back from the screen.
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

    // ── The strip's size ─────────────────────────────────────────────────

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

    // Every picture as high as the others and as wide as its monitor is for
    // that height, small enough for the strip to fit across the screen.
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
    // Eased when a workspace comes or goes, so the strip grows and shrinks
    // rather than snapping; not while it first fills.
    property real shownThumb: overview.thumbHeight
    Behavior on shownThumb {
        enabled: !overview.opening
        Elastic {}
    }

    // ── Choosing ─────────────────────────────────────────────────────────

    // The window the keyboard is on, by address.
    property string selectedKey: ""

    // Whether the pointer has moved since the overview opened. Only then
    // does hovering pick a window: opening under a pointer that sat still
    // put the selection on whichever window came out beneath it.
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

    // The nearest window in a direction, by where they sit spread out:
    // straight ahead counts more than off to the side.
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

    // ── Dragging ─────────────────────────────────────────────────────────

    readonly property int noCard: -999
    // The card under a window being dragged; the strip lights it.
    property int dropKey: overview.noCard
    property string draggingKey: ""

    // The strip's cards and the tiles, by key, as their delegates register
    // themselves: where a dragged window is let go, and what flies there.
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

    function dragMoved(p) {
        overview.dropKey = overview.cardKeyAt(p)
    }

    // Let go over a workspace other than this one: the window goes there and
    // the tile into its picture. Anywhere else, the tile goes back.
    function dropped(tile) {
        var key = overview.dropKey
        overview.dropKey = overview.noCard
        overview.draggingKey = ""
        var card = overview.cardData[key]
        if (card && tile.d && overview.goingCards.indexOf(key) === -1 && card.id !== overview.viewedId()) {
            tile.sendInto(overview.thumbs[key] ? overview.thumbs[key].picture : null, card.geom)
            overview.moveWindow(tile.d.address, card.id)
            overview.afterMove(tile.d.address, card.isNew)
        } else {
            tile.settle()
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

    // A window moved is the end of the visit: the overview closes once the
    // window has landed in its picture. Into a workspace that was already
    // there, the rest fly home to the places Hyprland has retiled them into
    // meanwhile and the workspace on screen stays. Into a new one, made for
    // it, the window is gone to: the overview closes the quick way and
    // focusing the window takes Hyprland to its workspace.
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

    // Closes the slow way, every window flying home, and does `what` once
    // they have landed and the surface is gone.
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

    // The workspace on screen is the one the windows fly back into; any
    // other is gone to the quick way, letting Hyprland's own animation play.
    function goToWorkspace(id) {
        if (id === overview.viewedId()) {
            overview.close()
            return
        }
        overview.leaveThen(function() { overview.run("hl.dispatch(hl.dsp.focus({ workspace = " + id + " }))") })
    }

    function chooseWindow(key) {
        var t = overview.tileData[key]
        if (!t) return
        overview.selectedKey = key
        overview.dismissThen(function() {
            overview.run("hl.dispatch(hl.dsp.focus({ window = 'address:0x" + t.address + "' }))")
        })
    }

    // The workspace before or after this one on this monitor, shown here
    // without closing: the monitor really switches, behind the overview, so
    // closing lands the windows where they now are.
    function viewWorkspace(delta) {
        var name = bar.monitor ? bar.monitor.name : ""
        var mine = overview.cardList.filter(function(c) { return !c.isNew && c.monitor === name })
        var at = -1
        for (var i = 0; i < mine.length; i++) if (mine[i].viewed) at = i
        var next = mine[at + delta]
        if (at < 0 || !next) return
        overview.run("hl.get_monitor(" + overview.luaString(name) + "):set_workspace({ workspace = " + next.id + " })")
    }

    // Without following it: the workspace on screen stays.
    function moveWindow(address, id) {
        overview.run("hl.dispatch(hl.dsp.window.move({ workspace = " + id
                     + ", follow = false, window = 'address:0x" + address + "' }))")
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

    // ── Drawing ──────────────────────────────────────────────────────────

    // How much of the backdrop is up. Driven by hand rather than by a
    // Behavior, because it comes in and goes out on different curves: in
    // quickly, out over the windows' whole flight home and late, so the real
    // windows show through only as the pictures land on them.
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
        // Going to another workspace: gone at once, for Hyprland's own
        // animation to show.
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

        // Keyboard.
        Item {
            id: keys
            focus: true

            // The number row by position, not by symbol: with Shift held the
            // key is whatever the layout puts over the digit ("!" on US,
            // "!" to "=" on the Latin American one), while its scan code is
            // the same everywhere. xkb codes are evdev's plus 8, so 1-9 are
            // 10-18 and 0 is 19.
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

        // The desktop the windows came off: the wallpaper, dimmed, with the
        // real windows hidden under it. Opaque, so the bar and every window
        // behind are gone while it is up, and the only windows on screen are
        // the pictures; a plain fill under the image covers the moment it
        // takes to load.
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

        // ── The strip ────────────────────────────────────────────────────

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

            // A plain row: it always knows where its cards are. (A ListView
            // here, with its transitions and a sliding highlight, lost track
            // when the cards changed width as one came or went.)
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
                        // What a dragged window is measured against and
                        // flies into.
                        readonly property Item picture: face

                        // Each card carries the gap after it (the last has
                        // none), and hands over its whole width as it goes
                        // -- or takes it as it comes -- so the strip closes up
                        // and opens out smoothly instead of jumping.
                        readonly property real faceWidth: Math.round(overview.shownThumb * card.geom.w / card.geom.h)
                        property real grow: 1
                        width: Math.round((card.faceWidth + (card.d.last ? 0
                                           : card.d.groupEnd ? overview.groupSpacing : overview.thumbSpacing)) * card.grow)
                        height: overview.shownThumb + overview.chipGap + overview.chipHeight

                        opacity: 0
                        scale: 0.9

                        // Set once, not bound: a card that arrives after the
                        // strip has filled grows in from nothing.
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

                        // Lifts a little under the pointer, and more under a
                        // window held over it.
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

                            // The new card's outline, dashed: a place for a
                            // workspace, not one yet.
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

                            // A click anywhere on the card that nothing on it
                            // takes: go to that workspace. First, so the ×
                            // above it gets its click first.
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

                                        // Clamped to the card: a window partly
                                        // off its monitor stays inside the picture.
                                        x: whole ? 0 : Math.max(0, Math.min(parent.width - width,
                                                                             Math.round((win.modelData.x - card.geom.x) * sx)))
                                        y: whole ? 0 : Math.max(0, Math.min(parent.height - height,
                                                                             Math.round((win.modelData.y - card.geom.y) * sy)))
                                        width: whole ? parent.width : Math.min(parent.width, Math.max(10, Math.round(win.modelData.w * sx)))
                                        height: whole ? parent.height : Math.min(parent.height, Math.max(8, Math.round(win.modelData.h * sy)))
                                        // Fades in when its capture has arrived,
                                        // rather than popping in over a blank.
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

                                        // Its app, over the middle, where
                                        // there is room for it.
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

                            // Remove the workspace. Last, so it is on top of
                            // everything the card holds and takes its click.
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

                        // The number, filled in the accent on the workspace
                        // whose windows are out.
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

        // The keys, on a surface of their own: the wallpaper under them can
        // be any brightness.
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

        // ── The windows ──────────────────────────────────────────────────
        //
        // Over the strip, so one dragged up there passes over it.
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

                    // Out of its place: off on opening, a beat after the
                    // tile is made where the window is, so it has somewhere
                    // to leave from.
                    property bool launched: false
                    // Moves are animated; off while it follows the pointer.
                    property bool animate: true
                    property bool dragging: false
                    // The picture in the strip it is flying into, once it has
                    // been sent to another workspace.
                    property var sendTo: null
                    property real sent: 0
                    property real appear: 0
                    // Grows in where it is (a window that turns up while the
                    // overview is up), rather than flying out of its place.
                    property bool popIn: true
                    property point pointer: Qt.point(0, 0)
                    // Where on it it was picked up, so that point stays under
                    // the pointer however small it is carried.
                    property real grabFx: 0.5
                    property real grabFy: 0.5

                    // Carried at most this wide, so it can be aimed; over a
                    // workspace, the size it would be in that picture.
                    readonly property real carryScale: Math.min(1, 320 / Math.max(1, tile.slot.width))
                    readonly property real miniScale: {
                        var it = overview.thumbs[overview.dropKey]
                        var c = overview.cardData[overview.dropKey]
                        if (!it || !c || !tile.d) return tile.carryScale
                        var w = it.picture.width * tile.d.home.width / c.geom.w
                        return Math.max(0.04, Math.min(tile.carryScale, w / Math.max(1, tile.slot.width)))
                    }
                    property real carry: tile.dragging ? (overview.dropKey !== overview.noCard ? tile.miniScale : tile.carryScale) : 1
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

                    // By hand, not with Behaviors, so each move picks its
                    // curve from where it is headed, read after the change:
                    // out to its place on the soft spring, home and into the
                    // strip on a plain ease, under the pointer with none.
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
                    }

                    // Back to its place.
                    function settle() {
                        tile.animate = true
                        tile.dragging = false
                    }

                    // Into a workspace's picture in the strip, fading as it
                    // lands; with no picture to aim at (a workspace the strip
                    // does not show yet), up towards the strip.
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

                    z: tile.dragging ? 1000 : (tile.d ? tile.d.order : 0)
                    opacity: tile.appear * tile.presence * (1 - tile.sent)

                    // Fades out over the flight home, late, so the window
                    // under it takes over as it lands.
                    property real presence: overview.spread ? 1 : 0
                    Behavior on presence { NumberAnimation { duration: Theme.durLong; easing.type: Easing.InQuad } }

                    transform: Scale {
                        origin.x: tile.width / 2
                        origin.y: tile.height / 2
                        xScale: tile.popIn ? 0.92 + 0.08 * tile.appear : 1
                        yScale: tile.popIn ? 0.92 + 0.08 * tile.appear : 1
                    }

                    // Put where it starts without a move: at its place on
                    // screen when the overview is opening, at its place in
                    // the layout when it turns up later.
                    Component.onCompleted: {
                        overview.tileItems[tile.key] = tile
                        tile.capturedSize = tile.sizeKey
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

                    // Quick when it leaves its place, so the picture is solid
                    // before the backdrop has hidden the window under it.
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

                    // A move Hyprland did not make: the window is still here,
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

                    // A capture is a still, taken once; when the window
                    // changes shape -- the others retiling after one has left
                    // -- it is taken again once Hyprland's own animation has
                    // had time to finish, instead of stretching the old one.
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

                    // Lifted off the desktop while out; on the way home the
                    // window's own shadow takes over.
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
                        // The window's own corners at home, the overlay's
                        // card corners while out.
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
                            tile.settle()
                        }
                        onClicked: if (!grab.moved) overview.chooseWindow(tile.key)
                    }

                    HoverHandler {
                        onHoveredChanged: if (hovered && overview.pointerSteers && overview.spread
                                                  && overview.draggingKey === "" && !tile.going)
                                              overview.selectedKey = tile.key
                    }

                    // Its name, under it, for the chosen window only: one
                    // label at a time reads, a label under every window is a
                    // wall of text.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 14
                        readonly property real most: Math.max(tile.width + 60, 180)
                        width: Math.min(captionRow.implicitWidth + 24, most)
                        height: 28
                        radius: height / 2
                        color: Theme.surface
                        // Once the window has landed: in flight it trailed
                        // under it and crossed the key hints.
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
        }

        // "Remove workspace N?" -- the one question asked before a workspace
        // with windows goes, under its picture.
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
