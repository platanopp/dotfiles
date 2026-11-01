import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects
import qs.config
import qs.services

// Background apps, in a pill of their own: inside the status pill they shifted
// whenever the SSID or the panel changed width. Its own window keeps them still and
// disappears when nothing is in the tray.
PanelWindow {
    id: trayItem

    property var bar: null

    screen: bar.screen
    color: "transparent"

    // Nothing to show means no empty pill floating on the bar.
    visible: SystemTray.items.values.length > 0

    // Hidden by cutting input and drawing nothing, never by unmapping: a remapped layer is
    // restacked above the pills and swallowed their clicks. The blur rule ignores pixels
    // under 0.3 alpha, so nothing shows. Also hidden under the Settings window: a re-created
    // layer surface stacks above older ones.
    property bool covered: false

    mask: bar.barHidden || covered ? blankMask : stageMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Input only where the pill is (see PillStage).
    Region {
        id: stageMask
        item: stage
    }

    // Keeps the bar up while hovered; shell.qml folds these together with the reveal zone's hover.
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
    // The content insets by 12, so the window sits back that much and the
    // drawn edge lands on Hyprland's gap.
    margins.top: Math.max(0, Hypr.gapTop - 12)

    // Set by shell.qml from the status pill's live width, so an expanding panel pushes these icons
    // along. Not animated: a second animation chasing that one made the row lag.
    property int rightMargin: 0
    margins.right: rightMargin

    // An icon coming or going animates the box, not the window (PillStage).
    PillStage {
        id: stage
        collapsed: bar.barHidden
        anchors.top: parent.top
        anchors.right: parent.right
        targetWidth: trayRow.implicitWidth + 24 + Theme.pillPaddingH * 2
        targetHeight: Theme.pillHeight + 24
    }

    implicitWidth: stage.windowWidth
    // 4px under the box, so the shadow fades out 16px below the glass as under the workspace pill
    // instead of being cut at 12. Input stays on the box (the Region above).
    implicitHeight: stage.collapsed ? stage.windowHeight : stage.windowHeight + 4

    readonly property real visualWidth: stage.width

    Item {
        id: contentArea
        visible: !bar.barHidden && !covered
        anchors.fill: stage
        anchors.margins: 12

        Rectangle {
            id: trayGlass
            anchors.fill: parent
            radius: height / 2
            color: Theme.glass
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: trayGlass
            anchors.fill: trayGlass
            shadowEnabled: true
            shadowColor: Theme.shadow
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
