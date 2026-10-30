import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services

// One monitor's desktop widgets, on the layer under every window
// (WlrLayer.Bottom: above the wallpaper, below the windows).
//
// Unmapped -- not just empty -- while it has nothing to show: with no
// widgets on that monitor, and while a window there is fullscreen, which is
// a game more often than not; the surface then costs the compositor nothing
// at all. Input is only taken over the widgets themselves (their regions in
// the mask), so a click on the bare desktop goes wherever it went before.
PanelWindow {
    id: layer

    property var bar: null
    screen: bar.screen

    readonly property string screenName: bar.monitor ? bar.monitor.name : ""

    WidgetModel {
        id: widgets
        screenName: layer.screenName
    }

    // The picker draws this monitor's widgets itself while it edits them, over
    // the windows, so they can be seen and carried; these step aside.
    readonly property bool editing: Panels.widgetsOpen && Panels.widgetsScreen === layer.screenName

    visible: widgets.count > 0 && !layer.bar.fullscreen

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
        regions: layer.editing ? [] : hits.instances
    }

    Variants {
        id: hits
        model: layer.editing ? [] : Widgets.onScreen(layer.screenName)

        Region {
            required property var modelData
            readonly property var spec: Widgets.spec(modelData.kind)
            x: modelData.x
            y: modelData.y
            width: spec ? spec.w : 0
            height: spec ? spec.h : 0
        }
    }

    Item {
        anchors.fill: parent
        visible: !layer.editing

        Repeater {
            model: widgets

            WidgetHost {
                // Kept on the monitor if it has shrunk since the widget was
                // put there.
                x: Math.max(0, Math.min(model.wx, layer.width - width))
                y: Math.max(0, Math.min(model.wy, layer.height - height))
                kind: model.kind
                bar: layer.bar
                // A hidden window keeps its items, so this has to say so
                // itself: nothing redraws or listens while covered, under a
                // fullscreen window, or while the picker shows its own copy.
                live: layer.visible && !layer.editing && !Widgets.isCovered(layer.screenName)
            }
        }
    }
}
