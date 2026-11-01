import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.desktop
import qs.services

// CPU, memory, GPU and its memory as four tiles like the control panel's: the number large, the bar
// under it neutral, turning amber then red as it nears full.
WidgetCard {
    id: root

    // Only while the desktop can be seen; Stats stops when nobody asks.
    onLiveChanged: root.live ? Stats.subscribe() : Stats.unsubscribe()
    Component.onCompleted: if (root.live) Stats.subscribe()
    Component.onDestruction: if (root.live) Stats.unsubscribe()

    component Tile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property string detail: ""
        property real fraction: -1
        readonly property bool known: tile.fraction >= 0

        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radiusLarge
        color: Theme.surfaceContainer

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 2

            Text {
                text: tile.label
                color: Theme.textSecondary
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.family: Theme.fontText
            }

            Text {
                text: tile.known ? tile.value : "No reading"
                color: tile.known ? Theme.textPrimary : Theme.textMuted
                font.pixelSize: tile.known ? 22 : 13
                font.bold: tile.known
                font.family: tile.known ? Theme.fontDisplay : Theme.fontText
                font.features: Theme.tabular
            }

            Text {
                Layout.fillWidth: true
                visible: tile.known
                text: tile.detail
                color: Theme.textMuted
                font.pixelSize: 10
                font.family: Theme.fontText
                font.features: Theme.tabular
                elide: Text.ElideRight
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: height / 2
                color: Theme.track

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, tile.fraction))
                    height: parent.height
                    radius: height / 2
                    color: tile.fraction >= 0.9 ? Theme.error
                         : tile.fraction >= 0.75 ? Theme.warning
                         : Theme.textSecondary

                    Behavior on width { Elastic { small: true } }
                    Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                }
            }
        }
    }

    function temp(t) { return t < 0 ? "" : Math.round(t) + " °C" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Text {
            text: "Resources"
            color: Theme.textPrimary
            font.pixelSize: 13
            font.bold: true
            font.family: Theme.fontText
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            Tile {
                label: "CPU"
                value: Math.round(Stats.cpu * 100) + "%"
                detail: root.temp(Stats.cpuTemp)
                fraction: Stats.cpu
            }

            Tile {
                label: "Memory"
                value: Stats.memUsed.toFixed(1) + " GiB"
                detail: "of " + Stats.memTotal.toFixed(1) + " GiB"
                fraction: Stats.memTotal > 0 ? Stats.memUsed / Stats.memTotal : -1
            }

            Tile {
                label: "GPU"
                value: Math.round(Stats.gpu * 100) + "%"
                detail: root.temp(Stats.gpuTemp)
                fraction: Stats.gpu
            }

            Tile {
                label: "Video memory"
                value: Stats.vramUsed.toFixed(1) + " GiB"
                detail: "of " + Stats.vramTotal.toFixed(1) + " GiB"
                fraction: Stats.vramTotal > 0 ? Stats.vramUsed / Stats.vramTotal : -1
            }
        }
    }
}
