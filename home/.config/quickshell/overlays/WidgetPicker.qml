import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.components
import qs.config
import qs.desktop
import qs.services

// The widget picker (Super + D): where desktop widgets are put on, moved
// and taken off.
//
// While it is up, this monitor's desktop is drawn here, over the windows
// and a scrim -- the widgets live under every window (desktop/DesktopLayer),
// where most of the time they cannot be seen, let alone grabbed. Each one can
// be dragged to a new place or taken off with its minus; the panel on the
// left holds every kind, to drag out onto the desktop or click to drop into
// the first gap. "On desktop" lists what is placed, on every monitor.
//
// Dragging happens inside this one surface: a widget carried out of the panel
// never crosses into another window, which Wayland would not allow.
PanelWindow {
    id: picker

    property var bar: null
    screen: bar.screen

    readonly property string screenName: bar.monitor ? bar.monitor.name : ""

    // ── Visibility ───────────────────────────────────────────────────────
    //
    // As for the other overlays: one per monitor, the one it was opened on
    // shows, and `shown` holds the surface mapped until the fade has played.
    readonly property bool onOpeningScreen: {
        if (!bar.monitor) return true
        if (Panels.widgetsScreen === "") return bar.monitor.focused
        return bar.monitor.name === Panels.widgetsScreen
    }
    readonly property bool open: Panels.widgetsOpen && picker.onOpeningScreen

    property bool shown: false
    visible: picker.shown

    Timer {
        id: unmapDelay
        interval: Theme.durMedium + 80
        onTriggered: picker.shown = false
    }

    Connections {
        target: picker
        function onOpenChanged() {
            if (picker.open) {
                unmapDelay.stop()
                picker.query = ""
                picker.tab = "add"
                picker.category = ""
                picker.selected = 0
                picker.lastAdded = ""
                picker.shown = true
            } else {
                ghost.active = false
                unmapDelay.restart()
            }
        }
    }

    color: "transparent"

    WlrLayershell.namespace: "quickshell:widgets"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    // Exclusive while mapped, for the search field; held through the fade,
    // since changing it on a mapped surface drops that surface for a frame.
    WlrLayershell.keyboardFocus: picker.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: picker.open ? null : blankMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    function close() { Panels.widgetsOpen = false }

    // ── Geometry ─────────────────────────────────────────────────────────

    readonly property int panelWidth: 404
    readonly property int panelMargin: 16
    // How near the edges a widget may go, and how far below the bar.
    readonly property int edge: 24
    readonly property int topEdge: (bar.stripHeight || 56) + 16
    // Widgets land on an 8px grid, so two dropped side by side line up
    // without being nudged pixel by pixel.
    readonly property int grid: 8

    function snap(v) { return Math.round(v / picker.grid) * picker.grid }
    function clampX(x, w) { return Math.max(picker.edge, Math.min(picker.width - picker.edge - w, x)) }
    function clampY(y, h) { return Math.max(picker.topEdge, Math.min(picker.height - picker.edge - h, y)) }

    // ── What the panel shows ─────────────────────────────────────────────

    property string query: ""
    property string tab: "add"          // "add" or "placed"
    property string category: ""        // "" for all
    property int selected: 0
    // The id of the widget added last, which springs in as it lands.
    property string lastAdded: ""

    readonly property var matches: {
        var words = picker.query.toLowerCase().split(/\s+/).filter(w => w.length > 0)
        return Widgets.catalog.filter(k => {
            if (picker.category !== "" && k.category !== picker.category) return false
            var hay = (k.name + " " + k.category + " " + k.description).toLowerCase()
            return words.every(w => hay.indexOf(w) !== -1)
        })
    }

    onMatchesChanged: picker.selected = Math.max(0, Math.min(picker.selected, picker.matches.length - 1))

    function addKind(kind) {
        var spec = Widgets.spec(kind)
        if (!spec) return
        var spot = Widgets.freeSpot(picker.screenName, spec.w, spec.h, picker.width, picker.height, picker.topEdge)
        picker.lastAdded = Widgets.add(kind, picker.screenName, spot.x, spot.y)
    }

    // The panel's insides are loaded only while it is up, so they are told
    // rather than reached into: scroll the card list to the selection.
    signal revealRequested(int index)

    function moveSelection(step) {
        if (picker.tab !== "add" || picker.matches.length === 0) return
        picker.selected = Math.max(0, Math.min(picker.matches.length - 1, picker.selected + step))
        picker.revealRequested(picker.selected)
    }

    function nameOf(kind) {
        var s = Widgets.spec(kind)
        return s ? s.name : kind
    }

    function glyphOf(category) {
        switch (category) {
        case "Clock": return "\u{F0150}"
        case "Calendar": return "\u{F00ED}"
        case "Weather": return "\u{F0595}"
        case "Media": return "\u{F0387}"
        case "System": return "\u{F035B}"
        }
        return "\u{F0379}"
    }

    // ── Pieces ───────────────────────────────────────────────────────────

    component KeyCap: Rectangle {
        id: cap
        property string key: ""
        width: Math.max(18, capText.implicitWidth + 10)
        height: 18
        radius: 5
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.outline

        Text {
            id: capText
            anchors.centerIn: parent
            text: cap.key
            color: Theme.textSecondary
            font.pixelSize: 10
            font.family: Theme.fontMono
        }
    }

    component KeyHint: Row {
        id: hint
        property string key: ""
        property string label: ""
        spacing: 6

        KeyCap { anchors.verticalCenter: parent.verticalCenter; key: hint.key }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.label
            color: Theme.textMuted
            font.pixelSize: 11
            font.family: Theme.fontText
        }
    }

    // ── The desktop being edited ─────────────────────────────────────────

    // The dim over the windows. A click on it does nothing: the picker is
    // closed with Done or Escape, never by a stray click beside a widget.
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: picker.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        MouseArea { anchors.fill: parent }
    }

    Item {
        id: desk
        anchors.fill: parent
        opacity: picker.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }

        Loader {
            anchors.fill: parent
            active: picker.shown

            sourceComponent: Item {
                WidgetModel {
                    id: placedModel
                    screenName: picker.screenName
                }

                Repeater {
                    model: placedModel

                    Item {
                        id: placed

                        readonly property string uid: model.uid
                        readonly property string kind: model.kind
                        property bool dragging: false
                        property real dragX: 0
                        property real dragY: 0
                        property bool leaving: false
                        // Lands with a spring when it is the one just added;
                        // the rest are simply there when the picker opens.
                        property bool arrived: picker.lastAdded !== placed.uid

                        width: host.width
                        height: host.height
                        x: placed.dragging ? placed.dragX : model.wx
                        y: placed.dragging ? placed.dragY : model.wy
                        z: placed.dragging ? 2 : 1

                        // Carried: lifted a little, with a shadow under it. Let
                        // go: it springs into the grid spot it was dropped on.
                        scale: placed.leaving ? 0.85 : !placed.arrived ? 0.9 : placed.dragging ? 1.03 : 1
                        opacity: placed.leaving || !placed.arrived ? 0 : 1

                        Behavior on x { enabled: !placed.dragging; Elastic { small: true } }
                        Behavior on y { enabled: !placed.dragging; Elastic { small: true } }
                        Behavior on scale { Elastic { small: true } }
                        Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }

                        Component.onCompleted: if (!placed.arrived) arriveTimer.start()

                        Timer {
                            id: arriveTimer
                            interval: 16
                            onTriggered: placed.arrived = true
                        }

                        RectangularShadow {
                            anchors.fill: host
                            radius: host.kind === "clock-analog" || host.kind === "clock-pill" ? height / 2 : Theme.radiusXLarge
                            blur: 28
                            offset.y: 10
                            color: Theme.alpha(Theme.shadow, 0.5)
                            opacity: placed.dragging ? 1 : 0

                            Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                        }

                        WidgetHost {
                            id: host
                            kind: placed.kind
                            bar: picker.bar
                            live: picker.open
                        }

                        MouseArea {
                            id: grab
                            anchors.fill: parent
                            preventStealing: true
                            cursorShape: placed.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property point from: Qt.point(0, 0)

                            onPressed: mouse => {
                                grab.from = Qt.point(mouse.x, mouse.y)
                                placed.dragX = placed.x
                                placed.dragY = placed.y
                            }
                            onPositionChanged: mouse => {
                                if (!pressed) return
                                var p = grab.mapToItem(desk, mouse.x, mouse.y)
                                if (!placed.dragging && Math.abs(mouse.x - grab.from.x) + Math.abs(mouse.y - grab.from.y) < 6)
                                    return
                                placed.dragging = true
                                placed.dragX = picker.clampX(p.x - grab.from.x, placed.width)
                                placed.dragY = picker.clampY(p.y - grab.from.y, placed.height)
                            }
                            onReleased: {
                                if (!placed.dragging) return
                                Widgets.move(placed.uid, picker.clampX(picker.snap(placed.dragX), placed.width),
                                             picker.clampY(picker.snap(placed.dragY), placed.height))
                                placed.dragging = false
                            }
                        }

                        // Takes it off the desktop.
                        Rectangle {
                            x: placed.kind === "clock-analog" ? 14 : -8
                            y: placed.kind === "clock-analog" ? 14 : -8
                            width: 26
                            height: 26
                            radius: height / 2
                            color: removeState.hovered ? Theme.error : Theme.textPrimary
                            opacity: placed.dragging ? 0 : 1

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                            Behavior on opacity { NumberAnimation { duration: Theme.durShort } }

                            IconGlyph {
                                anchors.centerIn: parent
                                text: "\u{F0374}"
                                color: Theme.inkOn(removeState.hovered ? Theme.error : Theme.textPrimary)
                                size: Theme.iconSmall
                            }

                            StateLayer {
                                id: removeState
                                hitMargin: 4
                                tint: Theme.background
                                onTapped: {
                                    placed.leaving = true
                                    removeLater.start()
                                }
                            }

                            Timer {
                                id: removeLater
                                interval: Theme.durMedium
                                onTriggered: Widgets.remove(placed.uid)
                            }
                        }
                    }
                }
            }
        }
    }

    // A widget being dragged out of the panel, at full size under the
    // pointer. Over the panel it pales: let go there and nothing is added.
    Item {
        id: ghost
        property string kind: ""
        property bool active: false
        property bool overPanel: false
        z: 10
        visible: ghost.active
        width: ghostHost.width
        height: ghostHost.height
        opacity: ghost.overPanel ? 0.45 : 1
        scale: ghost.active ? 1.03 : 0.9

        Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
        Behavior on scale { Elastic { small: true } }

        RectangularShadow {
            anchors.fill: ghostHost
            radius: ghost.kind === "clock-analog" || ghost.kind === "clock-pill" ? height / 2 : Theme.radiusXLarge
            blur: 28
            offset.y: 10
            color: Theme.alpha(Theme.shadow, 0.5)
        }

        WidgetHost {
            id: ghostHost
            kind: ghost.kind
            bar: picker.bar
            live: false
        }

        function follow(p) {
            ghost.x = p.x - ghost.width / 2
            ghost.y = p.y - ghost.height / 2
            ghost.overPanel = p.x < panel.x + panel.width + 8
        }

        function drop() {
            if (!ghost.active) return
            ghost.active = false
            if (ghost.overPanel) return
            picker.lastAdded = Widgets.add(ghost.kind, picker.screenName,
                picker.clampX(picker.snap(ghost.x), ghost.width), picker.clampY(picker.snap(ghost.y), ghost.height))
        }
    }

    // ── The panel ────────────────────────────────────────────────────────

    Item {
        id: panel
        x: picker.open ? picker.panelMargin : picker.panelMargin - 24
        y: picker.panelMargin
        width: picker.panelWidth
        height: picker.height - 2 * picker.panelMargin
        opacity: picker.open ? 1 : 0

        // Arrives on the spring from the edge it is attached to; leaves as a
        // plain fade.
        Behavior on x { Elastic {} }
        Behavior on opacity { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }

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

        // Swallows clicks on the panel's own empty parts.
        MouseArea { anchors.fill: parent }

        Loader {
            anchors.fill: parent
            active: picker.shown
            sourceComponent: panelBody
        }
    }

    Component {
        id: panelBody

        Item {
            // Header: what this is and how it is used.
            Item {
                id: header
                x: 20
                y: 20
                width: parent.width - 40
                height: 44

                Rectangle {
                    id: badge
                    width: 40
                    height: 40
                    radius: Theme.radiusMedium
                    color: Theme.surfaceContainer

                    IconGlyph {
                        anchors.centerIn: parent
                        text: "\u{F0573}"
                        color: Theme.textPrimary
                        size: Theme.iconLarge
                    }
                }

                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.right: closeButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: badge.verticalCenter
                    spacing: 1

                    Text {
                        text: "Widgets"
                        color: Theme.textPrimary
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        font.family: Theme.fontText
                    }

                    Text {
                        width: parent.width
                        text: picker.tab === "add" ? "Drag one onto the desktop, or click to add it."
                                                   : "Drag them where you want; the minus takes one off."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }
                }

                IconButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: badge.verticalCenter
                    icon: "\u{F0156}"
                    size: 30
                    glyphSize: Theme.iconSmall
                    onTapped: picker.close()
                }
            }

            // Search.
            Rectangle {
                id: searchBox
                x: 20
                anchors.top: header.bottom
                anchors.topMargin: 18
                width: parent.width - 40
                height: 44
                radius: Theme.radiusMedium
                color: Theme.surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 10

                    IconGlyph {
                        text: "\u{F0349}"
                        color: search.text.length > 0 ? Theme.accent : Theme.textMuted
                        size: Theme.iconMedium

                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                    }

                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.family: Theme.fontText
                        selectByMouse: true
                        selectionColor: Theme.alpha(Theme.accent, 0.35)
                        selectedTextColor: Theme.textPrimary
                        cursorDelegate: Component { AccentCaret {} }
                        clip: true
                        focus: true

                        Component.onCompleted: search.forceActiveFocus()

                        text: picker.query
                        onTextChanged: {
                            picker.query = text
                            if (text.length > 0) picker.tab = "add"
                        }

                        Keys.onEscapePressed: {
                            if (search.text.length > 0) picker.query = ""
                            else picker.close()
                        }
                        Keys.onLeftPressed: event => {
                            if (search.text.length > 0) { event.accepted = false; return }
                            picker.moveSelection(-1)
                        }
                        Keys.onRightPressed: event => {
                            if (search.text.length > 0) { event.accepted = false; return }
                            picker.moveSelection(1)
                        }
                        Keys.onUpPressed: picker.moveSelection(-2)
                        Keys.onDownPressed: picker.moveSelection(2)
                        Keys.onTabPressed: picker.tab = picker.tab === "add" ? "placed" : "add"
                        Keys.onBacktabPressed: picker.tab = picker.tab === "add" ? "placed" : "add"
                        onAccepted: if (picker.tab === "add" && picker.matches.length > 0)
                                        picker.addKind(picker.matches[picker.selected].kind)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: search.text.length === 0
                            text: "Search widgets"
                            color: Theme.textMuted
                            font.pixelSize: 14
                            font.family: Theme.fontText
                        }
                    }
                }
            }

            // The two tabs: one pill, the chosen half filled in the accent,
            // the fill sliding between them.
            Rectangle {
                id: tabs
                x: 20
                anchors.top: searchBox.bottom
                anchors.topMargin: 14
                width: parent.width - 40
                height: 36
                radius: height / 2
                color: Theme.surfaceContainer

                Rectangle {
                    x: 4 + (picker.tab === "placed" ? (tabs.width - 8) / 2 : 0)
                    y: 4
                    width: (tabs.width - 8) / 2
                    height: parent.height - 8
                    radius: height / 2
                    color: Theme.accent

                    Behavior on x { Elastic { small: true } }
                }

                Row {
                    x: 4
                    y: 4

                    Repeater {
                        model: [
                            { id: "add", label: "Add", glyph: "\u{F0415}" },
                            { id: "placed", label: "On desktop", glyph: "\u{F0379}" }
                        ]

                        Item {
                            id: tabItem
                            required property var modelData
                            readonly property bool chosen: picker.tab === tabItem.modelData.id
                            width: (tabs.width - 8) / 2
                            height: tabs.height - 8

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                IconGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabItem.modelData.glyph
                                    color: tabItem.chosen ? Theme.accentText : Theme.textSecondary
                                    size: Theme.iconSmall
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabItem.modelData.label
                                          + (tabItem.modelData.id === "placed" && Widgets.placed.length > 0
                                             ? "  " + Widgets.placed.length : "")
                                    color: tabItem.chosen ? Theme.accentText : Theme.textSecondary
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    font.family: Theme.fontText
                                    font.features: Theme.tabular
                                }
                            }

                            StateLayer {
                                radius: height / 2
                                interactive: !tabItem.chosen
                                onTapped: {
                                    picker.tab = tabItem.modelData.id
                                    search.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }

            // Categories, for the Add tab.
            Flow {
                id: chips
                visible: picker.tab === "add"
                x: 20
                anchors.top: tabs.bottom
                anchors.topMargin: 14
                width: parent.width - 40
                spacing: 6

                Repeater {
                    model: [""].concat(Widgets.categories)

                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool chosen: picker.category === chip.modelData
                        width: chipText.implicitWidth + 24
                        height: 30
                        radius: height / 2
                        color: chip.chosen ? Theme.accent : Theme.surfaceContainer

                        Behavior on color { ColorAnimation { duration: Theme.durShort } }

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData === "" ? "All" : chip.modelData
                            color: chip.chosen ? Theme.accentText : Theme.textSecondary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.family: Theme.fontText
                        }

                        StateLayer {
                            interactive: !chip.chosen
                            onTapped: {
                                picker.category = chip.modelData
                                search.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            // ── Add: every kind, as it will look ─────────────────────────
            Flickable {
                id: cards
                visible: picker.tab === "add"
                x: 20
                anchors.top: chips.bottom
                anchors.topMargin: 16
                anchors.bottom: footer.top
                anchors.bottomMargin: 8
                width: parent.width - 40
                contentHeight: cardGrid.height + 8
                clip: true
                // Dragging a card carries the widget out; the list moves by
                // the wheel (below) and by the keyboard selection instead.
                interactive: false

                Connections {
                    target: picker
                    function onRevealRequested(index) { cards.reveal(index) }
                }

                function reveal(index) {
                    var item = cardRepeater.itemAt(index)
                    if (!item) return
                    var top = item.y, bottom = item.y + item.height
                    var to = cards.contentY
                    if (top < cards.contentY) to = top
                    else if (bottom > cards.contentY + cards.height) to = bottom - cards.height
                    scrollTo.to = Math.max(0, Math.min(to, cards.contentHeight - cards.height))
                    scrollTo.restart()
                }

                NumberAnimation {
                    id: scrollTo
                    target: cards
                    property: "contentY"
                    duration: Theme.durMedium
                    easing.type: Easing.OutCubic
                }

                Grid {
                    id: cardGrid
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 12

                    Repeater {
                        id: cardRepeater
                        model: picker.matches

                        Rectangle {
                            id: kindCard
                            required property var modelData
                            required property int index
                            readonly property bool current: picker.selected === kindCard.index
                            readonly property int placedCount: Widgets.countOf(kindCard.modelData.kind)
                            width: (cards.width - 12) / 2
                            height: 206
                            radius: Theme.radiusLarge
                            color: kindCard.current || cardMouse.containsMouse ? Theme.surfaceContainerHigh
                                                                              : Theme.surfaceContainer
                            // The keyboard's place, drawn as a ring in the accent:
                            // the one outline here, because it is the focus.
                            border.width: kindCard.current ? 2 : 0
                            border.color: Theme.accent

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                            // The real widget, scaled down to fit.
                            Item {
                                id: previewBox
                                x: 10
                                y: 10
                                width: parent.width - 20
                                height: 112

                                WidgetHost {
                                    id: preview
                                    anchors.centerIn: parent
                                    kind: kindCard.modelData.kind
                                    bar: picker.bar
                                    live: picker.open
                                    scale: Math.min(previewBox.width / preview.width, previewBox.height / preview.height, 1)
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: previewBox.bottom
                                anchors.margins: 12
                                anchors.topMargin: 10
                                spacing: 3

                                Text {
                                    width: parent.width
                                    text: kindCard.modelData.name
                                    color: Theme.textPrimary
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.family: Theme.fontText
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: kindCard.modelData.description
                                    color: Theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: Theme.fontText
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: kindCard.placedCount > 0
                                    text: kindCard.placedCount === 1 ? "1 on the desktop"
                                                                     : kindCard.placedCount + " on the desktop"
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.family: Theme.fontText
                                    font.features: Theme.tabular
                                }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: ghost.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                property point from: Qt.point(0, 0)

                                onPressed: mouse => cardMouse.from = Qt.point(mouse.x, mouse.y)
                                onPositionChanged: mouse => {
                                    // Hover steers the selection only when the
                                    // pointer really moves, so a still pointer
                                    // under scrolling cards leaves the keys' pick.
                                    if (!pressed) {
                                        picker.selected = kindCard.index
                                        return
                                    }
                                    var p = cardMouse.mapToItem(picker.contentItem, mouse.x, mouse.y)
                                    if (!ghost.active) {
                                        if (Math.abs(mouse.x - cardMouse.from.x) + Math.abs(mouse.y - cardMouse.from.y) < 6) return
                                        ghost.kind = kindCard.modelData.kind
                                        ghost.active = true
                                    }
                                    ghost.follow(p)
                                }
                                onReleased: {
                                    if (ghost.active) ghost.drop()
                                    else picker.addKind(kindCard.modelData.kind)
                                    search.forceActiveFocus()
                                }
                                onCanceled: ghost.active = false
                            }
                        }
                    }
                }

                Text {
                    visible: picker.matches.length === 0
                    width: cards.width
                    topPadding: 24
                    horizontalAlignment: Text.AlignHCenter
                    text: "No widget matches “" + picker.query + "”. Try a category instead."
                    color: Theme.textMuted
                    font.pixelSize: 12
                    font.family: Theme.fontText
                    wrapMode: Text.WordWrap
                }
            }

            // ── On desktop: what is placed, on every monitor ─────────────
            Flickable {
                id: placedList
                visible: picker.tab === "placed"
                x: 20
                anchors.top: tabs.bottom
                anchors.topMargin: 16
                anchors.bottom: footer.top
                anchors.bottomMargin: 8
                width: parent.width - 40
                contentHeight: placedColumn.height
                clip: true
                interactive: false

                Column {
                    id: placedColumn
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: Widgets.placed

                        Rectangle {
                            id: placedRow
                            required property var modelData
                            readonly property var spec: Widgets.spec(placedRow.modelData.kind)
                            visible: placedRow.spec !== null
                            width: placedColumn.width
                            height: 52
                            radius: Theme.radiusMedium
                            color: Theme.surfaceContainer

                            IconGlyph {
                                id: rowGlyph
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: picker.glyphOf(placedRow.spec ? placedRow.spec.category : "")
                                color: Theme.textSecondary
                                size: Theme.iconMedium
                            }

                            Column {
                                anchors.left: rowGlyph.right
                                anchors.leftMargin: 14
                                anchors.right: rowRemove.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: placedRow.spec ? placedRow.spec.name : ""
                                    color: Theme.textPrimary
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    font.family: Theme.fontText
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: (placedRow.spec ? placedRow.spec.category : "") + "  ·  "
                                          + (placedRow.modelData.screen === picker.screenName ? "This screen"
                                                                                              : placedRow.modelData.screen)
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.family: Theme.fontText
                                    elide: Text.ElideRight
                                }
                            }

                            IconButton {
                                id: rowRemove
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "\u{F0374}"
                                size: 32
                                glyphSize: Theme.iconSmall
                                onTapped: Widgets.remove(placedRow.modelData.id)
                            }
                        }
                    }

                    Text {
                        visible: Widgets.placed.length === 0
                        width: parent.width
                        topPadding: 24
                        horizontalAlignment: Text.AlignHCenter
                        text: "Nothing on the desktop yet. Add one from the Add tab."
                        color: Theme.textMuted
                        font.pixelSize: 12
                        font.family: Theme.fontText
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // The wheel moves either list a fixed step a notch, as in the
            // launcher; neither Flickable takes the pointer itself.
            MouseArea {
                anchors.fill: picker.tab === "add" ? cards : placedList
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    var list = picker.tab === "add" ? cards : placedList
                    if (wheel.angleDelta.y === 0) return
                    var max = Math.max(0, list.contentHeight - list.height)
                    wheelScroll.target = list
                    var from = wheelScroll.running ? wheelScroll.to : list.contentY
                    wheelScroll.to = Math.max(0, Math.min(max, from - wheel.angleDelta.y / 120 * 120))
                    wheelScroll.restart()
                }
            }

            NumberAnimation {
                id: wheelScroll
                property: "contentY"
                duration: Theme.durMedium
                easing.type: Easing.OutCubic
            }

            // Keys, and Done.
            Item {
                id: footer
                x: 20
                width: parent.width - 40
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                height: 40

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    KeyHint { key: "esc"; label: picker.query.length > 0 ? "Clear" : "Close" }
                    KeyHint { key: "tab"; label: picker.tab === "add" ? "On desktop" : "Add" }
                    KeyHint { key: "↵"; label: "Add"; visible: picker.tab === "add" && picker.matches.length > 0 }
                }

                // Done, in the text colour like the shell's other primary
                // buttons; the accent stays on what is chosen.
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: doneRow.implicitWidth + 32
                    height: 36
                    radius: height / 2
                    color: Theme.textPrimary

                    Row {
                        id: doneRow
                        anchors.centerIn: parent
                        spacing: 6

                        IconGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{F012C}"
                            color: Theme.inkOn(Theme.textPrimary)
                            size: Theme.iconSmall
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Done"
                            color: Theme.inkOn(Theme.textPrimary)
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.family: Theme.fontText
                        }
                    }

                    StateLayer {
                        tint: Theme.inkOn(Theme.textPrimary)
                        onTapped: picker.close()
                    }
                }
            }
        }
    }
}
