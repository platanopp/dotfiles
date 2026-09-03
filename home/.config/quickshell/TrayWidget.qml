import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects

// Background apps, in a pill of their own.
//
// These used to ride inside the status widget's compact row, behind a divider.
// That made every tray icon shift whenever the SSID text changed length or the
// status panel expanded and re-centred the row -- apps that have nothing to do
// with the shell's own indicators were moving because the shell's indicators
// did. Its own window keeps them still and lets it disappear entirely when no
// app is running one.
PanelWindow {
    id: trayItem

    property var bar: null

    screen: bar.screen
    color: "transparent"

    // Nothing to show means no empty pill floating on the bar.
    visible: SystemTray.items.values.length > 0

    // Hidden by cutting input and drawing nothing, never by unmapping the
    // window. Toggling visible destroys the layer surface, and Hyprland
    // restacks it on the way back: the full-width bar came back above the
    // pills and swallowed every click meant for them. The blur rule ignores
    // pixels below 0.3 alpha, so a surface drawing nothing leaves no band.
    mask: bar.barHidden ? blankMask : null

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Keeps the bar up while the pointer is on it; shell.qml folds these
    // together with the reveal zone's own hover.
    readonly property bool barHovered: barHover.hovered

    HoverHandler {
        id: barHover
    }

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        right: true
    }
    // The content inside insets itself by 12, so the window sits back by
    // that much and the drawn edge lands exactly on Hyprland's gap.
    margins.top: AppState.gapTop - 12

    // Set by shell.qml, which owns the order of the right-hand pills. It
    // follows the status pill's live width, so an expanding panel pushes these
    // icons along instead of appearing underneath them.
    property int rightMargin: 0
    margins.right: rightMargin

    Behavior on margins.right {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    implicitWidth: trayRow.implicitWidth + 48
    implicitHeight: 64

    Behavior on implicitWidth {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    Item {
        id: contentArea
        visible: !bar.barHidden
        anchors.fill: parent
        anchors.margins: 12

        Rectangle {
            id: trayGlass
            anchors.fill: parent
            radius: 20
            color: Theme.glass
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: trayGlass
            anchors.fill: trayGlass
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.5
            shadowBlur: 0.7
            shadowVerticalOffset: 4
            autoPaddingEnabled: true
        }

        TrayItems {
            id: trayRow
            anchors.centerIn: parent
            menuWindow: trayItem
        }
    }
}
