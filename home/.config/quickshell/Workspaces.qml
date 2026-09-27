import Quickshell
import Quickshell.Hyprland
import QtQuick

// The workspaces, as a row of slots inside the left pill: a filled pill slides
// to the active one and carries its number; a workspace with windows is a
// firmer dot than an empty one; one asking for attention is red and pulses.
// While the special workspace (Super+S) is showing on this monitor it gets a
// slot of its own at the end. Click a slot to go there; the wheel steps
// through them.
//
// At least five slots, more when a higher workspace is in use, up to ten --
// Super+6..0 reach them, and a fixed five hid them.
//
// Nothing here polls. Occupancy and urgency come from each workspace's own
// toplevels and urgent flag, which Quickshell keeps current off Hyprland's
// event stream; only the special workspace needs the monitor re-read, and only
// when Hyprland says it changed.
Item {
    id: root

    property var monitor: null

    readonly property int slotSize: 22
    readonly property int slotGap: 4

    implicitWidth: row.width + (specialSlot.visible ? root.slotGap + root.slotSize : 0)
    implicitHeight: root.slotSize

    readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0

    // id -> { windows, urgent } for the normal workspaces.
    readonly property var state: {
        var map = {}
        var list = Hyprland.workspaces.values
        for (var i = 0; i < list.length; i++) {
            var ws = list[i]
            if (ws.id <= 0) continue
            map[ws.id] = {
                windows: ws.toplevels ? ws.toplevels.values.length : 0,
                urgent: ws.urgent === true
            }
        }
        return map
    }

    readonly property int count: {
        var high = Math.max(5, root.activeId)
        for (var id in root.state)
            if (root.state[id].windows > 0) high = Math.max(high, parseInt(id))
        return Math.min(10, high)
    }

    // The special workspace showing on this monitor, if any: Hyprland reports
    // it on the monitor ("specialWorkspace": { id, name }).
    readonly property string specialName: {
        var ipc = root.monitor ? root.monitor.lastIpcObject : null
        var sw = ipc ? ipc.specialWorkspace : null
        return sw && sw.name ? sw.name.replace(/^special:/, "") : ""
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activespecial") Hyprland.refreshMonitors()
        }
    }

    function go(id) {
        Hyprland.dispatch('hl.dsp.focus({workspace="' + id + '"})')
    }

    // The wheel: one step per notch, not one per event a touchpad sends.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (wheelCooldown.running) return
            var d = event.angleDelta.y !== 0 ? event.angleDelta.y : -event.angleDelta.x
            if (d === 0) return
            var next = root.activeId + (d < 0 ? 1 : -1)
            if (next < 1 || next > 10) return
            root.go(next)
            wheelCooldown.restart()
        }
    }

    Timer {
        id: wheelCooldown
        interval: 150
    }

    Item {
        id: row
        width: root.count * root.slotSize + (root.count - 1) * root.slotGap
        height: root.slotSize

        Behavior on width {
            NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
        }

        // The active workspace: one pill that slides, rather than two dots
        // trading sizes.
        Rectangle {
            id: highlight
            readonly property int index: root.activeId - 1
            visible: root.activeId >= 1 && root.activeId <= root.count
            x: Math.max(0, highlight.index) * (root.slotSize + root.slotGap) - 3
            width: root.slotSize + 6
            height: root.slotSize
            radius: height / 2
            color: Theme.accent

            Behavior on x {
                NumberAnimation { duration: Theme.durLong; easing.type: Easing.OutCubic }
            }
        }

        Repeater {
            model: root.count

            Item {
                id: slot
                required property int index
                readonly property int wsId: slot.index + 1
                readonly property bool active: root.activeId === slot.wsId
                readonly property var info: root.state[slot.wsId]
                readonly property bool occupied: !!slot.info && slot.info.windows > 0
                readonly property bool urgent: !!slot.info && slot.info.urgent && !slot.active

                x: slot.index * (root.slotSize + root.slotGap)
                width: root.slotSize
                height: root.slotSize

                // Under the pointer, the same soft disc as every other button.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.foreground
                    opacity: slot.active ? 0 : tap.pressed ? Theme.pressOpacity : hover.hovered ? Theme.hoverOpacity + 0.04 : 0

                    Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
                }

                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    visible: !slot.active
                    width: slot.urgent ? 8 : slot.occupied ? 7 : 5
                    height: width
                    radius: width / 2
                    color: slot.urgent ? Theme.error
                         : Theme.alpha(Theme.foreground, slot.occupied ? 0.7 : 0.25)

                    Behavior on width { NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Theme.durMedium } }

                    // Asking for attention: a slow pulse, only while it asks.
                    SequentialAnimation on opacity {
                        running: slot.urgent
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) dot.opacity = 1
                        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    opacity: slot.active ? 1 : 0
                    visible: opacity > 0
                    text: slot.wsId
                    color: Theme.accentText
                    font.pixelSize: 11
                    font.bold: true
                    font.family: Theme.fontMono

                    Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: tap
                    onTapped: if (!slot.active) root.go(slot.wsId)
                }
            }
        }
    }

    // The special workspace, while it is up on this monitor. Tapping it puts
    // it away again.
    Item {
        id: specialSlot
        visible: root.specialName.length > 0
        x: row.width + root.slotGap
        width: root.slotSize
        height: root.slotSize

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.alpha(Theme.accent, 0.22)
            border.width: 1
            border.color: Theme.alpha(Theme.accent, 0.6)
        }

        IconGlyph {
            anchors.centerIn: parent
            text: "\u{F0674}"
            color: Theme.textPrimary
            size: Theme.iconSmall
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        TapHandler {
            onTapped: Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + root.specialName + '")')
        }
    }
}
