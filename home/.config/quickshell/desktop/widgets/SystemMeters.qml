import QtQuick
import qs.components
import qs.config
import qs.desktop
import qs.services

// CPU, memory, GPU and its memory, as numbers and bars: what btop's window
// was kept open for. The bars stay neutral and turn amber, then red, as a
// meter nears full -- the number beside it says the same in words.
WidgetCard {
    id: root

    // Only while the desktop can be seen; Stats stops when nobody asks.
    onLiveChanged: root.live ? Stats.subscribe() : Stats.unsubscribe()
    Component.onCompleted: if (root.live) Stats.subscribe()
    Component.onDestruction: if (root.live) Stats.unsubscribe()

    function pct(v, temp) {
        if (v < 0) return "No reading"
        return Math.round(v * 100) + "%" + (temp < 0 ? "" : "  " + Math.round(temp) + "°C")
    }
    function gib(used, total) {
        if (used < 0 || total <= 0) return "No reading"
        return used.toFixed(1) + " / " + total.toFixed(1) + " GiB"
    }

    component Meter: Column {
        id: meter
        property string label: ""
        property string value: ""
        property real fraction: -1
        width: parent.width
        spacing: 6

        Item {
            width: parent.width
            height: name.implicitHeight

            Text {
                id: name
                text: meter.label
                color: Theme.textSecondary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.family: Theme.fontText
            }

            Text {
                anchors.right: parent.right
                text: meter.value
                color: Theme.textPrimary
                font.pixelSize: 12
                font.family: Theme.fontText
                font.features: Theme.tabular
            }
        }

        Rectangle {
            width: parent.width
            height: 6
            radius: height / 2
            color: Theme.track

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, meter.fraction))
                height: parent.height
                radius: height / 2
                color: meter.fraction >= 0.9 ? Theme.error
                     : meter.fraction >= 0.75 ? Theme.warning
                     : Theme.textSecondary

                Behavior on width { Elastic { small: true } }
                Behavior on color { ColorAnimation { duration: Theme.durMedium } }
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 22
        anchors.topMargin: 18
        spacing: 14

        Text {
            text: "Resources"
            color: Theme.textPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.family: Theme.fontText
        }

        Meter {
            label: "CPU"
            value: root.pct(Stats.cpu, Stats.cpuTemp)
            fraction: Stats.cpu
        }

        Meter {
            label: "Memory"
            value: root.gib(Stats.memUsed, Stats.memTotal)
            fraction: Stats.memTotal > 0 ? Stats.memUsed / Stats.memTotal : -1
        }

        Meter {
            label: "GPU"
            value: root.pct(Stats.gpu, Stats.gpuTemp)
            fraction: Stats.gpu
        }

        Meter {
            label: "Video memory"
            value: root.gib(Stats.vramUsed, Stats.vramTotal)
            fraction: Stats.vramTotal > 0 ? Stats.vramUsed / Stats.vramTotal : -1
        }
    }
}
