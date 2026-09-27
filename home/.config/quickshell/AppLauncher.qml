import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// The launcher, opened from the bind the config points at
// "quickshell:launcher" (Super+Space). Replaces `rofi -show drun`.
//
// Shaped after macOS Spotlight by request, which is why the names are in SF
// Pro rather than the mono face the bar uses, and why it does not dim the
// desktop behind it. The rest is the shell's: the pill glass and its shadow,
// the panels' small uppercase section labels, the mono hints.
//
// It finds more than applications, each kind under its own label:
//   Frequent      on an empty field, what you open most (LauncherHistory)
//   Applications  ranked by how well the name matches, then by use
//   Windows       open windows, to switch to (focus follows to its workspace)
//   Settings      the shell's Settings pages, by name or by what is on them
//   Actions       lock, suspend, wallpapers, keybinds, notifications
//   Calculator    "12*7" or "=2^10": the result, Enter copies it
//   Web           the query in the browser, always last
// The kinds come in the order of their best match, so "disp" puts the
// Displays page above an application that only mentions displays.
//
// Structurally the house pattern -- mapped only while open, exclusive
// keyboard focus while open, pinned to the screen it was summoned on.
PanelWindow {
    id: overlay

    property var bar: null
    screen: bar.screen

    // One copy per monitor and only the one it was opened on shows. Focus
    // follows the mouse here, so matching against live focus would drag the
    // launcher to whichever screen the pointer wandered onto.
    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (AppState.launcherScreen === "") return bar.monitor.focused
        return bar.monitor.name === AppState.launcherScreen
    }

    readonly property bool open: AppState.launcherOpen && overlay.onOpeningScreen

    // Unmapped while closed, not merely drawn empty: a mapped full-screen
    // layer is composited every frame whether or not it draws anything.
    // `shown` keeps it mapped until the fade out has played, and is the only
    // thing `visible` reads. It read `open || unmapDelay.running`, and
    // between `open` going false and the handler starting the timer that
    // was false: the launcher unmapped, came back, and only then faded --
    // a two-frame blink that looked like no animation at all.
    // Connections rather than an `onOpenChanged` here: the root already has
    // one, and a second on the same object is an error.
    property bool shown: false
    visible: overlay.shown

    Timer {
        id: unmapDelay
        interval: 170 + 60
        onTriggered: overlay.shown = false
    }

    Connections {
        target: overlay
        function onOpenChanged() {
            if (overlay.open) {
                unmapDelay.stop()
                overlay.shown = true
            } else {
                unmapDelay.restart()
            }
        }
    }

    color: "transparent"

    WlrLayershell.namespace: "quickshell:launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Held through the fade out when dismissed, let go at once when
    // something is launched. Changing it mid-fade drops the surface for two
    // frames -- the panel blinked out and came back before fading -- so a
    // dismissal keeps it until the end. A launch cannot: the new window has
    // to get the keyboard, so the panel hides at once instead (`launching`)
    // and there is nothing left on screen to blink.
    WlrLayershell.keyboardFocus: overlay.open || (overlay.shown && !overlay.launching)
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property bool launching: false

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

    // ── Pieces ───────────────────────────────────────────────────────────

    // A section's name over its rows: the panels' label (StatusWidget's
    // PanelLabel), so the launcher reads as part of the same shell.
    component SectionLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
        font.family: Theme.fontMono
    }

    // A key and what it does, for the footer.
    component KeyHint: Row {
        id: hint
        property string key: ""
        property string label: ""
        spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(18, keyText.implicitWidth + 10)
            height: 18
            radius: 5
            color: Theme.surfaceContainer
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
            font.family: Theme.fontMono
        }
    }

    // ── Type ─────────────────────────────────────────────────────────────
    //
    // Spotlight is a proportional-set panel and reads wrong in a monospace --
    // the names are the content here, not tabular data. Display is the
    // optical size cut for the large field, Text for the rows.
    readonly property string fontDisplay: "SF Pro Display"
    readonly property string fontText: "SF Pro Text"

    // ── Geometry ─────────────────────────────────────────────────────────
    readonly property int cardWidth: 680
    readonly property int searchHeight: 62
    readonly property int rowHeight: 46
    readonly property int headerHeight: 28
    readonly property int maxListHeight: 440
    readonly property int listPad: 6
    readonly property int footerHeight: 36

    readonly property bool hasResults: overlay.results.length > 0

    // Every row, and a label over the first of each section.
    readonly property int contentHeight: {
        var h = 0
        for (var i = 0; i < overlay.results.length; i++)
            h += overlay.rowHeight + (overlay.startsSection(i) ? overlay.headerHeight : 0)
        return h
    }

    readonly property int listHeight: Math.min(overlay.contentHeight, overlay.maxListHeight)

    // Just the field when nothing matches, the way Spotlight collapses to it.
    readonly property int cardHeight: overlay.searchHeight
        + (overlay.hasResults
           ? 1 + overlay.listPad * 2 + overlay.listHeight + 1 + overlay.footerHeight
           : 0)

    // Spotlight sits high rather than centred, and the field stays put while
    // the list grows and shrinks underneath it.
    readonly property int cardTop: Math.round(overlay.height * 0.22)

    function startsSection(i) {
        return i === 0 || overlay.results[i - 1].section !== overlay.results[i].section
    }

    // ── State ────────────────────────────────────────────────────────────
    property string query: ""
    property int selected: 0

    readonly property string q: overlay.query.trim().toLowerCase()

    // ── What there is to find ────────────────────────────────────────────

    // The Settings pages (SettingsView's nav), with the words someone would
    // type looking for what is on them -- in English and in Spanish, since
    // the desktop entries are Spanish and the shell is English.
    readonly property var settingsPages: [
        { id: "displays", name: "Displays", glyph: "\u{F037A}",
          keywords: ["monitor", "screen", "resolution", "refresh", "hz", "scale", "vrr", "pantalla", "resolucion"] },
        { id: "colour", name: "Colour", glyph: "\u{F03D8}",
          keywords: ["color", "gamma", "temperature", "night", "vibrance", "brightness", "brillo", "noche"] },
        { id: "keyboard", name: "Keyboard", glyph: "\u{F030C}",
          keywords: ["rgb", "wooting", "lights", "openrgb", "teclado", "luces"] },
        { id: "sound", name: "Sound", glyph: "\u{F057E}",
          keywords: ["audio", "volume", "output", "input", "microphone", "sonido", "volumen", "microfono"] },
        { id: "look", name: "Look", glyph: "\u{F05B2}",
          keywords: ["gaps", "border", "rounding", "blur", "animation", "apariencia", "bordes"] },
        { id: "input", name: "Input", glyph: "\u{F037D}",
          keywords: ["mouse", "sensitivity", "touchpad", "cursor", "raton", "sensibilidad"] },
        { id: "profile", name: "Profile", glyph: "\u{F0004}",
          keywords: ["avatar", "picture", "photo", "user", "perfil", "foto"] },
        { id: "shell", name: "Shell", glyph: "\u{F10AC}",
          keywords: ["bar", "clock", "lock", "backup", "barra", "reloj"] },
        { id: "power", name: "Power & idle", glyph: "\u{F0241}",
          keywords: ["idle", "suspend", "sleep", "power", "energia", "suspender"] },
        { id: "about", name: "About", glyph: "\u{F02FD}",
          keywords: ["system", "version", "info", "sistema", "acerca"] }
    ]

    readonly property var actions: [
        { id: "lock", name: "Lock screen", glyph: "\u{F033E}",
          keywords: ["lock", "bloquear"], run: function() { AppState.lockSession() } },
        { id: "suspend", name: "Suspend", glyph: "\u{F04B2}",
          keywords: ["sleep", "suspend", "suspender", "dormir"], run: function() { AppState.suspendSession() } },
        { id: "wallpapers", name: "Wallpapers", glyph: "\u{F02E9}",
          keywords: ["wallpaper", "background", "fondo", "fondos"], run: function() { AppState.toggleWallpapers() } },
        { id: "keybinds", name: "Keybinds", glyph: "\u{F030C}",
          keywords: ["shortcuts", "keys", "atajos", "teclas"], run: function() { AppState.toggleKeybinds() } },
        { id: "notifications", name: "Notifications", glyph: "\u{F009A}",
          keywords: ["notifications", "notificaciones"],
          run: function() { AppState.notificationsRequested("open", AppState.launcherScreen) } },
        { id: "settings", name: "Settings", glyph: "\u{F0493}",
          keywords: ["preferences", "ajustes", "configuracion"],
          run: function() { AppState.openSettings("", AppState.launcherScreen) } }
    ]

    // An arithmetic expression, or null. Only digits, operators, brackets
    // and spaces get anywhere near evaluation, and it must have an operator
    // -- a bare number is a search, not a sum.
    function calculate(text) {
        var t = text.trim().replace(/^=/, "")
        if (!/^[\d\s+\-*/().,%^x×÷]+$/.test(t)) return null
        if (!/\d/.test(t) || !/\d\s*[+\-*/%^x×÷]\s*[\d(.]/.test(t)) return null
        var expr = t.replace(/,/g, ".").replace(/[x×]/g, "*").replace(/÷/g, "/").replace(/\^/g, "**")
        try {
            var v = Function('"use strict"; return (' + expr + ')')()
            if (typeof v !== "number" || !isFinite(v)) return null
            return String(Number(v.toPrecision(12)))
        } catch (e) {
            return null
        }
    }

    // ── Ranking ──────────────────────────────────────────────────────────

    // Higher wins; zero drops the item. The tiers are in the order someone
    // would think of them, and each one subtracts a little for length or
    // distance so that within a tier the tighter match comes first. Works on
    // anything with a name, and optionally id, genericName, keywords and
    // comment -- desktop entries have them all, the rest what they can.
    function score(item, q) {
        var name = (item.name || "").toLowerCase()

        if (name === q) return 1000
        if (name.startsWith(q)) return 900 - Math.min(90, name.length)

        // A query that starts a later word: "code" for "Visual Studio Code".
        var words = name.split(/[\s\-_.:&]+/)
        for (var i = 1; i < words.length; i++) {
            if (words[i].startsWith(q)) return 800 - Math.min(90, name.length)
        }

        var at = name.indexOf(q)
        if (at !== -1) return 700 - Math.min(90, at)

        // The desktop id catches the binary a user knows the app by rather
        // than its display name: "nvim" for Neovim, "dolphin" for
        // org.kde.dolphin -- and an English query against Spanish entries.
        if ((item.id || "").toLowerCase().indexOf(q) !== -1) return 600

        // genericName is the curated "what this is" line and beats keywords,
        // which are a grab bag: the other way round, "term" put a text editor
        // that keywords itself "terminal" above both installed terminals.
        if ((item.genericName || "").toLowerCase().indexOf(q) !== -1) return 500

        var kw = item.keywords || []
        for (var k = 0; k < kw.length; k++) {
            if (kw[k].toLowerCase().indexOf(q) !== -1) return 450
        }
        if ((item.comment || "").toLowerCase().indexOf(q) !== -1) return 400

        // Last resort: the letters in order but not adjacent -- "gmp" for
        // Gimp, and a typo landing somewhere instead of on an empty list.
        return overlay.subsequenceScore(name, q)
    }

    // How tightly the letters of q are packed where they appear in order in
    // text. Zero when they are not all there, and zero when they are strewn:
    // without that ceiling "code" came back with the Avahi Zeroconf browser.
    function subsequenceScore(text, q) {
        if (q.length < 3) return 0

        var at = 0
        var first = -1
        var last = -1

        for (var i = 0; i < q.length; i++) {
            var found = text.indexOf(q[i], at)
            if (found === -1) return 0
            if (first === -1) first = found
            last = found
            at = found + 1
        }

        var slack = (last - first + 1) - q.length
        if (slack > Math.max(4, q.length)) return 0

        return Math.max(1, 300 - slack * 8 - Math.min(50, first))
    }

    // What you open most, as a nudge inside a tier: up to 90, never enough
    // to lift a looser kind of match over a tighter one.
    function useBonus(id) {
        return Math.min(90, Math.round(LauncherHistory.frecency(id) * 12))
    }

    function appItem(e, section, s) {
        return { kind: "app", section: section, score: s, key: "app:" + e.id,
                 name: e.name, detail: e.genericName || "", icon: e.icon, entry: e }
    }

    function sortByScore(list) {
        list.sort(function(a, b) {
            if (a.score !== b.score) return b.score - a.score
            return a.name.localeCompare(b.name)
        })
        return list
    }

    readonly property var results: {
        // Nothing to rank while unmapped: the copies on the other screens,
        // and this one between uses, would otherwise re-rank on every window
        // title that changes. `visible` and not `open`, so the list stays
        // through the fade out instead of emptying on its first frame.
        if (!overlay.visible) return []

        var apps = DesktopEntries.applications.values.filter(function(e) {
            // NoDisplay is the entry asking not to be listed: mime handlers,
            // per-app settings panels, the halves of a split package.
            return !e.noDisplay
        })
        var q = overlay.q

        // ── Empty: what you use, then everything ──
        if (q.length === 0) {
            var usage = LauncherHistory.usage   // for the binding
            var frequent = []
            var rest = []
            for (var i = 0; i < apps.length; i++) {
                var f = LauncherHistory.frecency(apps[i].id)
                if (f > 0.05) frequent.push(overlay.appItem(apps[i], "Frequent", f))
                else rest.push(overlay.appItem(apps[i], "Applications", 0))
            }
            overlay.sortByScore(frequent)
            // Past six the rest go back among the others, alphabetically.
            rest = rest.concat(frequent.slice(6).map(function(it) {
                return Object.assign({}, it, { section: "Applications", score: 0 })
            }))
            return frequent.slice(0, 6).concat(overlay.sortByScore(rest))
        }

        // ── Typing: every kind, each ranked, the kinds by their best ──
        var groups = []

        var sum = overlay.calculate(overlay.query)
        var calcGroup = sum === null ? [] : [{
            kind: "calc", section: "Calculator", score: 2000, key: "calc",
            name: "= " + sum, value: sum, detail: "Copy to clipboard", glyph: "\u{F00EC}" }]

        var appHits = []
        for (var a = 0; a < apps.length; a++) {
            var s = overlay.score(apps[a], q)
            if (s > 0) appHits.push(overlay.appItem(apps[a], "Applications", s + overlay.useBonus(apps[a].id)))
        }
        // A handful, so the other kinds still show without scrolling; the
        // rest are one more letter away.
        groups.push(overlay.sortByScore(appHits).slice(0, 8))

        var winHits = []
        var tops = Hyprland.toplevels.values
        for (var t = 0; t < tops.length; t++) {
            var o = tops[t].lastIpcObject || {}
            var title = tops[t].title || o.title || ""
            var cls = o.class || ""
            if (title.length === 0 && cls.length === 0) continue
            var owner = cls.length > 0 ? DesktopEntries.heuristicLookup(cls) : null
            var appName = owner ? owner.name : cls
            var ws = tops[t].workspace ? tops[t].workspace.name : ""
            var w = { name: title || appName, id: cls, genericName: appName }
            var ws_ = overlay.score(w, q)
            if (ws_ > 0) winHits.push({
                kind: "window", section: "Windows", score: ws_, key: "win:" + tops[t].address,
                name: w.name, detail: appName + (ws.length > 0 ? "  ·  " + ws : ""),
                icon: owner ? owner.icon : "", address: tops[t].address })
        }
        groups.push(overlay.sortByScore(winHits).slice(0, 6))

        var pageHits = []
        for (var p = 0; p < overlay.settingsPages.length; p++) {
            var pg = overlay.settingsPages[p]
            var ps = overlay.score({ name: pg.name, id: pg.id, keywords: pg.keywords }, q)
            if (ps > 0) pageHits.push({
                kind: "setting", section: "Settings", score: ps, key: "set:" + pg.id,
                name: pg.name, detail: "Settings", glyph: pg.glyph, page: pg.id })
        }
        groups.push(overlay.sortByScore(pageHits).slice(0, 5))

        var actHits = []
        for (var c = 0; c < overlay.actions.length; c++) {
            var ac = overlay.actions[c]
            var as = overlay.score({ name: ac.name, id: ac.id, keywords: ac.keywords }, q)
            if (as > 0) actHits.push({
                kind: "action", section: "Actions", score: as, key: "act:" + ac.id,
                name: ac.name, detail: "", glyph: ac.glyph, run: ac.run })
        }
        groups.push(overlay.sortByScore(actHits).slice(0, 5))

        groups = groups.filter(function(g) { return g.length > 0 })
        groups.sort(function(x, y) { return y[0].score - x[0].score })

        var out = calcGroup
        for (var g = 0; g < groups.length; g++) out = out.concat(groups[g])

        // No calculation to copy: the query as a web search, last.
        if (sum === null) out.push({
            kind: "web", section: "Web", score: 0, key: "web",
            name: "Search the web for “" + overlay.query.trim() + "”",
            detail: "", glyph: "\u{F059F}" })

        return out
    }

    // Every keystroke reorders the list, and the selection has to come back
    // to the top with it -- left where it was it points at whatever happens
    // to be in that slot now.
    onResultsChanged: {
        overlay.selected = 0
        overlay.pointerSteers = false
    }

    // Whether the pointer has moved since the list last changed. Only then
    // does it pick the row: a list rebuilt under a pointer that sat still
    // put the selection on whatever row landed beneath it -- type "ste" with
    // the pointer resting over the fifth row and Enter ran the fifth match.
    property bool pointerSteers: false
    property point lastPointer: Qt.point(-1, -1)

    // The name with the part that matched in bold.
    function highlight(item) {
        var name = item.name || ""
        var esc = function(s) {
            return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        }
        if (overlay.q.length === 0 || item.kind === "calc" || item.kind === "web") return esc(name)
        var at = name.toLowerCase().indexOf(overlay.q)
        if (at === -1) return esc(name)
        return esc(name.slice(0, at)) + "<b>" + esc(name.slice(at, at + overlay.q.length))
             + "</b>" + esc(name.slice(at + overlay.q.length))
    }

    function verb(item) {
        switch (item.kind) {
        case "window": return "Switch"
        case "calc": return "Copy"
        case "web": return "Search"
        case "action": return "Run"
        default: return "Open"
        }
    }

    // ── Running things ───────────────────────────────────────────────────

    function close() {
        AppState.launcherOpen = false
    }

    property var pending: null

    function run(item) {
        if (!item) return
        // Closed first, and at once (see `launching`): the launcher holds
        // the keyboard exclusively while it is up, and a window that maps
        // into that grab comes up without focus.
        overlay.launching = true
        overlay.close()

        switch (item.kind) {
        case "calc":
            Quickshell.execDetached(["wl-copy", item.value])
            return
        case "app":
            overlay.launchedAt = Date.now()
            LauncherHistory.record(item.entry.id)
            // Point the focus at the monitor the pointer is on, so the window
            // opens there: follow_mouse cannot while the grab is held. Then
            // straight away: the dispatch lands in a few ms, and no app maps
            // a window that fast -- it waited 90ms here for nothing.
            AppState.focusCursorMonitor()
            item.entry.execute()
            return
        case "web":
            overlay.launchedAt = Date.now()
            AppState.focusCursorMonitor()
            Quickshell.execDetached(["xdg-open",
                "https://www.google.com/search?q=" + encodeURIComponent(overlay.query.trim())])
            return
        case "window":
            // `hyprctl eval` and not `dispatch`: this Hyprland is configured
            // in Lua (see LockEngine). Focusing follows to its workspace.
            var sel = "address:0x" + item.address
            overlay.pending = function() {
                Quickshell.execDetached(["hyprctl", "eval",
                    "hl.dispatch(hl.dsp.focus({ window = '" + sel + "' }))"])
            }
            break
        case "setting":
            overlay.pending = function() { AppState.openSettings(item.page, AppState.launcherScreen) }
            break
        case "action":
            overlay.pending = item.run
            break
        }
        spawnTimer.restart()
    }

    // ── Following what was launched ──────────────────────────────────────
    //
    // A launch that lands in something already running -- a search handed
    // to the open browser, Discord or Steam asked to come up -- does not map
    // a window: the app asks for its existing one to be activated. That
    // request arrived while this layer was still up, and Hyprland turned it
    // down and only marked the window urgent: the search opened on another
    // workspace and you stayed where you were. So for a few seconds after a
    // launch, the window that turns urgent is the one launched, and it gets
    // focus -- once this layer is gone, or it would be refused again.
    property real launchedAt: 0
    property string urgentAddress: ""

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "urgent" || overlay.launchedAt === 0) return
            if (Date.now() - overlay.launchedAt > 4000) {
                overlay.launchedAt = 0
                return
            }
            overlay.launchedAt = 0
            overlay.urgentAddress = event.data
            overlay.focusUrgent()
        }
    }

    onVisibleChanged: overlay.focusUrgent()

    function focusUrgent() {
        if (overlay.visible || overlay.urgentAddress === "") return
        var sel = "address:0x" + overlay.urgentAddress
        overlay.urgentAddress = ""
        Quickshell.execDetached(["hyprctl", "eval",
            "hl.dispatch(hl.dsp.focus({ window = '" + sel + "' }))"])
    }

    // For what acts on the shell or on a window rather than starting a
    // process: a frame or two, for the launcher's keyboard grab to be let go
    // before focus is asked to move.
    Timer {
        id: spawnTimer
        interval: 30
        onTriggered: {
            if (overlay.pending) {
                var f = overlay.pending
                overlay.pending = null
                f()
            }
        }
    }

    function move(delta) {
        var n = overlay.results.length
        if (n === 0) return
        overlay.pointerSteers = false
        // Wraps, so Up from the first row reaches the last without a trip
        // through the whole list.
        overlay.selected = ((overlay.selected + delta) % n + n) % n
    }

    // By a page, not wrapping: the ends are where a page stops.
    function page(delta) {
        var n = overlay.results.length
        if (n === 0) return
        overlay.pointerSteers = false
        overlay.selected = Math.max(0, Math.min(n - 1, overlay.selected + delta))
    }

    // Cleared on the way in, not the way out: emptied on closing, the list
    // and the field went blank before the fade out could show them leaving.
    onOpenChanged: {
        if (!overlay.open) return
        overlay.launching = false
        overlay.query = AppState.launcherPreset
        overlay.selected = 0
        AppState.launcherPreset = ""
        searchInput.forceActiveFocus()
        searchInput.cursorPosition = searchInput.text.length
    }

    // ── Click-away ───────────────────────────────────────────────────────
    //
    // Draws nothing: the desktop keeps its own contrast while this is open.
    // It exists so a click outside the panel still closes it.
    Item {
        anchors.fill: parent

        TapHandler {
            onTapped: overlay.close()
        }
    }

    // ── Panel ────────────────────────────────────────────────────────────
    Item {
        id: cardArea

        x: Math.round((overlay.width - overlay.cardWidth) / 2)
        y: overlay.cardTop
        width: overlay.cardWidth
        height: overlay.cardHeight

        opacity: overlay.open ? 1 : 0
        visible: opacity > 0
        scale: overlay.open ? 1 : 0.97

        // Drops in a few pixels as it appears, the way the bar's panels
        // unfold from the pill.
        transform: Translate {
            y: overlay.open ? 0 : -8
            Behavior on y {
                NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
            }
        }

        Behavior on height {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        // Long enough both ways for leaving to read as a fade and not a cut:
        // at 100ms OutCubic the panel was gone in about two frames. One
        // duration for both directions -- one picked by `open` would be read
        // in the same instant `open` flips, and could be the old one.
        Behavior on opacity {
            // Not when launching: the app's window is the animation then.
            enabled: !overlay.launching
            NumberAnimation { duration: 170; easing.type: Easing.OutQuad }
        }

        Behavior on scale {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        // The pills' glass and shadow.
        Rectangle {
            id: card
            anchors.fill: parent
            radius: 26
            color: Theme.glass
            // No outline: none of the shell's glass has one, and this one's
            // bottom edge read as a light rim over the shadow.
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.55
            shadowBlur: 1.0
            shadowVerticalOffset: 10
            autoPaddingEnabled: true
        }

        // Swallows clicks that land on the panel, so only outside closes.
        TapHandler {}

        // The row under the pointer becomes the selection, once the pointer
        // has actually moved (see pointerSteers) -- one highlight, never a
        // hovered row and a different row for Enter.
        HoverHandler {
            onPointChanged: {
                var p = point.position
                var last = overlay.lastPointer
                overlay.lastPointer = p
                if (!hovered || (Math.abs(p.x - last.x) < 1 && Math.abs(p.y - last.y) < 1)) return
                overlay.pointerSteers = true
                var lp = list.mapFromItem(cardArea, p.x, p.y)
                if (lp.y < 0 || lp.y > list.height) return
                var i = list.indexAt(lp.x + list.contentX, lp.y + list.contentY)
                if (i >= 0) overlay.selected = i
            }
        }

        // ── Search field ─────────────────────────────────────────────────
        //
        // No box of its own: the field is the top of the panel, and a
        // rounded well inside a rounded panel reads as two things.
        Item {
            id: searchRow
            width: parent.width
            height: overlay.searchHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 20
                spacing: 14

                IconGlyph {
                    text: "\u{F0349}"
                    color: searchInput.text.length > 0 ? Theme.textSecondary : Theme.textMuted
                    size: 20

                    Behavior on color {
                        ColorAnimation { duration: Theme.durShort }
                    }
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    font.pixelSize: 22
                    font.family: overlay.fontDisplay
                    selectByMouse: true
                    selectionColor: Theme.alpha(AppState.themeAccent, 0.35)
                    selectedTextColor: Theme.textPrimary
                    clip: true
                    focus: overlay.open

                    text: overlay.query
                    onTextChanged: overlay.query = text

                    Keys.onEscapePressed: overlay.close()
                    Keys.onUpPressed: overlay.move(-1)
                    Keys.onDownPressed: overlay.move(1)
                    // Tab walks the list too, the way rofi's did.
                    Keys.onTabPressed: overlay.move(1)
                    Keys.onBacktabPressed: overlay.move(-1)
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_PageDown) { overlay.page(5); event.accepted = true }
                        else if (event.key === Qt.Key_PageUp) { overlay.page(-5); event.accepted = true }
                        else if (event.modifiers & Qt.ControlModifier) {
                            if (event.key === Qt.Key_J || event.key === Qt.Key_N) { overlay.move(1); event.accepted = true }
                            else if (event.key === Qt.Key_K || event.key === Qt.Key_P) { overlay.move(-1); event.accepted = true }
                        }
                    }

                    onAccepted: overlay.run(overlay.results[overlay.selected])

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: "Search apps, windows, settings…"
                        color: Theme.textMuted
                        font.pixelSize: 22
                        font.family: overlay.fontDisplay
                    }
                }

                // Clears the field without closing, when there is something
                // in it.
                Item {
                    implicitWidth: 26
                    implicitHeight: 26
                    visible: searchInput.text.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 13
                        color: Theme.surfaceContainer

                        IconGlyph {
                            anchors.centerIn: parent
                            text: "\u{F0156}"
                            color: Theme.textSecondary
                            size: Theme.iconTiny
                        }

                        StateLayer {
                            onTapped: {
                                overlay.query = ""
                                searchInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }

        // Hairline between the field and the list.
        Rectangle {
            y: searchRow.height
            x: 1
            width: parent.width - 2
            height: 1
            color: Theme.outline
            visible: overlay.hasResults
        }

        // ── Results ──────────────────────────────────────────────────────
        ListView {
            id: list
            y: searchRow.height + 1 + overlay.listPad
            width: parent.width
            height: overlay.listHeight
            clip: true
            model: overlay.results
            currentIndex: overlay.selected
            boundsBehavior: Flickable.StopAtBounds
            visible: overlay.hasResults

            // Keeps the keyboard selection on screen without dragging the
            // view along behind every step, which is what Beginning would do.
            onCurrentIndexChanged: list.positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Item {
                id: row
                required property int index
                required property var modelData

                readonly property bool current: overlay.selected === row.index
                readonly property bool header: overlay.startsSection(row.index)
                readonly property bool glyphIcon: row.modelData.kind !== "app"
                                                  && row.modelData.kind !== "window"

                width: list.width
                height: overlay.rowHeight + (row.header ? overlay.headerHeight : 0)

                SectionLabel {
                    visible: row.header
                    x: 24
                    height: overlay.headerHeight
                    verticalAlignment: Text.AlignVCenter
                    topPadding: row.index === 0 ? 0 : 6
                    text: row.modelData.section
                }

                Rectangle {
                    y: row.header ? overlay.headerHeight : 0
                    x: 8
                    width: parent.width - 16
                    height: overlay.rowHeight
                    radius: 12
                    color: row.current ? Theme.surfaceContainerHigh : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.durShort }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        spacing: 12

                        // Applications and windows by their app's icon; the
                        // shell's own things by a glyph on a small tile.
                        Item {
                            implicitWidth: 30
                            implicitHeight: 30

                            IconImage {
                                anchors.centerIn: parent
                                visible: !row.glyphIcon
                                implicitSize: 28
                                mipmap: true
                                source: row.glyphIcon ? ""
                                      : Quickshell.iconPath(row.modelData.icon || "", "application-x-executable")
                            }

                            Rectangle {
                                anchors.fill: parent
                                visible: row.glyphIcon
                                radius: 9
                                color: row.current ? Theme.alpha(AppState.themeAccent, 0.22) : Theme.surfaceContainer

                                Behavior on color {
                                    ColorAnimation { duration: Theme.durShort }
                                }

                                IconGlyph {
                                    anchors.centerIn: parent
                                    text: row.modelData.glyph || ""
                                    color: row.current ? Theme.textPrimary : Theme.textSecondary
                                    size: Theme.iconMedium
                                }
                            }
                        }

                        // One line, not two: the name on the left and what
                        // the thing is on the right, as Spotlight does.
                        Text {
                            Layout.fillWidth: true
                            text: overlay.highlight(row.modelData)
                            textFormat: Text.StyledText
                            color: row.current ? Theme.textPrimary : Theme.textSecondary
                            font.pixelSize: row.modelData.kind === "calc" ? 17 : 14
                            font.family: overlay.fontText
                            elide: Text.ElideRight

                            Behavior on color {
                                ColorAnimation { duration: Theme.durShort }
                            }
                        }

                        Text {
                            visible: text.length > 0
                            text: row.modelData.detail || ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: overlay.fontText
                            elide: Text.ElideRight
                            Layout.maximumWidth: 220
                        }

                        // What Enter does to the chosen row.
                        Text {
                            visible: row.current
                            text: overlay.verb(row.modelData) + "  ↵"
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontMono
                        }
                    }

                    StateLayer {
                        radius: 12
                        // No hover tint of its own: the pointer moves the
                        // selection instead (the HoverHandler on the panel).
                        tint: "transparent"
                        onTapped: overlay.run(row.modelData)
                    }
                }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────
        Rectangle {
            y: list.y + list.height + overlay.listPad
            x: 1
            width: parent.width - 2
            height: 1
            color: Theme.outline
            visible: overlay.hasResults
        }

        Item {
            y: list.y + list.height + overlay.listPad + 1
            width: parent.width
            height: overlay.footerHeight
            visible: overlay.hasResults

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                KeyHint { key: "↑↓"; label: "Navigate" }
                KeyHint {
                    key: "↵"
                    label: overlay.hasResults && overlay.results[overlay.selected]
                           ? overlay.verb(overlay.results[overlay.selected]) : "Open"
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: overlay.results.length + (overlay.results.length === 1 ? " result" : " results")
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontMono
                }

                KeyHint { key: "esc"; label: "Close" }
            }
        }
    }
}
