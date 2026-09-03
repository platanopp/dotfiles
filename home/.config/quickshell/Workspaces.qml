import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// Workspace indicators: the active one is a labelled pill, occupied ones are
// dots, empty ones are dimmer dots. Clicking switches workspace.
Item {
    id: root

    property var monitor: null
    property int count: 5

    implicitWidth: layout.implicitWidth
    implicitHeight: 22

    readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0

    // Reading each workspace's lastIpcObject makes this re-evaluate whenever
    // Hyprland reports a window count change.
    readonly property var occupied: {
        var map = {}
        var list = Hyprland.workspaces.values
        for (var i = 0; i < list.length; i++) {
            var ws = list[i]
            var ipc = ws.lastIpcObject
            if (ipc && ipc.windows > 0) map[ws.id] = true
        }
        return map
    }

    // Hyprland only pushes some events; refreshing on the relevant ones keeps
    // the window counts accurate without polling.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            var n = event.name
            if (n.endsWith("v2")) return
            if (n.indexOf("workspace") !== -1 || n.indexOf("window") !== -1 || n === "focusedmon") {
                Hyprland.refreshWorkspaces()
            }
        }
    }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 6

        Repeater {
            model: root.count

            Item {
                id: wsItem
                required property int index
                readonly property int wsId: index + 1
                readonly property bool isActive: root.activeId === wsId
                readonly property bool isOccupied: root.occupied[wsId] === true

                Layout.preferredWidth: indicator.width
                Layout.preferredHeight: 22

                Rectangle {
                    id: indicator
                    anchors.centerIn: parent

                    width: wsItem.isActive ? 24 : (wsItem.isOccupied ? 9 : 6)
                    height: wsItem.isActive ? 18 : (wsItem.isOccupied ? 9 : 6)
                    radius: height / 2

                    color: wsItem.isActive
                        ? Theme.accent
                        : (wsItem.isOccupied ? Theme.alpha(Theme.foreground, 0.5)
                                             : Theme.alpha(Theme.foreground, 0.2))

                    scale: hover.hovered && !wsItem.isActive ? 1.25 : 1.0

                    Behavior on width {
                        NumberAnimation { duration: Theme.durLong; easing.type: Easing.Bezier; easing.bezierCurve: Theme.easeDecelerate }
                    }
                    Behavior on height {
                        NumberAnimation { duration: Theme.durLong; easing.type: Easing.Bezier; easing.bezierCurve: Theme.easeDecelerate }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Theme.durMedium }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: Theme.durShort; easing.type: Easing.Bezier; easing.bezierCurve: Theme.easeSpring }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: wsItem.isActive
                        opacity: wsItem.isActive ? 1 : 0
                        text: wsItem.wsId
                        color: Theme.accentText
                        font.pixelSize: 11
                        font.bold: true
                        font.family: Theme.fontMono

                        Behavior on opacity {
                            NumberAnimation { duration: Theme.durMedium }
                        }
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    // Hyprland 0.56 dispatches through Lua, where the old
                    // "workspace N" string is a syntax error; it wants a
                    // dispatcher table instead.
                    onTapped: if (!wsItem.isActive) Hyprland.dispatch('hl.dsp.focus({workspace="' + wsItem.wsId + '"})')
                }
            }
        }
    }
}
