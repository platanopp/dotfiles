import Quickshell
import Quickshell.Wayland
import QtQuick

// A black cover for a screen that must not be powered off.
//
// The Xiaomi on HDMI-A-1 drops its link whenever it falls into standby -- with
// its own power-saving options off as well -- and when it comes back Hyprland
// has to set the output up from scratch. That reshuffle left the DRM state
// stuck on a pending page flip: first frozen-looking terminals, then a wake-up
// where neither panel came back at all and the machine had to be switched off
// at the button. So that monitor is never put to sleep. It is covered instead,
// and stays awake behind the cover.
//
// The Samsung on DP-2 never dropped its link in any test, so it is powered off
// for real. Which screens get the cover rather than the power-off is decided
// in ~/.config/hypr/scripts/idle-screens.sh, which drives this through
// `qs ipc call screens`.
PanelWindow {
    id: cover

    property var bar: null
    screen: bar.screen

    readonly property bool blanked: bar.monitor !== null
        && AppState.blankedScreens.indexOf(bar.monitor.name) !== -1

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
