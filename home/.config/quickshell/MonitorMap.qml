import QtQuick

// The displays laid out the way Hyprland places them, to scale. Drag one to
// move it: its edges snap to the edges of the others it comes near, so the
// arrangement never ends up with a gap the pointer cannot cross. A click
// without a drag picks that display for the settings below the map.
//
// The move is applied on release, not while dragging -- each one reconfigures
// the output, and doing that per pixel of mouse travel would stutter the
// whole desktop.
Item {
    id: map

    property string selected: ""
    signal picked(string name)

    readonly property var monitors: AppState.displayState.monitors || []
    readonly property int snap: 80

    // Where each display is shown, in Hyprland's own coordinates: its real
    // position, or where it was dropped until Hyprland reports it back.
    property var placed: ({})
    property string held: ""

    Connections {
        target: AppState
        function onDisplayStateChanged() { map.placed = ({}) }
    }

    function sizeOf(m) {
        var s = m.scale > 0 ? m.scale : 1
        return { w: Math.round(m.width / s), h: Math.round(m.height / s) }
    }

    function posOf(m) {
        var p = map.placed[m.name]
        return p ? p : { x: m.x, y: m.y }
    }

    readonly property var bounds: {
        var ms = map.monitors
        if (ms.length === 0) return { x: 0, y: 0, w: 1920, h: 1080 }
        var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
        for (var i = 0; i < ms.length; i++) {
            var p = map.posOf(ms[i]), s = map.sizeOf(ms[i])
            x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y)
            x1 = Math.max(x1, p.x + s.w); y1 = Math.max(y1, p.y + s.h)
        }
        // Room around the layout, so a display dragged past the edge still
        // has somewhere to be drawn.
        var padX = Math.max(300, (x1 - x0) * 0.12), padY = Math.max(300, (y1 - y0) * 0.18)
        return { x: x0 - padX, y: y0 - padY, w: (x1 - x0) + padX * 2, h: (y1 - y0) + padY * 2 }
    }

    readonly property real fit: Math.min(map.width / map.bounds.w, map.height / map.bounds.h)
    readonly property real offX: map.width / 2 - (map.bounds.x + map.bounds.w / 2) * map.fit
    readonly property real offY: map.height / 2 - (map.bounds.y + map.bounds.h / 2) * map.fit

    // The nearest edge alignment to where a display was let go: beside the
    // others, or lined up with their tops, bottoms and sides.
    function settle(name, wantX, wantY) {
        var me = null
        for (var i = 0; i < map.monitors.length; i++)
            if (map.monitors[i].name === name) me = map.monitors[i]
        var s = map.sizeOf(me)
        var x = Math.round(wantX), y = Math.round(wantY)
        var bestX = map.snap + 1, bestY = map.snap + 1, snapX = x, snapY = y
        for (var j = 0; j < map.monitors.length; j++) {
            var o = map.monitors[j]
            if (o.name === name) continue
            var p = map.posOf(o), os = map.sizeOf(o)
            var xs = [p.x - s.w, p.x + os.w, p.x, p.x + os.w - s.w]
            var ys = [p.y - s.h, p.y + os.h, p.y, p.y + os.h - s.h]
            for (var a = 0; a < 4; a++) {
                if (Math.abs(x - xs[a]) < bestX) { bestX = Math.abs(x - xs[a]); snapX = xs[a] }
                if (Math.abs(y - ys[a]) < bestY) { bestY = Math.abs(y - ys[a]); snapY = ys[a] }
            }
        }
        return { x: bestX <= map.snap ? snapX : x, y: bestY <= map.snap ? snapY : y }
    }

    function shortName(desc) {
        return (desc || "").replace(/ (Electric Company|Corporation|Technologies|Technology|Inc\.?|Co\.?,? ?Ltd\.?)/g, "")
    }

    Repeater {
        model: map.monitors

        Rectangle {
            id: plate
            required property var modelData

            readonly property var size: map.sizeOf(plate.modelData)
            readonly property var pos: map.posOf(plate.modelData)
            readonly property bool chosen: map.selected === plate.modelData.name
            readonly property bool lifted: map.held === plate.modelData.name

            // Dragged freely under the pointer, placed from the model
            // otherwise.
            property real dragX: 0
            property real dragY: 0

            x: plate.lifted ? plate.dragX : map.offX + plate.pos.x * map.fit
            y: plate.lifted ? plate.dragY : map.offY + plate.pos.y * map.fit
            width: Math.max(40, plate.size.w * map.fit)
            height: Math.max(28, plate.size.h * map.fit)
            radius: 10
            z: plate.lifted ? 2 : 1
            color: plate.chosen ? Theme.accent : Theme.surfaceContainerHigh
            border.width: plate.chosen ? 0 : 1
            border.color: Theme.outline

            Behavior on x { enabled: !plate.lifted; NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: !plate.lifted; NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.durShort } }

            readonly property color ink: plate.chosen ? Theme.accentText : Theme.textPrimary

            Column {
                anchors.centerIn: parent
                width: parent.width - 16
                spacing: 2

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: map.shortName(plate.modelData.description) || plate.modelData.name
                    color: plate.ink
                    font.pixelSize: 11
                    font.bold: true
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: plate.height > 60
                    text: plate.modelData.name + "  ·  " + plate.modelData.width + "×" + plate.modelData.height
                    color: plate.chosen ? Theme.alpha(Theme.accentText, 0.65) : Theme.textMuted
                    font.pixelSize: 9
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                cursorShape: map.monitors.length > 1 ? Qt.SizeAllCursor : Qt.PointingHandCursor
                preventStealing: true

                property point grab
                property bool moved: false

                onPressed: mouse => {
                    drag.grab = Qt.point(mouse.x, mouse.y)
                    drag.moved = false
                    plate.dragX = plate.x
                    plate.dragY = plate.y
                }

                onPositionChanged: mouse => {
                    if (!pressed || map.monitors.length < 2) return
                    if (!drag.moved && Math.abs(mouse.x - drag.grab.x) + Math.abs(mouse.y - drag.grab.y) < 4)
                        return
                    drag.moved = true
                    map.held = plate.modelData.name
                    var p = plate.mapToItem(map, mouse.x, mouse.y)
                    plate.dragX = p.x - drag.grab.x
                    plate.dragY = p.y - drag.grab.y
                }

                onReleased: {
                    if (!drag.moved) {
                        map.picked(plate.modelData.name)
                        return
                    }
                    var spot = map.settle(plate.modelData.name,
                                          (plate.dragX - map.offX) / map.fit,
                                          (plate.dragY - map.offY) / map.fit)
                    var next = Object.assign({}, map.placed)
                    next[plate.modelData.name] = spot
                    map.placed = next
                    map.held = ""
                    AppState.setDisplayPosition(plate.modelData.name, spot.x, spot.y)
                }
            }
        }
    }
}
