import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

PanelWindow {
    id: statusItem
    property var bar: null
    screen: bar.screen
    visible: true

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
    color: "transparent"

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

    // Set by shell.qml, which owns the order of the right-hand pills.
    property int rightMargin: 50
    margins.right: rightMargin

    Behavior on margins.right {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    property string expandedPanel: ""

    function togglePanel(name) {
        if (statusItem.expandedPanel === name) {
            statusItem.expandedPanel = ""
            return
        }
        statusItem.expandedPanel = name
        if (name === "wifi") AppState.scanWifiNetworks()
        if (name === "bluetooth") AppState.scanBluetoothDevices()
        if (name === "audio") {
            AppState.refreshAudioSinks()
            AppState.refreshAudioStreams()
        }
    }

    function signalIcon(signal) {
        if (signal >= 70) return "󰤨"
        if (signal >= 40) return "󰤢"
        return "󰤟"
    }

    readonly property int compactWidth: compactRow.implicitWidth + 48

    implicitWidth: expandedPanel !== "" ? 324 : compactWidth

    // Follows the content instead of a fixed 524, which left a large empty
    // box under short lists. Chrome is the 12px inset, the 40px compact row,
    // and the flickable's margins; past the cap the list scrolls.
    implicitHeight: expandedPanel !== "" ? Math.min(expandedColumn.implicitHeight + 84, 620) : 64

    Behavior on implicitWidth {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    Behavior on implicitHeight {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    Item {
        id: contentArea
        visible: !bar.barHidden
        anchors.fill: parent
        anchors.margins: 12

    Rectangle {
        id: statusGlass
        anchors.fill: parent
        radius: statusItem.expandedPanel !== "" ? 26 : 20
        color: Theme.glass
        visible: false
        layer.enabled: true

        Behavior on radius {
            NumberAnimation { duration: 200 }
        }
    }

    MultiEffect {
        source: statusGlass
        anchors.fill: statusGlass
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.5
        shadowBlur: 0.7
        shadowVerticalOffset: 4
        autoPaddingEnabled: true
    }

    Item {
        id: compactRowContainer
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 40

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: 14

            IconGlyph {
                visible: AppState.dndEnabled
                text: "󰂛"
                color: AppState.themeAccent
                size: Theme.iconLarge
            }

            RowLayout {
                spacing: 6

                IconGlyph {
                    text: AppState.wifiSsid.length > 0 ? "󰤨" : "󰤭"
                    color: Theme.textPrimary
                    size: Theme.iconLarge
                }

                Text {
                    visible: AppState.wifiSsid.length > 0
                    text: AppState.wifiSsid
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontMono
                    elide: Text.ElideRight
                    Layout.maximumWidth: 90
                }

                TapHandler {
                    onTapped: statusItem.togglePanel("wifi")
                }
            }

            RowLayout {
                spacing: 4

                IconGlyph {
                    text: AppState.btEnabled ? "󰂯" : "󰂲"
                    color: Theme.textPrimary
                    size: Theme.iconLarge
                }

                Text {
                    visible: AppState.btEnabled && AppState.btConnectedCount > 0
                    text: AppState.btConnectedCount.toString()
                    color: AppState.themeAccent
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontMono
                }

                TapHandler {
                    onTapped: statusItem.togglePanel("bluetooth")
                }
            }

            RowLayout {
                spacing: 6

                IconGlyph {
                    text: "󰕾"
                    color: Theme.textPrimary
                    size: Theme.iconLarge
                }

                Text {
                    text: Math.round(AppState.volumePercent) + "%"
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontMono
                }

                TapHandler {
                    onTapped: statusItem.togglePanel("audio")
                }
            }

            IconGlyph {
                text: AppState.micMuted ? "󰍭" : "󰍬"
                color: AppState.micMuted ? Theme.error : Theme.textPrimary
                size: Theme.iconLarge

                TapHandler {
                    onTapped: AppState.toggleMicMute()
                }
            }

            RowLayout {
                visible: AppState.batteryPresent
                spacing: 4

                IconGlyph {
                    text: AppState.batteryPercent >= 80 ? "󰁹" : AppState.batteryPercent >= 50 ? "󰁾" : AppState.batteryPercent >= 20 ? "󰁻" : "󰁺"
                    color: AppState.batteryPercent <= 15 ? Theme.error : Theme.textPrimary
                    size: Theme.iconLarge
                }

                Text {
                    text: Math.round(AppState.batteryPercent) + "%"
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontMono
                }
            }
        }
    }

    HyprlandFocusGrab {
        id: statusGrab
        windows: [statusItem]
        active: statusItem.expandedPanel !== ""
        onCleared: statusItem.expandedPanel = ""
    }

    // The media widget reads the same list, so the polling lives in AppState
    // and each viewer just says whether it is looking.
    readonly property bool watchingAudioStreams: statusItem.expandedPanel === "audio"
    onWatchingAudioStreamsChanged:
        watchingAudioStreams ? AppState.watchAudioStreams() : AppState.unwatchAudioStreams()
    Component.onDestruction: if (watchingAudioStreams) AppState.unwatchAudioStreams()

    Flickable {
        visible: statusItem.expandedPanel !== ""
        opacity: statusItem.expandedPanel !== "" ? 1 : 0
        anchors.top: compactRowContainer.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.topMargin: 4
        contentHeight: expandedColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        Column {
            id: expandedColumn
            width: parent.width
            spacing: 14

            Column {
                width: parent.width
                spacing: 10
                visible: statusItem.expandedPanel === "wifi"


            RowLayout {
                width: parent.width

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Wi-Fi networks"
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.bold: true
                        font.family: Theme.fontMono
                    }

                    Text {
                        visible: AppState.wifiSsid.length > 0
                        text: AppState.wifiSsid + " · " + (AppState.wifiIp.length > 0 ? AppState.wifiIp : "obteniendo IP...")
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                IconButton {
                    icon: "󰑐"
                    size: 28
                    glyphSize: Theme.iconMedium
                    iconColor: Theme.textPrimary
                    onTapped: AppState.scanWifiNetworks()
                }
            }

            Text {
                visible: AppState.wifiNetworks.length === 0
                text: "Scanning for networks..."
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontMono
            }

            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: AppState.wifiNetworks

                    Column {
                        id: networkRow
                        required property var modelData
                        width: parent.width
                        spacing: 6

                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 14
                            color: networkRow.modelData.inUse ? AppState.themeAccent : Theme.surfaceContainer

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                IconGlyph {
                                    text: statusItem.signalIcon(networkRow.modelData.signal)
                                    color: networkRow.modelData.inUse ? Theme.accentText : Theme.textPrimary
                                    size: Theme.iconMedium
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        text: networkRow.modelData.ssid
                                        color: networkRow.modelData.inUse ? Theme.accentText : Theme.textPrimary
                                        font.pixelSize: 13
                                        font.bold: networkRow.modelData.inUse
                                        font.family: Theme.fontMono
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }

                                    Text {
                                        text: networkRow.modelData.signal + "% · " + (networkRow.modelData.secure ? "Protegida" : "Open")
                                        color: networkRow.modelData.inUse ? Theme.accentText : Theme.textMuted
                                        opacity: networkRow.modelData.inUse ? 0.7 : 1
                                        font.pixelSize: 10
                                        font.family: Theme.fontMono
                                    }
                                }

                                IconGlyph {
                                    visible: networkRow.modelData.secure && !networkRow.modelData.inUse
                                    text: "󰌾"
                                    color: Theme.textMuted
                                    size: Theme.iconSmall
                                }

                                IconGlyph {
                                    visible: networkRow.modelData.inUse
                                    text: "󰄬"
                                    color: Theme.accentText
                                    size: Theme.iconSmall
                                }
                            }

                            StateLayer {
                                interactive: !networkRow.modelData.inUse
                                onTapped: {
                                    if (networkRow.modelData.secure) {
                                        AppState.toggleWifiExpand(networkRow.modelData.ssid)
                                    } else {
                                        AppState.connectToWifi(networkRow.modelData.ssid, "", false)
                                    }
                                }
                            }
                        }

                        Column {
                            visible: AppState.wifiExpandedSsid === networkRow.modelData.ssid
                            width: parent.width
                            spacing: 6

                            onVisibleChanged: {
                                if (visible) wifiPasswordInput.forceActiveFocus()
                            }

                            Rectangle {
                                width: parent.width
                                height: 34
                                radius: 12
                                color: Theme.surfaceContainer

                                TextInput {
                                    id: wifiPasswordInput
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: Theme.fontMono
                                    echoMode: TextInput.Password
                                    clip: true
                                    activeFocusOnTab: true
                                    onAccepted: AppState.connectToWifi(networkRow.modelData.ssid, text, true)
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 32
                                radius: 12
                                color: AppState.themeAccent
                                opacity: AppState.wifiConnecting ? 0.6 : 1

                                Text {
                                    anchors.centerIn: parent
                                    text: AppState.wifiConnecting ? "Connecting..." : "Conectar"
                                    color: Theme.accentText
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: Theme.fontMono
                                }

                                StateLayer {
                                    tint: Theme.accentText
                                    interactive: !AppState.wifiConnecting
                                    onTapped: AppState.connectToWifi(networkRow.modelData.ssid, wifiPasswordInput.text, true)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: AppState.wifiStatusMessage.length > 0
                text: AppState.wifiStatusMessage
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontMono
                width: parent.width
                wrapMode: Text.WordWrap
            }
            }

            Column {
                width: parent.width
                spacing: 10
                visible: statusItem.expandedPanel === "bluetooth"


            RowLayout {
                width: parent.width

                Column {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Bluetooth devices"
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.bold: true
                        font.family: Theme.fontMono
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: AppState.btConnectedCount > 0
                              ? AppState.btConnectedCount + (AppState.btConnectedCount === 1
                                                             ? " connected" : " connected")
                              : "None connected"
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontMono
                    }
                }

                IconButton {
                    icon: "󰑐"
                    size: 28
                    glyphSize: Theme.iconMedium
                    iconColor: Theme.textPrimary
                    onTapped: AppState.scanBluetoothDevices()
                }
            }

            Text {
                visible: AppState.bluetoothDevices.length === 0
                text: "Scanning for devices..."
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontMono
            }

            Column {
                width: parent.width
                spacing: 6

                Repeater {
                    model: AppState.bluetoothDevices

                    Rectangle {
                        id: btDeviceRow
                        required property var modelData
                        width: parent.width
                        height: 44
                        radius: 14
                        // Unpaired devices still get a faint surface, otherwise
                        // the row reads as a gap in the list.
                        color: btDeviceRow.modelData.connected ? AppState.themeAccent
                             : (btDeviceRow.modelData.paired ? Theme.surfaceContainer : Theme.alpha(Theme.foreground, 0.04))

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            IconGlyph {
                                text: "󰂯"
                                color: btDeviceRow.modelData.connected ? Theme.accentText : Theme.textPrimary
                                size: Theme.iconMedium
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: btDeviceRow.modelData.name
                                    color: btDeviceRow.modelData.connected ? Theme.accentText : Theme.textPrimary
                                    font.pixelSize: 13
                                    font.bold: btDeviceRow.modelData.connected
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                Text {
                                    visible: !btDeviceRow.modelData.connected && btDeviceRow.modelData.paired
                                    text: "Paired"
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontMono
                                }
                            }

                            IconGlyph {
                                visible: btDeviceRow.modelData.connected
                                text: "󰄬"
                                color: Theme.accentText
                                size: Theme.iconSmall
                            }
                        }

                        StateLayer {
                            interactive: !AppState.btActionInProgress
                            onTapped: {
                                if (btDeviceRow.modelData.connected) {
                                    AppState.disconnectBluetoothDevice(btDeviceRow.modelData.mac, btDeviceRow.modelData.name)
                                } else {
                                    AppState.connectBluetoothDevice(btDeviceRow.modelData.mac, btDeviceRow.modelData.name, btDeviceRow.modelData.paired)
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: AppState.btStatusMessage.length > 0
                text: AppState.btStatusMessage
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontMono
                width: parent.width
                wrapMode: Text.WordWrap
            }
            }

            Column {
                width: parent.width
                spacing: 14
                visible: statusItem.expandedPanel === "audio"


            Text {
                text: "Audio"
                color: Theme.textPrimary
                font.pixelSize: 14
                font.bold: true
                font.family: Theme.fontMono
            }

                                            Column {
                                                width: parent.width
                                                spacing: 6

                                                RowLayout {
                                                    width: parent.width

                                                    IconGlyph {
                                                        text: "󰕾"
                                                        color: Theme.textPrimary
                                                        size: Theme.iconSmall
                                                    }

                                                    Text {
                                                        text: "Volume"
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 13
                                                        font.family: Theme.fontMono
                                                        Layout.fillWidth: true
                                                        Layout.leftMargin: 4
                                                    }

                                                    Text {
                                                        text: Math.round(AppState.volumePercent) + "%"
                                                        color: Theme.textSecondary
                                                        font.pixelSize: 12
                                                        font.family: Theme.fontMono
                                                    }
                                                }

                                                Item {
                                                    width: parent.width
                                                    height: 20

                                                    Rectangle {
                                                        id: volumeTrack
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width
                                                        height: 6
                                                        radius: 3
                                                        color: Theme.track

                                                        Rectangle {
                                                            width: volumeTrack.width * (AppState.volumePercent / 100)
                                                            height: parent.height
                                                            radius: 3
                                                            color: AppState.themeAccent
                                                        }

                                                        Rectangle {
                                                            width: 14
                                                            height: 14
                                                            radius: 7
                                                            color: Theme.textPrimary
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            x: volumeTrack.width * (AppState.volumePercent / 100) - width / 2
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        onPressed: AppState.setVolume((mouseX / width) * 100)
                                                        onPositionChanged: if (pressed) AppState.setVolume((mouseX / width) * 100)
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Theme.outline
                                            }

                                            Column {
                                                width: parent.width
                                                spacing: 6

                                                Text {
                                                    text: "Audio output"
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 13
                                                    font.family: Theme.fontMono
                                                }

                                                Text {
                                                    visible: AppState.audioSinks.length === 0
                                                    text: "Looking for outputs..."
                                                    color: Theme.textMuted
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontMono
                                                }

                                                Column {
                                                    width: parent.width
                                                    spacing: 4

                                                    Repeater {
                                                        model: AppState.audioSinks

                                                        Rectangle {
                                                            id: sinkRow
                                                            required property var modelData
                                                            width: parent.width
                                                            height: 34
                                                            radius: 12
                                                            color: sinkRow.modelData.isDefault ? Theme.surfaceContainer : "transparent"

                                                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                                            RowLayout {
                                                                anchors.fill: parent
                                                                anchors.leftMargin: 10
                                                                anchors.rightMargin: 10
                                                                spacing: 8

                                                                IconGlyph {
                                                                    text: sinkRow.modelData.isDefault ? "󰓃" : "󰓄"
                                                                    color: sinkRow.modelData.isDefault ? AppState.themeAccent : Theme.textPrimary
                                                                    size: Theme.iconMedium
                                                                }

                                                                Text {
                                                                    text: sinkRow.modelData.name
                                                                    color: sinkRow.modelData.isDefault ? AppState.themeAccent : Theme.textPrimary
                                                                    font.pixelSize: 12
                                                                    font.bold: sinkRow.modelData.isDefault
                                                                    font.family: Theme.fontMono
                                                                    elide: Text.ElideRight
                                                                    Layout.fillWidth: true
                                                                }
                                                            }

                                                            StateLayer {
                                                                interactive: !sinkRow.modelData.isDefault
                                                                onTapped: AppState.setDefaultSink(sinkRow.modelData.id)
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Theme.outline
                                            }

                                            Column {
                                                width: parent.width
                                                spacing: 8

                                                Text {
                                                    text: "Per-app volume"
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 13
                                                    font.family: Theme.fontMono
                                                }

                                                Text {
                                                    visible: AppState.audioStreams.length === 0
                                                    text: "Nothing is playing audio"
                                                    color: Theme.textMuted
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontMono
                                                }

                                                Column {
                                                    width: parent.width
                                                    spacing: 10

                                                    Repeater {
                                                        model: AppState.audioStreams

                                                        Column {
                                                            id: streamRow
                                                            required property var modelData
                                                            width: parent.width
                                                            spacing: 4

                                                            property real localVolume: streamRow.modelData.volume

                                                            onModelDataChanged: streamRow.localVolume = streamRow.modelData.volume

                                                            RowLayout {
                                                                width: parent.width
                                                                spacing: 8

                                                                IconImage {
                                                                    implicitSize: 32
                                                                    mipmap: true
                                                                    source: AppState.resolveAppIcon(streamRow.modelData.icons)
                                                                }

                                                                Text {
                                                                    text: streamRow.modelData.name
                                                                    color: Theme.textPrimary
                                                                    font.pixelSize: 12
                                                                    font.family: Theme.fontMono
                                                                    elide: Text.ElideRight
                                                                    Layout.fillWidth: true
                                                                }

                                                                Text {
                                                                    text: Math.round(streamRow.localVolume) + "%"
                                                                    color: Theme.textSecondary
                                                                    font.pixelSize: 11
                                                                    font.family: Theme.fontMono
                                                                }
                                                            }

                                                            Item {
                                                                width: parent.width
                                                                height: 16

                                                                Rectangle {
                                                                    id: streamTrack
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: parent.width
                                                                    height: 5
                                                                    radius: 3
                                                                    color: Theme.track

                                                                    Rectangle {
                                                                        width: streamTrack.width * (streamRow.localVolume / 100)
                                                                        height: parent.height
                                                                        radius: 3
                                                                        color: AppState.themeAccent
                                                                    }

                                                                    Rectangle {
                                                                        width: 12
                                                                        height: 12
                                                                        radius: 6
                                                                        color: Theme.textPrimary
                                                                        anchors.verticalCenter: parent.verticalCenter
                                                                        x: streamTrack.width * (streamRow.localVolume / 100) - width / 2
                                                                    }
                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    onPressed: {
                                                                        AppState.audioStreamsDragging = true
                                                                        streamRow.localVolume = Math.max(0, Math.min(100, Math.round((mouseX / width) * 100)))
                                                                        AppState.setStreamVolumeThrottled(streamRow.modelData.id, streamRow.localVolume)
                                                                    }
                                                                    onPositionChanged: if (pressed) {
                                                                        streamRow.localVolume = Math.max(0, Math.min(100, Math.round((mouseX / width) * 100)))
                                                                        AppState.setStreamVolumeThrottled(streamRow.modelData.id, streamRow.localVolume)
                                                                    }
                                                                    onReleased: AppState.audioStreamsDragging = false
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

            }
        }
    }
}
}
