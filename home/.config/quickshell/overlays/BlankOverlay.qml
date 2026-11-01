import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.services

// A black cover for a screen that must not be powered off. The Xiaomi on HDMI-A-1 drops its link in
// standby, and Hyprland re-setting it up left DRM stuck on a pending page flip (once neither panel
// came back), so it is covered and kept awake. The Samsung on DP-2 is powered off for real.
// idle-screens.sh decides, via `qs ipc call screens`.
PanelWindow {
    id: cover

    property var bar: null
    screen: bar.screen

    readonly property bool blanked: bar.monitor !== null
        && Power.blankedScreens.indexOf(bar.monitor.name) !== -1

    // Unmapped while not in use, like every other overlay here: a mapped
    // full-screen layer surface is composited every frame even when empty.
    visible: cover.blanked

    color: "black"

    WlrLayershell.namespace: "quickshell:blank"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    // Never the keyboard: the first key that wakes the screens has to reach
    // whatever window it was meant for, not a black square.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
}
