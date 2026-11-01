import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.components
import qs.config
import qs.services

// A quiet word when the keyboard layout changes: a small glass pill near the
// bottom of the focused screen for a moment, never taking a click.
PanelWindow {
    id: toast

    property var bar: null
    screen: bar ? bar.screen : null

    readonly property bool onFocusedMonitor: {
        if (!bar || !bar.monitor) return false
        var focused = Hyprland.focusedMonitor
        return !!focused && focused.id === bar.monitor.id
    }

    WlrLayershell.namespace: "quickshell:bar-blur"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    anchors.bottom: true
    margins.bottom: 72
    color: "transparent"
    mask: Region {}

    // Fixed size, the pill moves inside (see PillStage on resizing surfaces).
    implicitWidth: 420
    implicitHeight: 72
    visible: false

    Connections {
        target: KeyLayout
        function onSwitched() {
            if (!toast.onFocusedMonitor) return
            toast.visible = true
            show.restart()
        }
    }

    SequentialAnimation {
        id: show
        ParallelAnimation {
            NumberAnimation { target: pill; property: "opacity"; to: 1; duration: Theme.durMedium; easing.type: Easing.OutCubic }
            NumberAnimation { target: pill; property: "slide"; to: 0; duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 1400 }
        ParallelAnimation {
            NumberAnimation { target: pill; property: "opacity"; to: 0; duration: 300; easing.type: Easing.InCubic }
            NumberAnimation { target: pill; property: "slide"; to: 8; duration: 300; easing.type: Easing.InCubic }
        }
        ScriptAction { script: toast.visible = false }
    }

    Item {
        id: pill
        property real slide: 8
        opacity: 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 + slide
        width: content.implicitWidth + 32
        height: 40

        Rectangle {
            id: glass
            anchors.fill: parent
            radius: height / 2
            color: Theme.glass
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            source: glass
            anchors.fill: glass
            shadowEnabled: true
            shadowColor: Theme.shadow
            shadowOpacity: 0.20
            shadowBlur: 0.38
            shadowVerticalOffset: 2
            autoPaddingEnabled: true
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 10

            IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F030C}"
                color: Theme.accent
                size: Theme.iconLarge
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: KeyLayout.label
                color: Theme.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.family: Theme.fontText
            }

            Text {
                visible: KeyLayout.hint !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: KeyLayout.hint
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontText
            }
        }
    }
}
