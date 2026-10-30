import QtQuick
import Quickshell.Io
import qs.components
import qs.config
import qs.desktop
import qs.services

// What fastfetch used to print in its terminal window: who and where, the
// system, and the hardware under it. The same facts Settings -> About reads
// (scripts/about.py), set as label and value rather than dressed up as a
// terminal -- it is a card on the desktop, not a shell.
WidgetCard {
    id: root

    readonly property var info: System.aboutInfo

    Component.onCompleted: if (!root.info.os) System.refreshInfo()

    // Uptime is the one fact that moves; read from /proc each minute rather
    // than running the whole of about.py again.
    property string uptime: ""

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: {
            var up = Number(uptimeFile.text().split(" ")[0])
            var d = Math.floor(up / 86400), h = Math.floor(up % 86400 / 3600), m = Math.floor(up % 3600 / 60)
            root.uptime = (d > 0 ? d + "d " : "") + h + "h " + m + "m"
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.live
        triggeredOnStart: true
        onTriggered: uptimeFile.reload()
    }

    // The vendor's boilerplate off the hardware names, which otherwise run
    // past the card: "Intel(R) Core(TM) i7-10700F CPU @ 2.90GHz" is an
    // i7-10700F to anyone reading it.
    function shortCpu(s) {
        return (s || "").replace(/\(R\)|\(TM\)/g, "").replace(/\bCPU\b.*$/, "")
                        .replace(/^Intel\s+Core\s+/, "Core ").replace(/\s+/g, " ").trim()
    }
    function shortGpu(s) {
        return (s || "").replace(/^NVIDIA\s+GeForce\s+/, "GeForce ").trim()
    }

    readonly property var rows: [
        { label: "OS", value: root.info.os || "" },
        { label: "Kernel", value: root.info.kernel || "" },
        { label: "Uptime", value: root.uptime },
        { label: "Packages", value: root.info.packages ? root.info.packages + " (pacman)" : "" },
        { label: "Shell", value: root.info.shell || "" },
        { label: "WM", value: root.info.hyprland ? "Hyprland " + root.info.hyprland : "" },
        { label: "CPU", value: root.shortCpu(root.info.cpu) },
        { label: "GPU", value: root.shortGpu(root.info.gpu) },
        { label: "Memory", value: root.info.memory || "" }
    ]

    Column {
        anchors.fill: parent
        anchors.margins: 22
        anchors.topMargin: 20
        spacing: 14

        Row {
            spacing: 12

            IconGlyph {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{F303}"
                color: Theme.textPrimary
                size: 26
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.info.user ? root.info.user + "@" + root.info.host : "This machine"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.weight: Font.Bold
                font.family: Theme.fontText
            }
        }

        Column {
            width: parent.width
            spacing: 6

            Repeater {
                model: root.rows

                Row {
                    id: row
                    required property var modelData
                    width: parent.width
                    spacing: 12

                    Text {
                        width: 72
                        text: row.modelData.label
                        color: Theme.textMuted
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        font.family: Theme.fontText
                    }

                    Text {
                        width: parent.width - 84
                        text: row.modelData.value.length > 0 ? row.modelData.value : "Unknown"
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.family: Theme.fontText
                        font.features: Theme.tabular
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
