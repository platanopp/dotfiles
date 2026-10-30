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
// be dragged to a new place or taken off with its minus. Every kind waits on
// a shelf along the bottom, drawn as it will look and in its own shape, the
// way the overview lines up workspaces: drag one up onto the desktop, or
// click it to drop it into the first gap.
//
// Dragging happens inside this one surface: a widget carried off the shelf
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
                picker.category = ""
                picker.selected = 0
                picker.lastAdded = ""
                picker.shown = true
            } else {
                ghost.active = false
                picker.movingPlaced = false
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

    // How near the edges a widget may go, and how far below the bar.
    readonly property int edge: 24
    readonly property int topEdge: (bar.stripHeight || 56) + 16
    // Widgets land on an 8px grid, so two dropped side by side line up
    // without being nudged pixel by pixel.
    readonly property int grid: 8

    function snap(v) { return Math.round(v / picker.grid) * picker.grid }
    function clampX(x, w) { return Math.max(picker.edge, Math.min(picker.width - picker.edge - w, x)) }
    function clampY(y, h) { return Math.max(picker.topEdge, Math.min(picker.height - picker.edge - h, y)) }

    // The shelf. Each kind is shown whole, scaled to one height, so the
    // shelf reads as the widgets themselves in their own shapes -- the clock
    // pill long and low, the analog clock round -- rather than as a grid of
    // same-sized cards. The widest are held to `previewWidthMax`.
    readonly property int shelfMargin: 24
    readonly property int shelfHeight: 296
    readonly property int shelfTop: picker.height - picker.shelfMargin - picker.shelfHeight
    readonly property int previewHeight: 112
    readonly property int previewWidthMax: 200
    readonly property int tileGap: 10

    function previewScale(s) { return Math.min(1, picker.previewHeight / s.h, picker.previewWidthMax / s.w) }
    function tileWidth(s) { return Math.max(Math.round(s.w * picker.previewScale(s)), 84) + 24 }

    // Every kind side by side, filter or not, so the shelf keeps its width
    // while the categories change what is on it.
    readonly property int stripWidth: Widgets.catalog.reduce((sum, s) => sum + picker.tileWidth(s), 0)
                                      + (Widgets.catalog.length - 1) * picker.tileGap

    // ── What the shelf shows ─────────────────────────────────────────────

    property string query: ""
    property string category: ""        // "" for all
    property int selected: 0
    // The id of the widget added last, which springs in as it lands.
    property string lastAdded: ""
    // A placed widget is being dragged: the shelf pales so the desktop
    // under it shows where it can go.
    property bool movingPlaced: false

    readonly property var categoryList: [""].concat(Widgets.categories)
    readonly property int categoryIndex: Math.max(0, picker.categoryList.indexOf(picker.category))

    readonly property var matches: {
        var words = picker.query.toLowerCase().split(/\s+/).filter(w => w.length > 0)
        return Widgets.catalog.filter(k => {
            if (picker.category !== "" && k.category !== picker.category) return false
            var hay = (k.name + " " + k.category + " " + k.description).toLowerCase()
            return words.every(w => hay.indexOf(w) !== -1)
        })
    }

    onMatchesChanged: {
        picker.selected = Math.max(0, Math.min(picker.selected, picker.matches.length - 1))
        // After the shelf has its new tiles, not before.
        Qt.callLater(() => picker.revealRequested(picker.selected))
    }

    function addKind(kind) {
        var spec = Widgets.spec(kind)
        if (!spec) return
        // Only above the shelf: one dropped under it would seem not to
        // have arrived.
        var spot = Widgets.freeSpot(picker.screenName, spec.w, spec.h, picker.width, picker.shelfTop, picker.topEdge)
        picker.lastAdded = Widgets.add(kind, picker.screenName, spot.x, spot.y)
    }

    function setCategory(c) {
        picker.category = c
        picker.selected = 0
    }

    function cycleCategory(step) {
        var n = picker.categoryList.length
        picker.setCategory(picker.categoryList[(picker.categoryIndex + step + n) % n])
    }

    // The shelf's insides are loaded only while it is up, so they are told
    // rather than reached into: scroll the strip to the selection.
    signal revealRequested(int index)

    function moveSelection(step) {
        if (picker.matches.length === 0) return
        picker.selected = Math.max(0, Math.min(picker.matches.length - 1, picker.selected + step))
        picker.revealRequested(picker.selected)
    }

    // ── The desktop being edited ─────────────────────────────────────────

    // The dim over the windows. A click on it does nothing: the picker is
    // closed with its close button or Escape, never by a stray click beside
    // a widget.
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
                                picker.movingPlaced = true
                                placed.dragX = picker.clampX(p.x - grab.from.x, placed.width)
                                placed.dragY = picker.clampY(p.y - grab.from.y, placed.height)
                            }
                            onReleased: {
                                picker.movingPlaced = false
                                if (!placed.dragging) return
                                Widgets.move(placed.uid, picker.clampX(picker.snap(placed.dragX), placed.width),
                                             picker.clampY(picker.snap(placed.dragY), placed.height))
                                placed.dragging = false
                            }
                            onCanceled: {
                                picker.movingPlaced = false
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

    // A widget being dragged off the shelf, at full size under the pointer.
    // Over the shelf it pales: let go there and nothing is added.
    Item {
        id: ghost
        property string kind: ""
        property bool active: false
        property bool overShelf: false
        z: 10
        visible: ghost.active
        width: ghostHost.width
        height: ghostHost.height
        opacity: ghost.overShelf ? 0.45 : 1
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
            ghost.overShelf = p.y > shelf.y - 8
        }

        function drop() {
            if (!ghost.active) return
            ghost.active = false
            if (ghost.overShelf) return
            picker.lastAdded = Widgets.add(ghost.kind, picker.screenName,
                picker.clampX(picker.snap(ghost.x), ghost.width), picker.clampY(picker.snap(ghost.y), ghost.height))
        }
    }

    // ── The shelf ────────────────────────────────────────────────────────
    //
    // Along the bottom, centred, as wide as the kinds need and the screen
    // allows. It rises on the spring and leaves as a fade; while a widget is
    // carried above it, it pales, so the desktop under it shows where that
    // widget could land.
    Item {
        id: shelf
        width: Math.min(picker.width - 2 * picker.shelfMargin, picker.stripWidth + 40)
        height: picker.shelfHeight
        x: Math.round((picker.width - width) / 2)
        y: picker.open ? picker.shelfTop : picker.shelfTop + 32
        opacity: !picker.open ? 0
                 : picker.movingPlaced || (ghost.active && !ghost.overShelf) ? 0.35 : 1

        Behavior on y { Elastic {} }
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

        // Swallows clicks on the shelf's own empty parts.
        MouseArea { anchors.fill: parent }

        Loader {
            anchors.fill: parent
            active: picker.shown
            sourceComponent: shelfBody
        }
    }

    Component {
        id: shelfBody

        Item {
            // ── Top row: name, categories, search, close ─────────────────
            Item {
                id: topRow
                x: 20
                y: 18
                width: parent.width - 40
                height: 36

                Text {
                    id: title
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Widgets"
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    font.family: Theme.fontText
                }

                // The categories as one pill, the chosen one filled in the
                // accent and the fill sliding to the next, as the tabs do
                // elsewhere in the shell.
                Rectangle {
                    id: segments
                    anchors.left: title.right
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: segRow.width + 8
                    height: 36
                    radius: height / 2
                    color: Theme.surfaceContainer

                    Rectangle {
                        readonly property Item at: segRepeater.count > 0 ? segRepeater.itemAt(picker.categoryIndex) : null
                        x: 4 + (at ? at.x : 0)
                        y: 4
                        width: at ? at.width : 0
                        height: parent.height - 8
                        radius: height / 2
                        color: Theme.accent

                        Behavior on x { Elastic { small: true } }
                        Behavior on width { Elastic { small: true } }
                    }

                    Row {
                        id: segRow
                        x: 4
                        y: 4

                        Repeater {
                            id: segRepeater
                            model: picker.categoryList

                            Item {
                                id: seg
                                required property var modelData
                                readonly property bool chosen: picker.category === seg.modelData
                                width: segText.implicitWidth + 28
                                height: segments.height - 8

                                Text {
                                    id: segText
                                    anchors.centerIn: parent
                                    text: seg.modelData === "" ? "All" : seg.modelData
                                    color: seg.chosen ? Theme.accentText : Theme.textSecondary
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    font.family: Theme.fontText

                                    Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                }

                                StateLayer {
                                    radius: height / 2
                                    interactive: !seg.chosen
                                    onTapped: {
                                        picker.setCategory(seg.modelData)
                                        search.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }
                }

                IconButton {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "\u{F0156}"
                    size: 30
                    glyphSize: Theme.iconSmall
                    onTapped: picker.close()
                }

                Rectangle {
                    id: searchBox
                    anchors.right: closeButton.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(260, closeButton.x - segments.x - segments.width - 28)
                    height: 36
                    radius: height / 2
                    color: Theme.surfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 8

                        IconGlyph {
                            text: "\u{F0349}"
                            color: search.text.length > 0 ? Theme.accent : Theme.textMuted
                            size: Theme.iconSmall

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }
                        }

                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.family: Theme.fontText
                            selectByMouse: true
                            selectionColor: Theme.alpha(Theme.accent, 0.35)
                            selectedTextColor: Theme.textPrimary
                            cursorDelegate: Component { AccentCaret {} }
                            clip: true
                            focus: true

                            Component.onCompleted: search.forceActiveFocus()

                            text: picker.query
                            onTextChanged: picker.query = text

                            Keys.onEscapePressed: {
                                if (search.text.length > 0) picker.query = ""
                                else picker.close()
                            }
                            // Left and right walk the shelf while there is no
                            // text to move through; up and down always do.
                            Keys.onLeftPressed: event => {
                                if (search.text.length > 0) { event.accepted = false; return }
                                picker.moveSelection(-1)
                            }
                            Keys.onRightPressed: event => {
                                if (search.text.length > 0) { event.accepted = false; return }
                                picker.moveSelection(1)
                            }
                            Keys.onUpPressed: picker.moveSelection(-1)
                            Keys.onDownPressed: picker.moveSelection(1)
                            Keys.onTabPressed: picker.cycleCategory(1)
                            Keys.onBacktabPressed: picker.cycleCategory(-1)
                            onAccepted: if (picker.matches.length > 0)
                                            picker.addKind(picker.matches[picker.selected].kind)

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: search.text.length === 0
                                text: "Search"
                                color: Theme.textMuted
                                font.pixelSize: 13
                                font.family: Theme.fontText
                            }
                        }
                    }
                }
            }

            // ── The kinds, side by side ──────────────────────────────────
            Flickable {
                id: strip
                x: 20
                anchors.top: topRow.bottom
                anchors.topMargin: 14
                width: parent.width - 40
                height: picker.previewHeight + 62
                contentWidth: tileRow.width
                contentHeight: height
                clip: true
                // Dragging a tile carries the widget out; the strip moves by
                // the wheel (below) and by the keyboard selection instead.
                interactive: false

                Connections {
                    target: picker
                    function onRevealRequested(index) { strip.reveal(index) }
                }

                function reveal(index) {
                    var item = tileRepeater.itemAt(index)
                    if (!item) return
                    var to = strip.contentX
                    if (item.x < strip.contentX) to = item.x
                    else if (item.x + item.width > strip.contentX + strip.width) to = item.x + item.width - strip.width
                    scrollTo.to = Math.max(0, Math.min(to, strip.contentWidth - strip.width))
                    scrollTo.restart()
                }

                NumberAnimation {
                    id: scrollTo
                    target: strip
                    property: "contentX"
                    duration: Theme.durMedium
                    easing.type: Easing.OutCubic
                }

                Row {
                    id: tileRow
                    spacing: picker.tileGap

                    Repeater {
                        id: tileRepeater
                        model: picker.matches

                        Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool current: picker.selected === tile.index
                            readonly property int placedCount: Widgets.countOf(tile.modelData.kind)
                            width: picker.tileWidth(tile.modelData)
                            height: strip.height
                            radius: Theme.radiusLarge
                            color: tile.current || tileMouse.containsMouse ? Theme.surfaceContainerHigh
                                                                           : Theme.surfaceContainer
                            // The keyboard's place, drawn as a ring in the
                            // accent: the one outline here, because it is the
                            // focus.
                            border.width: tile.current ? 2 : 0
                            border.color: Theme.accent

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                            // The real widget, scaled to the shelf's height.
                            Item {
                                id: previewBox
                                x: 12
                                y: 12
                                width: parent.width - 24
                                height: picker.previewHeight

                                WidgetHost {
                                    anchors.centerIn: parent
                                    kind: tile.modelData.kind
                                    bar: picker.bar
                                    live: picker.open
                                    scale: picker.previewScale(tile.modelData)
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: previewBox.bottom
                                anchors.margins: 10
                                anchors.topMargin: 10
                                spacing: 2

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: tile.modelData.name
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    font.family: Theme.fontText
                                    elide: Text.ElideRight
                                }

                                // How many are out already, so a second one
                                // is a choice; empty, the line keeps the
                                // tiles the same height.
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: tile.placedCount > 0 ? tile.placedCount + " placed" : " "
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontText
                                    font.features: Theme.tabular
                                }
                            }

                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true
                                cursorShape: ghost.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                property point from: Qt.point(0, 0)

                                onPressed: mouse => tileMouse.from = Qt.point(mouse.x, mouse.y)
                                onPositionChanged: mouse => {
                                    // Hover steers the selection only when the
                                    // pointer really moves, so a still pointer
                                    // under a scrolling strip leaves the keys'
                                    // pick.
                                    if (!pressed) {
                                        picker.selected = tile.index
                                        return
                                    }
                                    var p = tileMouse.mapToItem(picker.contentItem, mouse.x, mouse.y)
                                    if (!ghost.active) {
                                        if (Math.abs(mouse.x - tileMouse.from.x) + Math.abs(mouse.y - tileMouse.from.y) < 6) return
                                        ghost.kind = tile.modelData.kind
                                        ghost.active = true
                                    }
                                    ghost.follow(p)
                                }
                                onReleased: {
                                    if (ghost.active) ghost.drop()
                                    else picker.addKind(tile.modelData.kind)
                                    search.forceActiveFocus()
                                }
                                onCanceled: ghost.active = false
                            }
                        }
                    }
                }

                Text {
                    visible: picker.matches.length === 0
                    width: strip.width
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "No widget matches “" + picker.query + "”."
                    color: Theme.textMuted
                    font.pixelSize: 12
                    font.family: Theme.fontText
                    elide: Text.ElideRight
                }
            }

            // The wheel moves the strip sideways a fixed step a notch, as the
            // launcher's list moves down; the strip does not take the pointer
            // itself.
            MouseArea {
                anchors.fill: strip
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    var d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                    if (d === 0) return
                    var max = Math.max(0, strip.contentWidth - strip.width)
                    var from = wheelScroll.running ? wheelScroll.to : strip.contentX
                    wheelScroll.to = Math.max(0, Math.min(max, from - d / 120 * 240))
                    wheelScroll.restart()
                }
            }

            NumberAnimation {
                id: wheelScroll
                target: strip
                property: "contentX"
                duration: Theme.durMedium
                easing.type: Easing.OutCubic
            }

            // ── Keys, and how it is used ─────────────────────────────────
            Item {
                id: footer
                x: 20
                width: parent.width - 40
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                height: 24

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    KeyHint { key: "← →"; label: "Choose"; visible: picker.matches.length > 0 }
                    KeyHint { key: "↵"; label: "Add"; visible: picker.matches.length > 0 }
                    KeyHint { key: "tab"; label: "Category" }
                    KeyHint { key: "esc"; label: picker.query.length > 0 ? "Clear" : "Close" }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: picker.matches.length > 0
                    text: "Drag one up onto the desktop, or click it to add it"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                }
            }
        }
    }
}
