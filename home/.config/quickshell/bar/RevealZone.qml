import Quickshell
import Quickshell.Wayland
import QtQuick

// Hot corner that brings the bar back while an app is fullscreen: it sits at the top-right
// corner and grows to the whole strip once the bar is up. On the Top layer, below the pills on
// Overlay, so it never takes their clicks.
PanelWindow {
    id: root

    property var bar: null

    screen: bar.screen
    color: "transparent"

    WlrLayershell.namespace: "quickshell:reveal"

    // Overlay, not Top: a fullscreen window covers the top layer, so a zone
    // there would never see the pointer. The bar's pills live here too.
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    readonly property bool hovered: revealHover.hovered

    anchors {
        top: true
        right: true
    }

    // Only ever the corner, so it never takes from the pills; once the bar is up
    // its own window handles the strip.
    implicitWidth: 180
    implicitHeight: 6

    // Live only while the bar is actually hidden, and by mask rather than by
    // unmapping, so the surface never restacks.
    mask: (bar.fullscreen && bar.barHidden) ? null : blankMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    HoverHandler {
        id: revealHover
    }
}
