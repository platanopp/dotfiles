import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.desktop
import qs.services

// What fastfetch used to print, set like the control panel's header: picture, name, host and
// uptime, then the system and hardware as label and value (Settings -> About's data, about.py).
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
            root.uptime = "up " + (d > 0 ? d + "d " : "") + h + "h " + m + "m"
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.live
        triggeredOnStart: true
        onTriggered: uptimeFile.reload()
    }

    // Vendor boilerplate off the hardware names: "Intel(R) Core(TM) i7-10700F
    // CPU @ 2.90GHz" is an i7-10700F.
    function shortCpu(s) {
        return (s || "").replace(/\(R\)|\(TM\)/g, "").replace(/\bCPU\b.*$/, "")
                        .replace(/^Intel\s+Core\s+/, "Core ").replace(/\s+/g, " ").trim()
    }
    function shortGpu(s) {
        return (s || "").replace(/^NVIDIA\s+GeForce\s+/, "GeForce ").trim()
    }

    readonly property var rows: [
        { label: "Kernel", value: root.info.kernel || "" },
        { label: "Packages", value: root.info.packages ? root.info.packages + " (pacman)" : "" },
        { label: "Shell", value: root.info.shell || "" },
        { label: "WM", value: root.info.hyprland ? "Hyprland " + root.info.hyprland : "" },
        { label: "CPU", value: root.shortCpu(root.info.cpu) },
        { label: "GPU", value: root.shortGpu(root.info.gpu) },
        { label: "Memory", value: root.info.memory || "" }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // The control panel's header: picture in a ring, name, then host and
        // uptime, then the distribution, each line quieter than the last.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.alpha(Theme.foreground, 0.35)
                }

                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: width / 2
                    color: Theme.surfaceContainerHigh

                    Image {
                        id: avatar
                        anchors.fill: parent
                        source: Profile.avatarSource
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 128
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: avatar.status !== Image.Ready
                        text: Profile.username.length > 0 ? Profile.username.charAt(0).toUpperCase() : "?"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.bold: true
                        font.family: Theme.fontText
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: Profile.username
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.bold: true
                    font.family: Theme.fontText
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: [root.info.host || "", root.uptime].filter(s => s.length > 0).join(" · ")
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontText
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.info.os || ""
                    color: Theme.textMuted
                    opacity: 0.7
                    font.pixelSize: 10
                    font.family: Theme.fontText
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.outline
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 6
            columnSpacing: 12

            Repeater {
                model: root.rows

                Text {
                    required property var modelData
                    required property int index
                    Layout.row: index
                    Layout.column: 0
                    text: modelData.label
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: Theme.fontText
                }
            }

            Repeater {
                model: root.rows

                Text {
                    required property var modelData
                    required property int index
                    Layout.row: index
                    Layout.column: 1
                    Layout.fillWidth: true
                    text: modelData.value.length > 0 ? modelData.value : "Unknown"
                    color: modelData.value.length > 0 ? Theme.textPrimary : Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                    elide: Text.ElideRight
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
