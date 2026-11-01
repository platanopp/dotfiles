import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.services

// One monitor's desktop widgets, on the layer under every window
// (WlrLayer.Bottom: above the wallpaper, below the windows).
//
// Unmapped -- not just empty -- while it has nothing to show: with no
// widgets on that monitor, and while a window there is fullscreen, which is
// a game more often than not; the surface then costs the compositor nothing
// at all. Input is only taken over the widgets themselves (their regions in
// the mask), so a click on the bare desktop goes wherever it went before.
//
// Not `id: layer`: inside the widgets that name is every Item's own `layer`
// property (the offscreen-texture group), which shadows the id. Each
// `layer.x` there read undefined -- the clamp put every widget in the top-left
// corner, `live` never came on and the meters never asked for a reading.
PanelWindow {
    id: desk

    property var bar: null
    screen: bar.screen

    readonly property string screenName: bar.monitor ? bar.monitor.name : ""

    WidgetModel {
        id: widgets
        screenName: desk.screenName
    }

    // The picker draws this monitor's widgets itself while it edits them, over
    // the windows, so they can be seen and carried; these step aside.
    readonly property bool editing: Panels.widgetsOpen && Panels.widgetsScreen === desk.screenName

    readonly property bool showing: widgets.count > 0 && !desk.bar.fullscreen

    // The workspace overview covers every screen, opaque, so for as long as
    // it is up the surface goes too -- once its backdrop is up, and back the
    // moment it starts to close, before the backdrop has gone -- and the
    // widgets stop, as they do when covered. (The spectrum's helper waits a
    // few seconds before quitting, so it is not restarted every Super+Tab.)
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
                // Kept on the monitor if it has shrunk since the widget was
                // put there.
                x: Math.max(0, Math.min(model.wx, area.width - width))
                y: Math.max(0, Math.min(model.wy, area.height - height))
                kind: model.kind
                size: model.ws
                bar: desk.bar
                // A hidden window keeps its items, so this has to say so
                // itself: nothing redraws or listens while covered, under a
                // fullscreen window, or while the picker shows its own copy.
                live: desk.showing && !desk.editing && !desk.underOverview && !Widgets.isCovered(desk.screenName)
            }
        }
    }
}
