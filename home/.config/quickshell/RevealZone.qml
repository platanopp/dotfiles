import Quickshell
import Quickshell.Wayland
import QtQuick

// Hot corner that brings the bar back while an app is fullscreen.
//
// A hidden bar has nothing to hover, so something has to stay behind to catch
// the pointer. This sits at the top-right corner, where the cursor stops
// against the screen edge, and grows to cover the whole bar strip once the bar
// is up -- otherwise crossing a gap between two pills would drop the pointer
// and collapse the bar again.
//
// It sits on the Top layer, below the pills on Overlay, so it never swallows a
// click meant for them.
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

    // Only ever the corner. Keeping it small means it can sit above the pills
    // in the stack without taking anything from them, and once the bar is up
    // the bar's own window handles the rest of the strip.
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
