import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.services

// One monitor's desktop widgets, on WlrLayer.Bottom: above the wallpaper, below the
// windows. Unmapped while there is nothing to show (no widgets, or a fullscreen window);
// input only over the widgets themselves. Not `id: layer`: inside the widgets that name
// resolves to every Item's own `layer` property.
PanelWindow {
    id: desk

    property var bar: null
    screen: bar.screen

    readonly property string screenName: bar.monitor ? bar.monitor.name : ""

    WidgetModel {
        id: widgets
        screenName: desk.screenName
    }

    // The picker draws this monitor's widgets itself while editing them, over
    // the windows; these step aside.
    readonly property bool editing: Panels.widgetsOpen && Panels.widgetsScreen === desk.screenName

    readonly property bool showing: widgets.count > 0 && !desk.bar.fullscreen

    // Unmapped while the overview's opaque backdrop is up, back as soon as it starts
    // closing; the widgets stop meanwhile. The spectrum helper lingers a few seconds,
    // so Super+Tab doesn't restart it.
    property bool underOverview: false

    Timer {
        id: overviewCover
        interval: Theme.durMedium + 50
        onTriggered: desk.underOverview = Panels.overviewOpen
    }

    Connections {
        target: Panels
        function onOverviewOpenChanged() {
            if (Panels.overviewOpen) {
                overviewCover.restart()
            } else {
                overviewCover.stop()
                desk.underOverview = false
            }
        }
    }

    visible: desk.showing && !desk.underOverview

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:desktop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        regions: desk.editing ? [] : hits.instances
    }

    Variants {
        id: hits
        model: desk.editing ? [] : Widgets.onScreen(desk.screenName)

        Region {
            required property var modelData
            readonly property var spec: Widgets.spec(modelData.kind)
            x: modelData.x
            y: modelData.y
            width: spec ? Math.round(spec.w * Widgets.sizeOf(modelData)) : 0
            height: spec ? Math.round(spec.h * Widgets.sizeOf(modelData)) : 0
        }
    }

    Item {
        id: area
        anchors.fill: parent
        visible: !desk.editing

        Repeater {
            model: widgets

            WidgetHost {
                // Kept on the monitor if it shrank since the widget was placed.
                x: Math.max(0, Math.min(model.wx, area.width - width))
                y: Math.max(0, Math.min(model.wy, area.height - height))
                kind: model.kind
                size: model.ws
                bar: desk.bar
                // A hidden window keeps its items, so they are told: nothing redraws while covered,
                // under fullscreen, or while the picker shows its own copy.
                live: desk.showing && !desk.editing && !desk.underOverview && !Widgets.isCovered(desk.screenName)
            }
        }
    }
}
