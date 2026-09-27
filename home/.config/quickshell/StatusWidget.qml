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
    // Hidden under the Settings window while it is open: it sits where
    // Settings grows to, and a layer surface that is re-created (this one is,
    // whenever its contents come and go) stacks itself above older ones.
    property bool covered: false

    mask: bar.barHidden || covered ? blankMask : stageMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Input only where the pill is: the window also holds the room the pill
    // grows into (see PillStage).
    Region {
        id: stageMask
        item: stage
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
    margins.top: Math.max(0, AppState.gapTop - 12)

    // Set by shell.qml, which owns the order of the right-hand pills. Not
    // animated here: it follows the control pill's box, which already moves
    // smoothly, and a second animation chasing that one is what made the
    // row lag and wobble behind an opening panel.
    property int rightMargin: 50
    margins.right: rightMargin

    property string expandedPanel: ""

    // A panel's heading: title, one line of state under it, and whatever
    // controls it carries on the right (a switch, refresh, settings).
    component PanelHeader: RowLayout {
        id: header
        property string title: ""
        property string subtitle: ""
        default property alias controls: slot.data
        width: parent ? parent.width : 0
        spacing: 8

        Column {
            Layout.fillWidth: true
            spacing: 1

            Text {
                text: header.title
                color: Theme.textPrimary
                font.pixelSize: 14
                font.bold: true
                font.family: Theme.fontMono
            }

            Text {
                visible: text.length > 0
                width: parent.width
                text: header.subtitle
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontMono
                elide: Text.ElideRight
            }
        }

        Row {
            id: slot
            Layout.alignment: Qt.AlignVCenter
            spacing: 6
        }
    }

    // Refresh that spins while its scan runs.
    component ScanButton: IconButton {
        id: scan
        property bool busy: false
        icon: "\u{F0450}"
        size: 28
        glyphSize: Theme.iconMedium
        iconColor: Theme.textPrimary
        interactive: !scan.busy
        opacity: scan.busy ? 0.6 : 1

        RotationAnimation on rotation {
            running: scan.busy
            loops: Animation.Infinite
            from: 0; to: 360
            duration: 900
            onStopped: scan.rotation = 0
        }
    }

    // A small heading inside a panel.
    component PanelLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 10
        font.bold: true
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
        font.family: Theme.fontMono
    }

    // Said plainly when there is nothing to list, and why.
    component EmptyNote: Text {
        width: parent ? parent.width : 0
        color: Theme.textMuted
        font.pixelSize: 12
        font.family: Theme.fontMono
        horizontalAlignment: Text.AlignHCenter
        topPadding: 10
        bottomPadding: 10
        wrapMode: Text.WordWrap
    }


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
            AppState.refreshAudioSources()
            AppState.refreshAudioStreams()
        }
    }

    function signalIcon(signal) {
        if (signal >= 75) return "\u{F0928}"
        if (signal >= 50) return "\u{F0925}"
        if (signal >= 25) return "\u{F0922}"
        return "\u{F091F}"
    }

    // What the bar shows for the network: Wi-Fi by strength, a cable when
    // wired, and the difference between Wi-Fi off and just not connected.
    readonly property string networkIcon: AppState.wifiSsid.length > 0
        ? statusItem.signalIcon(AppState.wifiSignal < 0 ? 100 : AppState.wifiSignal)
        : AppState.ethernetUp ? "\u{F0200}"
        : !AppState.wifiRadioEnabled ? "\u{F092E}"
        : "\u{F092F}"

    function volumeIcon(v, muted) {
        if (muted || v === 0) return "\u{F0581}"
        if (v < 34) return "\u{F057F}"
        if (v < 67) return "\u{F0580}"
        return "\u{F057E}"
    }

    // Kinds of Bluetooth device, by the icon name BlueZ gives them.
    function btIcon(kind) {
        if (/headset|headphone/.test(kind)) return "\u{F02CB}"
        if (/audio|speaker/.test(kind)) return "\u{F04C3}"
        if (/gaming|joystick/.test(kind)) return "\u{F0296}"
        if (/mouse/.test(kind)) return "\u{F037D}"
        if (/keyboard/.test(kind)) return "\u{F030C}"
        if (/phone/.test(kind)) return "\u{F011C}"
        if (/computer/.test(kind)) return "\u{F0322}"
        return "\u{F00AF}"
    }

    readonly property int compactWidth: compactRow.implicitWidth + 24 + Theme.pillPaddingH * 2

    // The pill's box, animated inside a window that is not (see PillStage).
    PillStage {
        id: stage
        anchors.top: parent.top
        anchors.right: parent.right
        // Sized for the open panel from the start and never resized: a
        // window anchored on the right that grows moves its left edge, and
        // for the frame the compositor takes to get the new buffer it showed
        // the old one there -- the pill flicked left over the tray.
        minWindowWidth: 324
        minWindowHeight: 620
        targetWidth: statusItem.expandedPanel !== "" ? 324 : statusItem.compactWidth
        // Follows the content instead of a fixed 524, which left a large empty
        // box under short lists. Chrome is the 12px inset, the 40px compact row,
        // and the flickable's margins; past the cap the list scrolls.
        targetHeight: statusItem.expandedPanel !== "" ? Math.min(expandedColumn.implicitHeight + 84, 620) : 64
    }

    implicitWidth: stage.windowWidth
    implicitHeight: stage.windowHeight

    // What the pills beside this one park off: the box as drawn, mid-move
    // included, not the window around it.
    readonly property real visualWidth: stage.width

    Item {
        id: contentArea
        visible: !bar.barHidden && !covered
        anchors.fill: stage
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

                // The icon alone: the network's name is in the panel it opens.
                IconGlyph {
                    text: statusItem.networkIcon
                    color: AppState.wifiSsid.length > 0 || AppState.ethernetUp ? Theme.textPrimary : Theme.textMuted
                    size: Theme.iconLarge
                }

                TapHandler {
                    onTapped: statusItem.togglePanel("wifi")
                }
            }

            RowLayout {
                spacing: 4

                IconGlyph {
                    text: !AppState.btEnabled ? "\u{F00B2}"
                        : AppState.btConnectedCount > 0 ? "\u{F00B1}" : "\u{F00AF}"
                    color: AppState.btEnabled ? Theme.textPrimary : Theme.textMuted
                    size: Theme.iconLarge
                }

                Text {
                    visible: AppState.btEnabled && AppState.btConnectedCount > 1
                    text: AppState.btConnectedCount.toString()
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontMono
                }

                TapHandler {
                    onTapped: statusItem.togglePanel("bluetooth")
                }
            }

            // The wheel turns the volume up and down without opening anything.
            RowLayout {
                spacing: 6

                IconGlyph {
                    text: statusItem.volumeIcon(AppState.volumePercent, AppState.volumeMuted)
                    color: AppState.volumeMuted ? Theme.textMuted : Theme.textPrimary
                    size: Theme.iconLarge
                }

                Text {
                    text: Math.round(AppState.volumePercent) + "%"
                    color: AppState.volumeMuted ? Theme.textMuted : Theme.textPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontMono
                }

                TapHandler {
                    onTapped: statusItem.togglePanel("audio")
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        var d = event.angleDelta.y
                        if (d !== 0) AppState.setVolume(AppState.volumePercent + (d > 0 ? 5 : -5))
                    }
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

            // ── Wi-Fi ────────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 10
                visible: statusItem.expandedPanel === "wifi"

                PanelHeader {
                    title: "Wi-Fi"
                    subtitle: !AppState.wifiRadioEnabled ? "Off"
                        : AppState.wifiSsid.length > 0
                            ? AppState.wifiSsid + " · " + (AppState.wifiIp.length > 0 ? AppState.wifiIp : "getting an address…")
                        : AppState.ethernetUp ? "Using a wired connection"
                        : "Not connected"

                    ScanButton {
                        visible: AppState.wifiRadioEnabled
                        busy: AppState.wifiScanning
                        onTapped: AppState.scanWifiNetworks()
                    }

                    SettingsSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: AppState.wifiRadioEnabled
                        onToggled: {
                            AppState.toggleWifiRadio()
                            if (!AppState.wifiRadioEnabled) return
                            wifiRescan.restart()
                        }

                        // The radio takes a moment to come up before it
                        // can see anything.
                        Timer {
                            id: wifiRescan
                            interval: 2500
                            onTriggered: AppState.scanWifiNetworks()
                        }
                    }
                }

                EmptyNote {
                    visible: !AppState.wifiRadioEnabled
                    text: "Wi-Fi is off"
                }

                EmptyNote {
                    visible: AppState.wifiRadioEnabled && AppState.wifiNetworks.length === 0
                    text: AppState.wifiScanning ? "Looking for networks…" : "No networks found"
                }

                Column {
                    width: parent.width
                    spacing: 6
                    visible: AppState.wifiRadioEnabled

                    Repeater {
                        model: AppState.wifiNetworks

                        Column {
                            id: networkRow
                            required property var modelData
                            readonly property bool open: AppState.wifiExpandedSsid === networkRow.modelData.ssid
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                width: parent.width
                                height: 46
                                radius: 14
                                color: networkRow.modelData.inUse ? Theme.accent : Theme.surfaceContainer

                                Behavior on color { ColorAnimation { duration: Theme.durShort } }

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
                                            text: (networkRow.modelData.inUse ? "Connected"
                                                   : networkRow.modelData.saved ? "Saved"
                                                   : networkRow.modelData.secure ? "Secured" : "Open")
                                                  + " · " + networkRow.modelData.signal + "%"
                                            color: networkRow.modelData.inUse ? Theme.accentText : Theme.textMuted
                                            opacity: networkRow.modelData.inUse ? 0.75 : 1
                                            font.pixelSize: 10
                                            font.family: Theme.fontMono
                                        }
                                    }

                                    IconGlyph {
                                        visible: networkRow.modelData.secure
                                        text: "\u{F033E}"
                                        color: networkRow.modelData.inUse ? Theme.accentText : Theme.textMuted
                                        size: Theme.iconSmall
                                    }
                                }

                                // Saved and open networks connect at once;
                                // a new secured one asks for its password;
                                // the one in use offers to disconnect.
                                StateLayer {
                                    tint: networkRow.modelData.inUse ? Theme.accentText : Theme.foreground
                                    interactive: !AppState.wifiConnecting
                                    onTapped: {
                                        var n = networkRow.modelData
                                        if (n.inUse || (n.secure && !n.saved))
                                            AppState.toggleWifiExpand(n.ssid)
                                        else
                                            AppState.connectToWifi(n.ssid, "", n.secure, n.saved)
                                    }
                                }
                            }

                            // The one in use: disconnect.
                            Row {
                                visible: networkRow.open && networkRow.modelData.inUse
                                anchors.right: parent.right
                                spacing: 6

                                PillButton {
                                    text: "Disconnect"
                                    available: !AppState.wifiConnecting
                                    onClicked: AppState.disconnectWifi(networkRow.modelData.ssid)
                                }
                            }

                            // A new secured one: its password.
                            RowLayout {
                                visible: networkRow.open && !networkRow.modelData.inUse
                                width: parent.width
                                spacing: 6

                                onVisibleChanged: if (visible) wifiPasswordInput.forceActiveFocus()

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: 18
                                    color: Theme.surfaceContainer
                                    border.width: wifiPasswordInput.activeFocus ? 1 : 0
                                    border.color: Theme.alpha(Theme.foreground, 0.4)

                                    TextInput {
                                        id: wifiPasswordInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 36
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontMono
                                        echoMode: reveal.shown ? TextInput.Normal : TextInput.Password
                                        clip: true
                                        activeFocusOnTab: true
                                        onAccepted: if (text.length > 0)
                                            AppState.connectToWifi(networkRow.modelData.ssid, text, true, false)

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: wifiPasswordInput.text.length === 0
                                            text: "Password"
                                            color: Theme.textMuted
                                            font: wifiPasswordInput.font
                                        }
                                    }

                                    IconButton {
                                        id: reveal
                                        property bool shown: false
                                        anchors.right: parent.right
                                        anchors.rightMargin: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        icon: reveal.shown ? "\u{F0209}" : "\u{F0208}"
                                        onTapped: reveal.shown = !reveal.shown
                                    }
                                }

                                PillButton {
                                    text: AppState.wifiConnecting ? "…" : "Connect"
                                    emphasis: true
                                    available: !AppState.wifiConnecting && wifiPasswordInput.text.length > 0
                                    onClicked: AppState.connectToWifi(networkRow.modelData.ssid, wifiPasswordInput.text, true, false)
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: AppState.wifiStatusMessage.length > 0
                    text: AppState.wifiStatusMessage
                    color: /Wrong|Could not|out of range/.test(AppState.wifiStatusMessage) ? Theme.error : Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            // ── Bluetooth ────────────────────────────────────────────────
            Column {
                id: btPanel
                width: parent.width
                spacing: 10
                visible: statusItem.expandedPanel === "bluetooth"

                readonly property var mine: AppState.bluetoothDevices.filter(d => d.paired)
                readonly property var nearby: AppState.bluetoothDevices.filter(d => !d.paired)

                PanelHeader {
                    title: "Bluetooth"
                    subtitle: !AppState.btEnabled ? "Off"
                        : AppState.btConnectedCount > 0 ? AppState.btConnectedCount + " connected"
                        : "Nothing connected"

                    ScanButton {
                        visible: AppState.btEnabled
                        busy: AppState.btScanning
                        onTapped: AppState.scanBluetoothDevices()
                    }

                    SettingsSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: AppState.btEnabled
                        onToggled: {
                            AppState.toggleBluetoothPower()
                            if (AppState.btEnabled) btRescan.restart()
                        }

                        Timer {
                            id: btRescan
                            interval: 1500
                            onTriggered: AppState.scanBluetoothDevices()
                        }
                    }
                }

                EmptyNote {
                    visible: !AppState.btEnabled
                    text: "Bluetooth is off"
                }

                EmptyNote {
                    visible: AppState.btEnabled && AppState.bluetoothDevices.length === 0
                    text: AppState.btScanning ? "Looking for devices…" : "No devices found"
                }

                Repeater {
                    model: AppState.btEnabled ? [
                        { label: "My devices", list: btPanel.mine },
                        { label: "Nearby", list: btPanel.nearby }
                    ] : []

                    Column {
                        id: btSection
                        required property var modelData
                        width: parent.width
                        spacing: 6
                        visible: btSection.modelData.list.length > 0

                        PanelLabel { text: btSection.modelData.label }

                        Repeater {
                            model: btSection.modelData.list

                            Rectangle {
                                id: btDeviceRow
                                required property var modelData
                                width: parent.width
                                height: 46
                                radius: 14
                                color: btDeviceRow.modelData.connected ? Theme.accent : Theme.surfaceContainer

                                Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                readonly property color ink: btDeviceRow.modelData.connected ? Theme.accentText : Theme.textPrimary

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 10
                                    // Over the row's StateLayer, so Forget
                                    // takes its own taps.
                                    z: 2

                                    IconGlyph {
                                        text: statusItem.btIcon(btDeviceRow.modelData.icon)
                                        color: btDeviceRow.ink
                                        size: Theme.iconMedium
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            text: btDeviceRow.modelData.name
                                            color: btDeviceRow.ink
                                            font.pixelSize: 13
                                            font.bold: btDeviceRow.modelData.connected
                                            font.family: Theme.fontMono
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: btDeviceRow.modelData.connected ? "Connected · tap to disconnect"
                                                : btDeviceRow.modelData.paired ? "Paired" : "Tap to pair"
                                            color: btDeviceRow.modelData.connected ? Theme.accentText : Theme.textMuted
                                            opacity: btDeviceRow.modelData.connected ? 0.75 : 1
                                            font.pixelSize: 10
                                            font.family: Theme.fontMono
                                        }
                                    }

                                    // Forget: paired, not in use, and asks twice.
                                    IconButton {
                                        id: forget
                                        property bool armed: false
                                        visible: btDeviceRow.modelData.paired && !btDeviceRow.modelData.connected
                                        icon: forget.armed ? "\u{F05E0}" : "\u{F01B4}"
                                        iconColor: forget.armed ? Theme.error : Theme.textMuted
                                        interactive: !AppState.btActionInProgress
                                        onTapped: {
                                            if (!forget.armed) { forget.armed = true; disarmForget.restart(); return }
                                            forget.armed = false
                                            AppState.forgetBluetoothDevice(btDeviceRow.modelData.mac, btDeviceRow.modelData.name)
                                        }

                                        Timer {
                                            id: disarmForget
                                            interval: 3000
                                            onTriggered: forget.armed = false
                                        }
                                    }
                                }

                                StateLayer {
                                    tint: btDeviceRow.modelData.connected ? Theme.accentText : Theme.foreground
                                    interactive: !AppState.btActionInProgress
                                    onTapped: {
                                        var d = btDeviceRow.modelData
                                        if (d.connected) AppState.disconnectBluetoothDevice(d.mac, d.name)
                                        else AppState.connectBluetoothDevice(d.mac, d.name, d.paired)
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: AppState.btStatusMessage.length > 0
                    text: AppState.btStatusMessage
                    color: AppState.btStatusMessage.indexOf("Could not") === 0 ? Theme.error : Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontMono
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            // ── Sound ────────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 14
                visible: statusItem.expandedPanel === "audio"

                PanelHeader {
                    title: "Sound"
                    subtitle: {
                        for (var i = 0; i < AppState.audioSinks.length; i++)
                            if (AppState.audioSinks[i].isDefault) return AppState.audioSinks[i].name
                        return ""
                    }

                    // The full page: input devices, and everything else.
                    IconButton {
                        icon: "\u{F0493}"
                        size: 28
                        glyphSize: Theme.iconMedium
                        iconColor: Theme.textPrimary
                        onTapped: {
                            statusItem.expandedPanel = ""
                            AppState.openSettings("sound", statusItem.screen ? statusItem.screen.name : "")
                        }
                    }
                }

                // Output and microphone: a mute button, the level, the number.
                Repeater {
                    model: [
                        { key: "out" },
                        { key: "mic" }
                    ]

                    RowLayout {
                        id: level
                        required property var modelData
                        readonly property bool isMic: level.modelData.key === "mic"
                        readonly property bool muted: level.isMic ? AppState.micMuted : AppState.volumeMuted
                        width: parent.width
                        spacing: 10

                        IconButton {
                            icon: level.isMic ? (AppState.micMuted ? "\u{F036D}" : "\u{F036C}")
                                              : statusItem.volumeIcon(AppState.volumePercent, AppState.volumeMuted)
                            size: 30
                            glyphSize: Theme.iconMedium
                            iconColor: level.muted ? (level.isMic ? Theme.error : Theme.textMuted) : Theme.textPrimary
                            onTapped: level.isMic ? AppState.toggleMicMute() : AppState.toggleVolumeMute()
                        }

                        SettingsSlider {
                            id: levelSlider
                            Layout.fillWidth: true
                            compact: true
                            live: !level.isMic
                            opacity: level.muted ? 0.45 : 1
                            from: 0; to: level.isMic ? 150 : 100; step: 1
                            neutral: level.isMic ? 100 : NaN
                            value: level.isMic ? AppState.micVolume : AppState.volumePercent
                            onMoved: v => level.isMic ? AppState.setMicVolume(v) : AppState.setVolume(v)
                        }

                        Text {
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(levelSlider.shown) + "%"
                            color: level.muted ? Theme.textMuted : Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontMono
                        }
                    }
                }

                // Where it plays.
                Column {
                    width: parent.width
                    spacing: 4
                    visible: AppState.audioSinks.length > 1

                    PanelLabel { text: "Output" }

                    Repeater {
                        model: AppState.audioSinks

                        Rectangle {
                            id: sinkRow
                            required property var modelData
                            width: parent.width
                            height: 36
                            radius: 12
                            color: sinkRow.modelData.isDefault ? Theme.surfaceContainer : "transparent"

                            Behavior on color { ColorAnimation { duration: Theme.durShort } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                IconGlyph {
                                    text: /head/i.test(sinkRow.modelData.name) ? "\u{F02CB}" : "\u{F04C3}"
                                    color: sinkRow.modelData.isDefault ? Theme.textPrimary : Theme.textMuted
                                    size: Theme.iconMedium
                                }

                                Text {
                                    text: sinkRow.modelData.name
                                    color: sinkRow.modelData.isDefault ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: 12
                                    font.bold: sinkRow.modelData.isDefault
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                IconGlyph {
                                    visible: sinkRow.modelData.isDefault
                                    text: "\u{F012C}"
                                    color: Theme.textPrimary
                                    size: Theme.iconSmall
                                }
                            }

                            StateLayer {
                                radius: sinkRow.radius
                                interactive: !sinkRow.modelData.isDefault
                                onTapped: AppState.setDefaultSink(sinkRow.modelData.id)
                            }
                        }
                    }
                }

                // Each application, up to 150% like the Sound page.
                Column {
                    width: parent.width
                    spacing: 10

                    PanelLabel { text: "Applications" }

                    EmptyNote {
                        visible: AppState.audioStreams.length === 0
                        text: "Nothing is playing"
                    }

                    Repeater {
                        model: AppState.audioStreams

                        Column {
                            id: streamRow
                            required property var modelData
                            width: parent.width
                            spacing: 2

                            RowLayout {
                                width: parent.width
                                spacing: 8

                                IconImage {
                                    implicitSize: 22
                                    mipmap: true
                                    source: AppState.resolveAppIcon(streamRow.modelData.icons)
                                }

                                Text {
                                    text: AppState.streamName(streamRow.modelData.name)
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: Math.round(streamSlider.shown) + "%"
                                    color: Theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: Theme.fontMono
                                }
                            }

                            SettingsSlider {
                                id: streamSlider
                                width: parent.width
                                compact: true
                                live: true
                                from: 0; to: 150; step: 1
                                neutral: 100
                                value: streamRow.modelData.volume
                                onDraggingChanged: AppState.audioStreamsDragging = streamSlider.dragging
                                onMoved: v => AppState.setStreamVolumeThrottled(streamRow.modelData.id, v)
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
