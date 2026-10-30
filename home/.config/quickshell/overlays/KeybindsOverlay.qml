import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// The keyboard shortcut sheet: every Hyprland bind, read out of the live
// config, and Yazi's, out of its keymap (see Keybinds). Opened from the
// control panel or from the bind the config points at "quickshell:keybinds".
//
// Laid out like the launcher -- a search field across the top of one glass
// panel, the list under it, the keys along the bottom -- because it is used
// the same way: open it, type a few letters of what you want to do, read the
// keys. The two sources stay apart, a tab each: `d` is a different key in
// Yazi than in Hyprland, and one merged list would leave the reader working
// out which one they are looking at.
PanelWindow {
    id: overlay

    property var bar: null
    screen: bar.screen

    // ── Pieces ───────────────────────────────────────────────────────────

    // A group's name over its rows: the launcher's section label.
    component SectionLabel: Text {
        color: Theme.textSecondary
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.family: Theme.fontText
    }

    // One bind's keys, as caps (see capsOf): "Super + Shift + R" is three
    // keys held together, joined by a small plus; "g g" is one key pressed
    // twice, two caps side by side; "or" joins two binds that do the same
    // (see prepare).
    component KeyCombo: Row {
        id: combo
        property var caps: []
        spacing: 3

        Repeater {
            model: combo.caps

            Item {
                id: part
                required property var modelData
                readonly property bool isCap: part.modelData.kind === "cap"
                anchors.verticalCenter: parent.verticalCenter
                width: part.isCap ? partCap.width : partText.implicitWidth
                height: 22

                KeyCap {
                    id: partCap
                    visible: part.isCap
                    anchors.verticalCenter: parent.verticalCenter
                    key: part.isCap ? part.modelData.text : ""
                    capHeight: 22
                    fontSize: 11
                }

                Text {
                    id: partText
                    visible: !part.isCap
                    anchors.verticalCenter: parent.verticalCenter
                    text: part.modelData.kind === "plus" ? "+" : part.modelData.text
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontMono
                    // "or" stands between two whole combinations, so it gets
                    // more room than the plus inside one.
                    leftPadding: part.modelData.kind === "or" ? 5 : 1
                    rightPadding: part.modelData.kind === "or" ? 5 : 1
                }
            }
        }
    }

    // ── Type and geometry ────────────────────────────────────────────────
    //
    // The launcher's: a proportional face for what the binds do, which is
    // the content here, and the monospace only on the keys.
    readonly property string fontDisplay: Theme.fontDisplay
    readonly property string fontText: Theme.fontText

    // Never below a sane floor. The window is 0x0 until Hyprland first sizes
    // it, and a panel worked out from that came to -120px wide -- with a
    // layer-rendered shadow on it, the sheet drew nothing on its first open.
    readonly property int cardWidth: Math.max(480, Math.min(overlay.width - 120, 1320))
    // The top stays put and the panel grows and shrinks below it, so the
    // field does not slide around under the text being typed into it.
    readonly property int cardTop: Math.round(overlay.height * 0.12)
    readonly property int searchHeight: 62
    readonly property int footerHeight: 44
    readonly property int bodyPad: 24
    readonly property int columnGap: 32

    // As many columns of at least 380px as fit, up to three: past that a row
    // is a long way for the eye to travel from what a bind does to its keys.
    readonly property int maxColumns: Math.max(1, Math.min(3,
        Math.floor((overlay.cardWidth - 2 * overlay.bodyPad + overlay.columnGap) / (380 + overlay.columnGap))))
    // Fixed whatever the count in use, so typing never re-flows a row that
    // is still showing into a different width.
    readonly property int columnWidth: Math.floor(
        (overlay.cardWidth - 2 * overlay.bodyPad - (overlay.maxColumns - 1) * overlay.columnGap) / overlay.maxColumns)

    // ── Visibility ───────────────────────────────────────────────────────

    // One copy exists per monitor, and only the one it was opened on shows.
    // Matched against the screen latched when it opened, not live focus,
    // which follows the mouse and used to drag the sheet along with it.
    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (Panels.keybindsScreen === "") return bar.monitor.focused
        return bar.monitor.name === Panels.keybindsScreen
    }

    readonly property bool open: Panels.keybindsOpen && overlay.onOpeningScreen

    // Unmapped while closed, not merely drawn empty: a mapped full-screen
    // layer is composited every frame whether or not it shows anything.
    //
    // `shown` keeps it mapped until the fade out has played. Not `open ||
    // unmapDelay.running`, which is false for the moment between `open`
    // going false and the timer starting -- a two-frame blink before the fade
    // (see AppLauncher).
    property bool shown: false
    visible: overlay.shown

    Timer {
        id: unmapDelay
        // The inner fades run on durMedium; the margin covers the frame the
        // Behavior needs to get going.
        interval: Theme.durMedium + 80
        onTriggered: overlay.shown = false
    }

    // Connections rather than an `onOpenChanged`, which the object may
    // declare only once.
    Connections {
        target: overlay
        function onOpenChanged() {
            if (overlay.open) {
                unmapDelay.stop()
                // Always from the top with an empty field: the sheet is looked
                // up in, not left half-read.
                overlay.query = ""
                overlay.viewSection = overlay.section
                flick.contentY = 0
                overlay.shown = true
                searchInput.forceActiveFocus()
                overlay.revealBody()
            } else {
                overlay.hideBody()
                unmapDelay.restart()
            }
        }
    }

    color: "transparent"

    WlrLayershell.namespace: "quickshell:keybinds"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Exclusive while up, so the keys reach the field; held through the fade
    // out, since changing it on a surface that stays mapped drops that
    // surface for two frames (see AppLauncher).
    WlrLayershell.keyboardFocus: overlay.shown ? WlrKeyboardFocus.Exclusive
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

    function close() {
        Panels.keybindsOpen = false
    }

    // ── Sections ─────────────────────────────────────────────────────────

    readonly property var sections: [
        { id: "hyprland", name: "Hyprland", glyph: "\u{F056E}" },
        { id: "yazi", name: "Yazi", glyph: "\u{F024B}" }
    ]

    // The tab selected, and the one the body is showing. The second follows
    // the first once the old list has faded out (see showSection), so a tab
    // change never swaps the rows in mid-fade.
    property string section: "hyprland"
    property string viewSection: "hyprland"

    function showSection(id) {
        if (overlay.section === id) return
        overlay.section = id
        overlay.hideBody()
        sectionSwap.restart()
    }

    function otherSection() {
        return overlay.section === "hyprland" ? "yazi" : "hyprland"
    }

    Timer {
        id: sectionSwap
        interval: Theme.durShort
        onTriggered: {
            overlay.viewSection = overlay.section
            flick.contentY = 0
            overlay.revealBody()
        }
    }

    // ── The binds, ready to show ─────────────────────────────────────────
    //
    // Keys split into caps, and one lower-case string to search, worked out
    // once each time a config is re-read rather than on every keystroke.
    readonly property var keyNames: ({
        "Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
        "Enter": "↵", "Return": "↵", "Backspace": "⌫"
    })

    function capsOf(keys) {
        var out = []
        var parts = (keys || "").split(" + ")
        for (var i = 0; i < parts.length; i++) {
            if (i > 0) out.push({ kind: "plus", text: "" })
            var p = parts[i]
            // "g g" and "1 … 0" are a sequence of keys; "Vol +" is one key
            // with a space in its name. Short pieces are the tell.
            var seq = p.split(" ")
            if (seq.length > 1 && seq.every(s => s.length > 0 && s.length <= 2)) {
                for (var j = 0; j < seq.length; j++) {
                    out.push(seq[j] === "…" ? { kind: "text", text: "…" }
                                                  : { kind: "cap", text: overlay.keyNames[seq[j]] || seq[j] })
                }
            } else {
                out.push({ kind: "cap", text: overlay.keyNames[p] || p })
            }
        }
        return out
    }

    readonly property var groupGlyphs: ({
        "Applications": "\u{F003B}", "Windows": "\u{F05AF}", "Workspaces": "\u{F0570}",
        "Media": "\u{F057E}", "System": "\u{F0493}",
        "My own": "\u{F04CE}", "Files": "\u{F0224}", "Getting around": "\u{F018B}",
        "Selecting": "\u{F0138}", "Looking around": "\u{F0208}", "Commands": "\u{F07B7}"
    })

    // Two binds in a group that do the same thing are one row with both
    // keys ("Media play or Media pause"): the sheet is read by what you want
    // done, and the same line twice reads as a mistake.
    function prepare(groups) {
        var home = Quickshell.env("HOME")
        return (groups || []).map(g => {
            var binds = []
            var byAction = {}
            for (var i = 0; i < (g.binds || []).length; i++) {
                var b = g.binds[i]
                var command = (b.command || "").split(home).join("~")
                var same = byAction[b.action + "\n" + command]
                if (same) {
                    same.caps = same.caps.concat([{ kind: "or", text: "or" }], overlay.capsOf(b.keys))
                    same.hay += " " + b.keys.toLowerCase()
                    continue
                }
                var row = {
                    action: b.action,
                    // The config's own paths, shortened the way a shell would.
                    command: command,
                    caps: overlay.capsOf(b.keys),
                    hay: (b.action + " " + b.keys + " " + (b.command || "") + " " + g.name).toLowerCase()
                }
                byAction[b.action + "\n" + command] = row
                binds.push(row)
            }
            return { name: g.name, glyph: overlay.groupGlyphs[g.name] || "\u{F097B}", binds: binds }
        })
    }

    readonly property var hyprGroups: overlay.prepare(Keybinds.hyprBindGroups)
    readonly property var yaziGroups: overlay.prepare(Keybinds.yaziBindGroups)

    // ── Search ───────────────────────────────────────────────────────────
    //
    // Every word typed has to appear somewhere in the bind -- what it does,
    // its keys, the command behind it or its group -- so "move work" finds
    // "Move to workspace" and "super shift" finds every bind on those two.
    property string query: ""
    readonly property var terms: overlay.query.toLowerCase().split(/\s+/).filter(t => t.length > 0)

    function filter(groups) {
        var t = overlay.terms
        if (t.length === 0) return groups
        var out = []
        for (var i = 0; i < groups.length; i++) {
            var binds = groups[i].binds.filter(b => t.every(x => b.hay.indexOf(x) !== -1))
            if (binds.length > 0) out.push({ name: groups[i].name, glyph: groups[i].glyph, binds: binds })
        }
        return out
    }

    function countOf(groups) {
        var n = 0
        for (var i = 0; i < groups.length; i++) n += groups[i].binds.length
        return n
    }

    readonly property var hyprShown: overlay.filter(overlay.hyprGroups)
    readonly property var yaziShown: overlay.filter(overlay.yaziGroups)

    function totalOf(id) { return overlay.countOf(id === "yazi" ? overlay.yaziGroups : overlay.hyprGroups) }
    function shownOf(id) { return overlay.countOf(id === "yazi" ? overlay.yaziShown : overlay.hyprShown) }

    readonly property var viewGroups: overlay.viewSection === "yazi" ? overlay.yaziShown : overlay.hyprShown
    readonly property string viewError: overlay.viewSection === "yazi" ? Keybinds.yaziBindsError
                                                                       : Keybinds.hyprBindsError

    // What was typed, marked in the text it matched. The accent alone, not
    // bold as well: bold is wider, and the row would shift under the eye as
    // each letter lands.
    function escaped(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function highlight(text) {
        var t = overlay.terms
        if (t.length === 0) return overlay.escaped(text)
        var low = text.toLowerCase()
        var mark = []
        for (var k = 0; k < text.length; k++) mark.push(false)
        for (var i = 0; i < t.length; i++) {
            var at = low.indexOf(t[i])
            while (at !== -1) {
                for (var m = at; m < at + t[i].length; m++) mark[m] = true
                at = low.indexOf(t[i], at + t[i].length)
            }
        }
        var out = "", on = false
        for (var c = 0; c < text.length; c++) {
            if (mark[c] !== on) {
                out += mark[c] ? "<font color=\"" + Theme.accent + "\">" : "</font>"
                on = mark[c]
            }
            out += overlay.escaped(text[c])
        }
        return on ? out + "</font>" : out
    }

    // ── Columns ──────────────────────────────────────────────────────────
    //
    // Groups poured into columns in the order the config declares them,
    // each column filled to about an even share. A group that crosses the
    // line carries on at the top of the next column under its name again --
    // Yazi's own binds alone are sixty rows, and whole groups only would
    // leave one column that long beside two short ones.
    //
    // Only as many columns as the rows need: a handful of search results
    // reads as a list, not three stubs.
    readonly property int columnCount: {
        var rows = overlay.countOf(overlay.viewGroups) + 2 * overlay.viewGroups.length
        return Math.max(1, Math.min(overlay.maxColumns, Math.ceil(rows / 12)))
    }

    function packColumns(groups, n) {
        var units = b => b.command.length > 0 ? 1.5 : 1
        var total = 0
        for (var i = 0; i < groups.length; i++) {
            total += 2
            for (var j = 0; j < groups[i].binds.length; j++) total += units(groups[i].binds[j])
        }
        var target = total / n
        var cols = [], col = [], h = 0
        for (var gi = 0; gi < groups.length; gi++) {
            var g = groups[gi]
            var block = { name: g.name, glyph: g.glyph, cont: false, binds: [] }
            h += 2
            for (var bi = 0; bi < g.binds.length; bi++) {
                var b = g.binds[bi], u = units(b)
                var left = g.binds.length - bi
                // Break before this row if the column is full -- unless it is
                // the last column, or the break would strand a single row.
                if (h + u > target && cols.length < n - 1 && h > 2 && (left >= 2 || block.binds.length === 0)) {
                    if (block.binds.length >= 2 || (block.cont && block.binds.length > 0)) {
                        col.push(block)
                        block = { name: g.name, glyph: g.glyph, cont: true, binds: [] }
                    }
                    // Otherwise the heading and its lone row move on together.
                    cols.push(col)
                    col = []
                    h = 2
                    for (var k = 0; k < block.binds.length; k++) h += units(block.binds[k])
                }
                block.binds.push(b)
                h += u
            }
            col.push(block)
        }
        if (col.length > 0) cols.push(col)
        return cols
    }

    readonly property var columns: overlay.packColumns(overlay.viewGroups, overlay.columnCount)

    // ── The body's entrance ──────────────────────────────────────────────
    //
    // The columns come in one after another, rising a few pixels, and leave
    // all at once. `stagger` is set before `bodyIn` changes, so the delays
    // bound to it are already right when the Behaviors read them.
    property bool bodyIn: false
    property bool stagger: false

    function revealBody() {
        overlay.stagger = true
        overlay.bodyIn = true
    }

    function hideBody() {
        overlay.stagger = false
        overlay.bodyIn = false
    }

    // ── Scrolling from the keyboard ──────────────────────────────────────
    function scrollBy(dy) {
        var max = Math.max(0, flick.contentHeight - flick.height)
        scrollAnim.to = Math.max(0, Math.min(max, (scrollAnim.running ? scrollAnim.to : flick.contentY) + dy))
        scrollAnim.restart()
    }

    NumberAnimation {
        id: scrollAnim
        target: flick
        property: "contentY"
        duration: Theme.durMedium
        easing.type: Easing.OutCubic
    }

    // ── Backdrop ─────────────────────────────────────────────────────────

    // The overlays' scrim. There is no compositor blur under it any more, so
    // it is what keeps the windows behind from competing with the sheet.
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: overlay.open ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        TapHandler {
            onTapped: overlay.close()
        }
    }

    // ── Panel ────────────────────────────────────────────────────────────

    Item {
        id: cardArea

        readonly property int bodyHeight: overlay.viewGroups.length > 0
            ? columnsRow.implicitHeight + 2 * overlay.bodyPad
            : emptyState.implicitHeight + 2 * overlay.bodyPad + 24

        x: Math.round((overlay.width - overlay.cardWidth) / 2)
        y: overlay.cardTop
        width: overlay.cardWidth
        height: Math.max(overlay.searchHeight + overlay.footerHeight + 120,
                         Math.min(overlay.height - overlay.cardTop - 60,
                                  overlay.searchHeight + 1 + cardArea.bodyHeight + 1 + overlay.footerHeight))

        opacity: overlay.open ? 1 : 0
        visible: opacity > 0
        scale: overlay.open ? 1 : 0.94

        // Drops in a few pixels as it appears, the way the launcher does.
        transform: Translate {
            y: overlay.open ? 0 : -8
            Behavior on y {
                Elastic { small: true }
            }
        }

        Behavior on height {
            Elastic {}
        }

        Behavior on opacity {
            NumberAnimation { duration: 170; easing.type: Easing.OutQuad }
        }

        Behavior on scale {
            Elastic { small: true }
        }

        // The overlays' solid card and shadow, no outline.
        Rectangle {
            id: card
            anchors.fill: parent
            radius: Theme.radiusXLarge
            color: Theme.surface
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.55
            shadowBlur: 1.0
            shadowVerticalOffset: 10
            autoPaddingEnabled: true
        }

        // Swallows clicks on the panel, so only outside closes.
        TapHandler {}

        // ── Search field and tabs ────────────────────────────────────────
        Item {
            id: searchRow
            width: parent.width
            height: overlay.searchHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 13
                spacing: 14

                // In the accent while there is a search running: the field is
                // what is active here. Muted while it is empty.
                IconGlyph {
                    text: "\u{F0349}"
                    color: searchInput.text.length > 0 ? Theme.accent : Theme.textMuted
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
                    font.pixelSize: 20
                    font.family: overlay.fontDisplay
                    selectByMouse: true
                    selectionColor: Theme.alpha(Theme.accent, 0.35)
                    selectedTextColor: Theme.textPrimary
                    cursorDelegate: Component { AccentCaret {} }
                    clip: true
                    focus: overlay.open

                    text: overlay.query
                    onTextChanged: {
                        overlay.query = text
                        flick.contentY = 0
                    }

                    // Escape empties the field first, then closes.
                    Keys.onEscapePressed: {
                        if (overlay.query.length > 0) overlay.query = ""
                        else overlay.close()
                    }
                    Keys.onTabPressed: overlay.showSection(overlay.otherSection())
                    Keys.onBacktabPressed: overlay.showSection(overlay.otherSection())
                    Keys.onUpPressed: overlay.scrollBy(-90)
                    Keys.onDownPressed: overlay.scrollBy(90)
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_PageDown) {
                            overlay.scrollBy(flick.height * 0.8)
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            overlay.scrollBy(-flick.height * 0.8)
                            event.accepted = true
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: "Search shortcuts…"
                        color: Theme.textMuted
                        font.pixelSize: 20
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
                        radius: Theme.radiusMedium
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

                // Hyprland | Yazi: two segments in one pill with the fill
                // sliding between them -- the wallpaper picker's switch. With
                // a search going, each counts its matches, so a miss here and
                // a hit there shows before switching.
                Rectangle {
                    id: sectionSwitch
                    implicitWidth: tabsRow.implicitWidth + 8
                    implicitHeight: 38
                    radius: height / 2
                    color: Theme.alpha(Theme.foreground, 0.06)

                    Rectangle {
                        y: 4
                        height: parent.height - 8
                        radius: height / 2
                        color: Theme.accent
                        x: 4 + (overlay.section === "yazi" ? hyprTab.width : 0)
                        width: overlay.section === "yazi" ? yaziTab.width : hyprTab.width

                        Behavior on x {
                            Elastic { small: true }
                        }
                        Behavior on width {
                            Elastic { small: true }
                        }
                    }

                    Row {
                        id: tabsRow
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: overlay.sections

                            Item {
                                id: tab
                                required property var modelData
                                required property int index
                                readonly property bool selected: overlay.section === tab.modelData.id
                                readonly property int count: overlay.terms.length > 0
                                    ? overlay.shownOf(tab.modelData.id) : overlay.totalOf(tab.modelData.id)

                                width: tabContent.implicitWidth + 28
                                height: sectionSwitch.height - 8
                                // A tab with nothing matching steps back.
                                opacity: tab.selected || tab.count > 0 ? 1 : 0.45

                                Behavior on opacity {
                                    NumberAnimation { duration: Theme.durShort }
                                }

                                Component.onCompleted: {
                                    if (tab.index === 0) hyprTab.width = Qt.binding(() => tab.width)
                                    else yaziTab.width = Qt.binding(() => tab.width)
                                }

                                Row {
                                    id: tabContent
                                    anchors.centerIn: parent
                                    spacing: 7

                                    IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tab.modelData.glyph
                                        size: Theme.iconSmall
                                        color: tab.selected ? Theme.accentText : Theme.textSecondary
                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tab.modelData.name
                                        font.pixelSize: 12
                                        font.bold: tab.selected
                                        font.family: Theme.fontText
                                        color: tab.selected ? Theme.accentText : Theme.textSecondary
                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tab.count
                                        font.pixelSize: 10
                                        font.family: Theme.fontText
                                        font.features: Theme.tabular
                                        color: tab.selected ? Theme.alpha(Theme.accentText, 0.6) : Theme.textMuted
                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                    }
                                }

                                StateLayer {
                                    radius: height / 2
                                    interactive: !tab.selected
                                    onTapped: {
                                        overlay.showSection(tab.modelData.id)
                                        searchInput.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }

                    // Widths of the two segments, for the sliding fill; a
                    // Repeater's items are not reachable by id from outside.
                    QtObject { id: hyprTab; property real width: 0 }
                    QtObject { id: yaziTab; property real width: 0 }
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
        }

        // ── Binds ────────────────────────────────────────────────────────
        Flickable {
            id: flick
            y: searchRow.height + 1
            width: parent.width
            height: parent.height - searchRow.height - 2 - overlay.footerHeight
            contentHeight: cardArea.bodyHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Row {
                id: columnsRow
                x: overlay.bodyPad
                y: overlay.bodyPad
                spacing: overlay.columnGap
                visible: overlay.viewGroups.length > 0

                Repeater {
                    model: overlay.columns

                    Column {
                        id: column
                        required property var modelData
                        required property int index
                        width: overlay.columnWidth
                        spacing: 20

                        opacity: overlay.bodyIn ? 1 : 0

                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: overlay.stagger ? 40 + column.index * 50 : 0 }
                                NumberAnimation {
                                    duration: overlay.stagger ? Theme.durLong : Theme.durShort
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        transform: Translate {
                            y: overlay.bodyIn ? 0 : 10
                            Behavior on y {
                                SequentialAnimation {
                                    PauseAnimation { duration: overlay.stagger ? 40 + column.index * 50 : 0 }
                                    NumberAnimation {
                                        duration: overlay.stagger ? Theme.durLong : Theme.durShort
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: column.modelData

                            // A group, or the part of one this column holds.
                            Column {
                                id: block
                                required property var modelData
                                width: column.width
                                spacing: 2

                                Row {
                                    spacing: 8
                                    bottomPadding: 6

                                    IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: block.modelData.glyph
                                        size: Theme.iconSmall
                                        color: Theme.textMuted
                                    }

                                    SectionLabel {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: block.modelData.name
                                    }

                                    // Carried on from the column before.
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: block.modelData.cont
                                        text: "cont."
                                        color: Theme.alpha(Theme.textMuted, 0.6)
                                        font.pixelSize: 10
                                        font.family: Theme.fontText
                                    }
                                }

                                Repeater {
                                    model: block.modelData.binds

                                    Item {
                                        id: row
                                        required property var modelData
                                        width: block.width
                                        height: Math.max(32, rowText.implicitHeight + 12)

                                        // Only a highlight: the sheet shows keys,
                                        // it does not run them.
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.leftMargin: -10
                                            anchors.rightMargin: -10
                                            radius: Theme.radiusMedium
                                            color: Theme.foreground
                                            opacity: rowHover.hovered ? 0.06 : 0

                                            Behavior on opacity {
                                                NumberAnimation { duration: Theme.durShort }
                                            }
                                        }

                                        HoverHandler { id: rowHover }

                                        Column {
                                            id: rowText
                                            anchors.left: parent.left
                                            anchors.right: combo.left
                                            anchors.rightMargin: 14
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            Text {
                                                width: parent.width
                                                text: overlay.highlight(row.modelData.action)
                                                textFormat: Text.StyledText
                                                color: Theme.textPrimary
                                                font.pixelSize: 13
                                                font.family: overlay.fontText
                                                elide: Text.ElideRight
                                            }

                                            // What actually runs, for the binds
                                            // whose label names a command rather
                                            // than being one.
                                            Text {
                                                visible: row.modelData.command.length > 0
                                                width: parent.width
                                                text: row.modelData.command
                                                color: Theme.textMuted
                                                font.pixelSize: 10
                                                font.family: Theme.fontText
                                                elide: Text.ElideRight
                                            }
                                        }

                                        KeyCombo {
                                            id: combo
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            caps: row.modelData.caps
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Nothing to show: the reader error, no binds at all, or a search
            // that found nothing here -- and, when the other tab has matches,
            // how many and how to get there.
            Column {
                id: emptyState
                visible: overlay.viewGroups.length === 0
                width: flick.width
                y: overlay.bodyPad + 12
                spacing: 12

                IconGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: overlay.viewError.length > 0 ? "\u{F0028}" : "\u{F0349}"
                    color: overlay.viewError.length > 0 ? Theme.error : Theme.textMuted
                    size: 28
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, parent.width - 80)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: overlay.viewError.length > 0 ? overlay.viewError
                        : overlay.terms.length > 0 ? "Nothing in " + (overlay.viewSection === "yazi" ? "Yazi" : "Hyprland")
                                                     + " matches “" + overlay.query.trim() + "”"
                        : "No shortcuts configured"
                    color: overlay.viewError.length > 0 ? Theme.error : Theme.textSecondary
                    font.pixelSize: 14
                    font.family: overlay.fontText
                }

                KeyHint {
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property int elsewhere: overlay.terms.length > 0 ? overlay.shownOf(overlay.otherSection()) : 0
                    visible: elsewhere > 0
                    key: "tab"
                    label: elsewhere + (elsewhere === 1 ? " match in " : " matches in ")
                           + (overlay.otherSection() === "yazi" ? "Yazi" : "Hyprland")
                }
            }
        }

        // Where in a long list the view is: a thin thumb at the right edge,
        // only when there is more than fits.
        Rectangle {
            visible: flick.interactive
            x: parent.width - 9
            width: 3
            radius: 1.5
            color: Theme.textMuted
            opacity: flick.moving || scrollAnim.running ? 0.7 : 0.3
            readonly property real track: flick.height - 16
            height: Math.max(28, track * flick.height / Math.max(1, flick.contentHeight))
            y: flick.y + 8 + (track - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))

            Behavior on opacity {
                NumberAnimation { duration: Theme.durMedium }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────
        Rectangle {
            y: flick.y + flick.height
            x: 1
            width: parent.width - 2
            height: 1
            color: Theme.outline
        }

        Item {
            y: flick.y + flick.height + 1
            width: parent.width
            height: overlay.footerHeight

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                KeyHint { key: "tab"; label: overlay.otherSection() === "yazi" ? "Yazi" : "Hyprland" }
                KeyHint { key: "↑ ↓"; label: "Scroll"; visible: flick.interactive }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property int shown: overlay.shownOf(overlay.viewSection)
                    readonly property int total: overlay.totalOf(overlay.viewSection)
                    text: overlay.terms.length > 0 ? shown + " of " + total : total + " shortcuts"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }

                KeyHint { key: "esc"; label: overlay.query.length > 0 ? "Clear" : "Close" }
            }
        }
    }
}
