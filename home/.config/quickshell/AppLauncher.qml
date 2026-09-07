import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// The application launcher, opened from the bind the config points at
// "quickshell:launcher". Replaces `rofi -show drun`.
//
// Structure follows KeybindsOverlay and the wallpaper picker: mapped for the
// life of the shell and hidden by cutting input rather than by unmapping,
// exclusive keyboard focus only while open, pinned to the screen it was
// summoned on. Sized to what rofi was -- 600px wide, eight rows -- because
// that is the shape the muscle memory is in.
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

    visible: true
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

    // ── Geometry ─────────────────────────────────────────────────────────
    readonly property int cardWidth: 600
    readonly property int cardPadding: 14
    readonly property int searchHeight: 46
    readonly property int rowHeight: 46
    readonly property int visibleRows: 8
    readonly property int listGap: 10

    readonly property int listHeight:
        overlay.rowHeight * Math.min(Math.max(overlay.results.length, 1), overlay.visibleRows)

    readonly property int cardHeight:
        overlay.cardPadding * 2 + overlay.searchHeight + overlay.listGap + overlay.listHeight

    // The card grows and shrinks with the result count, so it is placed by
    // where it would sit at full height rather than by its own centre --
    // otherwise the search field walks up the screen as you type and the
    // thing you are aiming at moves while you aim at it.
    readonly property int fullHeight:
        overlay.cardPadding * 2 + overlay.searchHeight + overlay.listGap
        + overlay.rowHeight * overlay.visibleRows

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
    // down to the fiftieth fuzzy match. Kept separate from `ranked` so the
    // count beside the search field can report what actually matched rather
    // than reporting the cap back at the user.
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
        // "dolphin" for org.kde.dolphin.
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

    // ── Backdrop ─────────────────────────────────────────────────────────
    //
    // The compositor blurs what is behind this surface (see the
    // quickshell-launcher-blur layer rule), so the tint only has to settle
    // the contrast under the card.
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.background, 0.38)
        opacity: overlay.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        TapHandler {
            onTapped: overlay.close()
        }
    }

    // ── Card ─────────────────────────────────────────────────────────────
    Item {
        id: cardArea

        x: Math.round((overlay.width - overlay.cardWidth) / 2)
        y: Math.round((overlay.height - overlay.fullHeight) / 2)
        width: overlay.cardWidth
        height: overlay.cardHeight

        opacity: overlay.open ? 1 : 0
        visible: opacity > 0
        scale: overlay.open ? 1 : 0.97

        Behavior on height {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: 26
            color: Theme.glass
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.5
            shadowBlur: 0.8
            shadowVerticalOffset: 6
            autoPaddingEnabled: true
        }

        // Swallows clicks that land on the card, so only the backdrop closes.
        TapHandler {}

        // ── Search field ─────────────────────────────────────────────────
        Rectangle {
            id: searchBox
            x: overlay.cardPadding
            y: overlay.cardPadding
            width: parent.width - overlay.cardPadding * 2
            height: overlay.searchHeight
            radius: 14
            color: Theme.surfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                IconGlyph {
                    text: "\u{F0349}"
                    color: Theme.textSecondary
                    size: Theme.iconMedium
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.family: Theme.fontMono
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
                        text: "Search…"
                        color: Theme.textMuted
                        font.pixelSize: 14
                        font.family: Theme.fontMono
                    }
                }

                Text {
                    visible: overlay.ranked.length > 0
                    text: overlay.ranked.length
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                }
            }
        }

        // ── Results ──────────────────────────────────────────────────────
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: searchBox.y + searchBox.height + overlay.listGap
            height: overlay.rowHeight
            verticalAlignment: Text.AlignVCenter
            visible: overlay.results.length === 0
            text: overlay.query.trim().length === 0 ? "No applications found"
                                                    : "Nothing matches that"
            color: Theme.textMuted
            font.pixelSize: 12
            font.family: Theme.fontMono
        }

        ListView {
            id: list
            x: overlay.cardPadding
            y: searchBox.y + searchBox.height + overlay.listGap
            width: parent.width - overlay.cardPadding * 2
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
                    anchors.rightMargin: 2
                    radius: 12
                    color: row.current ? Theme.surfaceContainerHigh : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Theme.durShort }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 12

                        IconImage {
                            implicitSize: 26
                            mipmap: true
                            source: Quickshell.iconPath(row.modelData.entry.icon,
                                                        "application-x-executable")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.entry.name
                                color: row.current ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: 13
                                font.family: Theme.fontMono
                                elide: Text.ElideRight

                                Behavior on color {
                                    ColorAnimation { duration: Theme.durShort }
                                }
                            }

                            // The one-line description the entry gives for
                            // itself, which is usually the difference between
                            // two apps whose names say nothing.
                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: row.modelData.entry.genericName
                                      || row.modelData.entry.comment || ""
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontMono
                                elide: Text.ElideRight
                            }
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
