import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// The application launcher, opened from the bind the config points at
// "quickshell:launcher". Replaces `rofi -show drun`.
//
// Shaped after macOS Spotlight by request, which is why it breaks two of the
// shell's own habits: it draws in SF Pro rather than the mono face the bar
// uses, and it does not dim the desktop behind it. Everything structural is
// still the house pattern -- mapped for the life of the shell, exclusive
// keyboard focus only while open, pinned to the screen it was summoned on.
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

    WlrLayershell.namespace: "quickshell:launcher"
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

    // ── Type ─────────────────────────────────────────────────────────────
    //
    // The one place in the shell that is not in the mono face. Spotlight is
    // a proportional-set panel and reads wrong in a monospace -- the names
    // are the content here, not tabular data. Both families resolve exactly;
    // Display is the optical size cut for the large field, Text for the rows.
    readonly property string fontDisplay: "SF Pro Display"
    readonly property string fontText: "SF Pro Text"

    // ── Geometry ─────────────────────────────────────────────────────────
    readonly property int cardWidth: 680
    readonly property int searchHeight: 60
    readonly property int rowHeight: 44
    readonly property int visibleRows: 8
    readonly property int listPad: 6

    readonly property bool hasResults: overlay.results.length > 0

    readonly property int listHeight:
        overlay.rowHeight * Math.min(overlay.results.length, overlay.visibleRows)

    // Just the field when nothing matches, the way Spotlight collapses to it.
    readonly property int cardHeight: overlay.searchHeight
        + (overlay.hasResults ? 1 + overlay.listPad * 2 + overlay.listHeight : 0)

    // Spotlight sits high rather than centred, and the field stays put while
    // the list grows and shrinks underneath it.
    readonly property int cardTop: Math.round(overlay.height * 0.22)

    // ── State ────────────────────────────────────────────────────────────
    property string query: ""
    property int selected: 0

    // Ranked rather than filtered. A plain substring test has no way to say
    // that "fi" should reach Firefox before it reaches "Wi-Fi settings", and
    // ordering is most of what a launcher does -- the first row is the one
    // that gets run.
    readonly property var ranked: {
        var all = DesktopEntries.applications.values
        var q = overlay.query.trim().toLowerCase()
        var out = []

        for (var i = 0; i < all.length; i++) {
            var e = all[i]
            // NoDisplay is the entry asking not to be listed: mime handlers,
            // per-app settings panels, the halves of a split package.
            if (e.noDisplay) continue

            if (q.length === 0) {
                out.push({ entry: e, score: 0 })
                continue
            }

            var s = overlay.score(e, q)
            if (s > 0) out.push({ entry: e, score: s })
        }

        out.sort(function(a, b) {
            if (a.score !== b.score) return b.score - a.score
            return a.entry.name.localeCompare(b.entry.name)
        })

        return out
    }

    // The list scrolls, but past a point the tail is noise -- nobody arrows
    // down to the fiftieth fuzzy match.
    readonly property var results: overlay.ranked.slice(0, 50)

    // Higher wins; zero drops the entry. The tiers are in the order someone
    // would think of them, and each one subtracts a little for length or
    // distance so that within a tier the tighter match comes first.
    function score(entry, q) {
        var name = (entry.name || "").toLowerCase()

        if (name === q) return 1000
        if (name.startsWith(q)) return 900 - Math.min(90, name.length)

        // A query that starts a later word: "code" for "Visual Studio Code".
        var words = name.split(/[\s\-_.:]+/)
        for (var i = 1; i < words.length; i++) {
            if (words[i].startsWith(q)) return 800 - Math.min(90, name.length)
        }

        var at = name.indexOf(q)
        if (at !== -1) return 700 - Math.min(90, at)

        // The desktop id catches the case where the binary is what the user
        // knows the app by rather than its display name: "nvim" for Neovim,
        // "dolphin" for org.kde.dolphin. It earns its place twice over here,
        // where the entries are localised to Spanish and an English query
        // would otherwise reach nothing.
        if ((entry.id || "").toLowerCase().indexOf(q) !== -1) return 600

        // genericName is the curated "what this is" line -- "Terminal
        // emulator", "Web Browser" -- and it beats keywords, which are a
        // grab bag anyone can stuff. Tried the other way round first, and
        // "term" put a text editor that keywords itself "terminal" above
        // both installed terminals.
        if ((entry.genericName || "").toLowerCase().indexOf(q) !== -1) return 500

        var kw = entry.keywords || []
        for (var k = 0; k < kw.length; k++) {
            if (kw[k].toLowerCase().indexOf(q) !== -1) return 450
        }
        if ((entry.comment || "").toLowerCase().indexOf(q) !== -1) return 400

        // Last resort: the letters in order but not adjacent. This is what
        // gets "gimp" from "gmp", and what keeps a typo landing somewhere
        // instead of on an empty list.
        return overlay.subsequenceScore(name, q)
    }

    // Scores how tightly the letters of q are packed where they appear in
    // order in text. Zero when the letters are not all there, and zero again
    // when they are there but strewn: without that ceiling this matched
    // almost everything, and "code" came back with the Avahi Zeroconf
    // browser and the volume control rather than with nothing.
    function subsequenceScore(text, q) {
        // Two letters land inside almost any name, so there is no signal in
        // a fuzzy match this short.
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

        // Letters skipped between the first and the last. Allowing about as
        // many as were typed keeps a real abbreviation ("gmp" for Gimp, "vsc"
        // for VS Code) and drops a coincidence.
        var slack = (last - first + 1) - q.length
        if (slack > Math.max(4, q.length)) return 0

        return Math.max(1, 300 - slack * 8 - Math.min(50, first))
    }

    function close() {
        AppState.launcherOpen = false
    }

    function launch(entry) {
        if (!entry) return
        // Closed first: the launcher holds the keyboard exclusively while it
        // is open, and a window that maps into that grab comes up without
        // focus.
        overlay.close()
        entry.execute()
    }

    function move(delta) {
        var n = overlay.results.length
        if (n === 0) return
        // Wraps, so Up from the first row reaches the last without a trip
        // through the whole list.
        overlay.selected = ((overlay.selected + delta) % n + n) % n
    }

    onOpenChanged: {
        if (overlay.open) {
            overlay.query = ""
            overlay.selected = 0
            searchInput.forceActiveFocus()
        } else {
            overlay.query = ""
        }
    }

    // Every keystroke reorders the list, and the selection has to come back
    // to the top with it -- leaving it where it was points at whatever
    // happens to be in that slot now.
    onResultsChanged: overlay.selected = 0

    // ── Click-away ───────────────────────────────────────────────────────
    //
    // Deliberately draws nothing. The desktop keeps its own contrast and its
    // own colour while this is open; the panel is the only thing that
    // arrives. This item exists so a click outside it still closes.
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
        // Barely there, and short. Spotlight appears rather than animating.
        scale: overlay.open ? 1 : 0.98

        Behavior on height {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 20
            color: Theme.glass
            // The hairline every macOS panel carries, which is what keeps a
            // translucent surface from bleeding into a busy wallpaper now
            // that there is no dim behind it to separate the two.
            border.width: 1
            border.color: Theme.outline
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

        // ── Search field ─────────────────────────────────────────────────
        //
        // No box of its own: in Spotlight the field is the top of the panel,
        // and a rounded well inside a rounded panel reads as two things.
        Item {
            id: searchRow
            width: parent.width
            height: overlay.searchHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                spacing: 14

                IconGlyph {
                    text: "\u{F0349}"
                    color: Theme.textMuted
                    size: 20
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

                    onAccepted: {
                        var hit = overlay.results[overlay.selected]
                        if (hit) overlay.launch(hit.entry)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: "Search"
                        color: Theme.textMuted
                        font.pixelSize: 22
                        font.family: overlay.fontDisplay
                    }
                }
            }
        }

        // Hairline between the field and the list, inset from the rounded
        // corners so it does not run into them.
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
            highlightMoveDuration: Theme.durShort

            // Keeps the keyboard selection on screen without dragging the
            // view along behind every step, which is what Beginning would do.
            onCurrentIndexChanged: list.positionViewAtIndex(currentIndex, ListView.Contain)

            delegate: Item {
                id: row
                required property int index
                required property var modelData

                width: list.width
                height: overlay.rowHeight

                readonly property bool current: overlay.selected === row.index

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    radius: 8
                    color: row.current ? Theme.surfaceContainerHigh : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.durShort }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 14
                        spacing: 12

                        IconImage {
                            implicitSize: 28
                            mipmap: true
                            source: Quickshell.iconPath(row.modelData.entry.icon,
                                                        "application-x-executable")
                        }

                        // One line, not two. Spotlight puts the name on the
                        // left and what the thing is on the right, and the
                        // stacked subtitle was what made the old rows read as
                        // a settings list rather than as a launcher.
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.entry.name
                            color: row.current ? Theme.textPrimary : Theme.textSecondary
                            font.pixelSize: 14
                            font.family: overlay.fontText
                            elide: Text.ElideRight

                            Behavior on color {
                                ColorAnimation { duration: Theme.durShort }
                            }
                        }

                        Text {
                            visible: text.length > 0
                            text: row.modelData.entry.genericName || ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: overlay.fontText
                            elide: Text.ElideRight
                            Layout.maximumWidth: 200
                        }
                    }

                    StateLayer {
                        // Hovering moves the selection rather than drawing a
                        // second highlight, so the row Enter would run and
                        // the row under the pointer are never two rows.
                        onTapped: overlay.launch(row.modelData.entry)

                        onHoveredChanged: if (hovered) overlay.selected = row.index
                    }
                }
            }
        }
    }
}
