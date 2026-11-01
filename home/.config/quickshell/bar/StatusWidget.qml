import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

PanelWindow {
    id: statusItem
    property var bar: null
    screen: bar.screen
    visible: true

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

    // Input only where the pill is; the window also holds the room it grows into (see PillStage).
    Region {
        id: stageMask
        item: stage
    }

    // Keeps the bar up while hovered; shell.qml folds these together with the reveal zone's hover.
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
    // The content insets by 12, so the window sits back that much and the
    // drawn edge lands on Hyprland's gap.
    margins.top: Math.max(0, Hypr.gapTop - 12)

    // Set by shell.qml, which orders the right-hand pills. Not animated: it follows the control
    // pill's box, and a second animation made the row lag and wobble.
    property int rightMargin: 50
    margins.right: rightMargin

    property string expandedPanel: ""

    // Escape closes it (Panels.dismissPanels, bound while any panel is up).
    readonly property bool escapeOpen: statusItem.expandedPanel !== ""
    readonly property string escapeKey: "status:" + (statusItem.screen ? statusItem.screen.name : "")
    onEscapeOpenChanged: Panels.setPanelOpen(statusItem.escapeKey, statusItem.escapeOpen)

    Connections {
        target: Panels
        function onDismissRequested() { statusItem.expandedPanel = "" }
    }

    // Each list is kept current by events only while a panel shows it; the services count who looks.
    readonly property bool watchingAudioStreams: statusItem.expandedPanel === "audio"
    onWatchingAudioStreamsChanged:
        watchingAudioStreams ? Audio.watchAudioStreams() : Audio.unwatchAudioStreams()
    readonly property bool watchingWifi: statusItem.expandedPanel === "wifi"
    onWatchingWifiChanged: {
        if (statusItem.watchingWifi) {
            Network.watchWifi()
        } else {
            Network.unwatchWifi()
            // Closed, a network opened for its password folds back.
            Network.wifiExpandedSsid = ""
        }
    }
    readonly property bool watchingBluetooth: statusItem.expandedPanel === "bluetooth"
    onWatchingBluetoothChanged:
        watchingBluetooth ? Bluetooth.watchBluetooth() : Bluetooth.unwatchBluetooth()
    Component.onDestruction: {
        if (statusItem.escapeOpen) Panels.setPanelOpen(statusItem.escapeKey, false)
        if (watchingAudioStreams) Audio.unwatchAudioStreams()
        if (watchingWifi) Network.unwatchWifi()
        if (watchingBluetooth) Bluetooth.unwatchBluetooth()
    }

    // What the panel shows. It trails expandedPanel so the content leaves the way it came: on close
    // it fades out as the glass shrinks instead of vanishing first, and a switch fades the old
    // panel out before the new one comes in.
    property string shownPanel: ""

    onExpandedPanelChanged: {
        var next = statusItem.expandedPanel
        panelFade.stop()
        // Nothing else showing: straight in, so the box grows to this panel's height from the start.
        // Reopened while closing: on from where the fade is, not from nothing.
        if (next !== "" && (statusItem.shownPanel === next || panelFlick.opacity === 0)) {
            statusItem.shownPanel = next
            fadeOut.to = panelFlick.opacity
            fadeOut.duration = 0
        } else {
            fadeOut.to = 0
            fadeOut.duration = Theme.durShort
        }
        panelFade.next = next
        fadeIn.to = next === "" ? 0 : 1
        fadeIn.duration = next === "" ? 0 : Theme.durMedium
        panelFade.start()
    }

    SequentialAnimation {
        id: panelFade
        property string next: ""

        NumberAnimation { id: fadeOut; target: panelFlick; property: "opacity"; easing.type: Easing.OutCubic }
        ScriptAction {
            script: {
                if (statusItem.shownPanel !== panelFade.next) panelFlick.contentY = 0
                statusItem.shownPanel = panelFade.next
            }
        }
        NumberAnimation { id: fadeIn; target: panelFlick; property: "opacity"; easing.type: Easing.OutCubic }
    }

    // A panel's heading: title, a line of state under it, and its controls on the right.
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
                font.family: Theme.fontText
            }

            Text {
                visible: text.length > 0
                width: parent.width
                text: header.subtitle
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        Row {
            id: slot
            Layout.alignment: Qt.AlignVCenter
            spacing: 6
        }
    }

    // Refresh that spins while its scan runs, and finishes its turn when the scan ends rather than
    // snapping back upright.
    component ScanButton: IconButton {
        id: scan
        property bool busy: false
        // One turn's time: the spin's pace, not a transition.
        readonly property int turn: 900
        icon: "\u{F0450}"
        size: 28
        glyphSize: Theme.iconMedium
        iconColor: Theme.textPrimary
        interactive: !scan.busy
        opacity: scan.busy ? 0.6 : 1

        Behavior on opacity { NumberAnimation { duration: Theme.durMedium } }

        RotationAnimation on rotation {
            running: scan.busy
            loops: Animation.Infinite
            from: 0; to: 360
            duration: scan.turn
        }

        RotationAnimation {
            id: settle
            target: scan
            property: "rotation"
            to: 360
            easing.type: Easing.OutCubic
            onFinished: scan.rotation = 0
        }

        onBusyChanged: {
            settle.stop()
            if (scan.busy) return
            // The rest of the turn, eased out over a little longer than it would take at speed.
            settle.duration = Math.max(Theme.durShort, (360 - scan.rotation % 360) / 360 * scan.turn * 1.5)
            settle.start()
        }
    }

    // A small heading inside a panel.
    component PanelLabel: Text {
        color: Theme.textSecondary
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.family: Theme.fontText
    }

    // A button in the closed pill: icon (and number) on a disc, a capsule with text, lit on hover
    // and press like the control pill's and the tray's.
    component PillButtonArea: Item {
        id: btn
        default property alias content: btnRow.data
        property int rowSpacing: 6
        signal tapped()

        implicitWidth: Math.max(30, btnRow.implicitWidth + 16)
        implicitHeight: 30

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.foreground
            opacity: btnTap.pressed ? 0.16 : btnHover.hovered ? 0.09 : 0

            Behavior on opacity {
                NumberAnimation { duration: Theme.durShort }
            }
        }

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: btn.rowSpacing
        }

        HoverHandler {
            id: btnHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: btnTap
            onTapped: btn.tapped()
        }
    }

    // Said plainly when there is nothing to list, and why.
    component EmptyNote: Text {
        width: parent ? parent.width : 0
        color: Theme.textMuted
        font.pixelSize: 12
        font.family: Theme.fontText
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
        if (name === "wifi") {
            Network.clearWifiStatus()
            Network.scanWifiNetworks()
        }
        if (name === "bluetooth") {
            Bluetooth.clearBtStatus()
            Bluetooth.scanBluetoothDevices()
        }
        if (name === "audio") {
            Audio.refreshAudioSinks()
            Audio.refreshAudioSources()
            Audio.refreshAudioStreams()
        }
    }

    function signalIcon(signal) {
        if (signal >= 75) return "\u{F0928}"
        if (signal >= 50) return "\u{F0925}"
        if (signal >= 25) return "\u{F0922}"
        return "\u{F091F}"
    }

    // The network icon: Wi-Fi by strength, a cable when wired, and Wi-Fi off
    // distinct from not connected.
    readonly property string networkIcon: Network.wifiSsid.length > 0
        ? statusItem.signalIcon(Network.wifiSignal < 0 ? 100 : Network.wifiSignal)
        : Network.ethernetUp ? "\u{F0200}"
        : !Network.wifiRadioEnabled ? "\u{F092E}"
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

    // Less the 8px the first and last buttons carry inside them, so the
    // pill's padding stays the same.
    readonly property int compactWidth: compactRow.implicitWidth + 24 + Theme.pillPaddingH * 2 - 16

    // The pill's box, animated inside a window that is not (see PillStage).
    PillStage {
        id: stage
        collapsed: bar.barHidden
        anchors.top: parent.top
        anchors.right: parent.right
        // Sized for the open panel from the start and never resized: a right-anchored
        // window that grows moves its left edge, and for a frame the old buffer showed
        // the pill flicked over the tray.
        minWindowWidth: 324
        minWindowHeight: 620
        targetWidth: statusItem.expandedPanel !== "" ? 324 : statusItem.compactWidth
        // Follows the content (a fixed 524 left empty space under short lists). Chrome is the 12px
        // inset, the pill-high row and the flickable's margins; past the cap the list scrolls.
        targetHeight: statusItem.expandedPanel !== ""
            ? Math.min(expandedColumn.implicitHeight + 44 + Theme.pillHeight, 620) : Theme.pillHeight + 24
    }

    implicitWidth: stage.windowWidth
    implicitHeight: stage.windowHeight

    // What the neighbouring pills park off: the box as drawn, mid-move included, not the window.
    readonly property real visualWidth: stage.width

    Item {
        id: contentArea
        visible: !bar.barHidden && !covered
        anchors.fill: stage
        anchors.margins: 12

    Rectangle {
        id: statusGlass
        anchors.fill: parent
        radius: statusItem.expandedPanel !== "" ? 26 : Theme.pillHeight / 2
        color: Theme.glass
        visible: false
        layer.enabled: true

        Behavior on radius {
            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
        }
    }

    MultiEffect {
        source: statusGlass
        anchors.fill: statusGlass
        shadowEnabled: true
        shadowColor: Theme.shadow
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
        height: Theme.pillHeight

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            // The buttons carry their own 8px either side, so the icons still sit 14 apart.
            spacing: 0

            IconGlyph {
                visible: Notifications.dnd
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                text: "󰂛"
                color: Theme.accent
                size: Theme.iconLarge
            }

            // Keyboard layout as a keycap the size of the icons beside it;
            // a tap switches it, like Super+Ctrl+Space.
            PillButtonArea {
                visible: KeyLayout.code !== ""
                onTapped: KeyLayout.switchNext()

                Rectangle {
                    implicitWidth: 25
                    implicitHeight: 17
                    radius: 4
                    color: "transparent"
                    border.width: 1.25
                    border.color: Theme.textMuted

                    Text {
                        anchors.centerIn: parent
                        text: KeyLayout.code
                        color: Theme.textPrimary
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0.4
                        font.family: Theme.fontText
                    }
                }
            }

            PillButtonArea {
                rowSpacing: 4
                onTapped: statusItem.togglePanel("bluetooth")

                IconGlyph {
                    text: !Bluetooth.btEnabled ? "\u{F00B2}"
                        : Bluetooth.btConnectedCount > 0 ? "\u{F00B1}" : "\u{F00AF}"
                    color: Bluetooth.btEnabled ? Theme.textPrimary : Theme.textMuted
                    size: Theme.iconLarge
                }

                Text {
                    visible: Bluetooth.btEnabled && Bluetooth.btConnectedCount > 1
                    text: Bluetooth.btConnectedCount.toString()
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: true
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }
            }

            PillButtonArea {
                onTapped: statusItem.togglePanel("wifi")

                // The icon alone: the network's name is in the panel it opens.
                IconGlyph {
                    text: statusItem.networkIcon
                    color: Network.wifiSsid.length > 0 || Network.ethernetUp ? Theme.textPrimary : Theme.textMuted
                    size: Theme.iconLarge
                }
            }

            // The wheel turns the volume up and down without opening anything.
            PillButtonArea {
                onTapped: statusItem.togglePanel("audio")

                IconGlyph {
                    text: statusItem.volumeIcon(Audio.volumePercent, Audio.volumeMuted)
                    color: Audio.volumeMuted ? Theme.textMuted : Theme.textPrimary
                    size: Theme.iconLarge
                }

                Text {
                    text: Math.round(Audio.volumePercent) + "%"
                    color: Audio.volumeMuted ? Theme.textMuted : Theme.textPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontText
                    font.features: Theme.tabular
                }

                // 5% a notch. A notch is 120: touchpads and high-resolution wheels send many smaller
                // deltas, which each moved 5% and raced the volume. Turning it up unmutes.
                WheelHandler {
                    id: volumeWheel
                    property real carry: 0
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        volumeWheel.carry += event.angleDelta.y
                        var steps = Math.trunc(volumeWheel.carry / 120)
                        if (steps === 0) return
                        volumeWheel.carry -= steps * 120
                        if (steps > 0 && Audio.volumeMuted) Audio.setVolumeMuted(false)
                        Audio.setVolume(Audio.volumePercent + steps * 5)
                    }
                }
            }

            PillButtonArea {
                onTapped: Audio.toggleMicMute()

                IconGlyph {
                    text: Audio.micMuted ? "󰍭" : "󰍬"
                    color: Audio.micMuted ? Theme.error : Theme.textPrimary
                    size: Theme.iconLarge
                }
            }

            RowLayout {
                visible: Power.batteryPresent
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 4

                IconGlyph {
                    text: Power.batteryPercent >= 80 ? "󰁹" : Power.batteryPercent >= 50 ? "󰁾" : Power.batteryPercent >= 20 ? "󰁻" : "󰁺"
                    color: Power.batteryPercent <= 15 ? Theme.error : Theme.textPrimary
                    size: Theme.iconLarge
                }

                Text {
                    text: Math.round(Power.batteryPercent) + "%"
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.family: Theme.fontText
                    font.features: Theme.tabular
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

    Flickable {
        id: panelFlick
        visible: opacity > 0
        opacity: 0
        anchors.top: compactRowContainer.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        anchors.topMargin: 4
        contentHeight: expandedColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: expandedColumn
            width: parent.width
            spacing: 14

            // Wi-Fi
            Column {
                width: parent.width
                spacing: 10
                visible: statusItem.shownPanel === "wifi"

                PanelHeader {
                    title: "Wi-Fi"
                    subtitle: !Network.wifiRadioEnabled ? "Off"
                        : Network.wifiSsid.length > 0
                            ? Network.wifiSsid + " · " + (Network.wifiIp.length > 0 ? Network.wifiIp : "getting an address…")
                        : Network.ethernetUp ? "Using a wired connection"
                        : "Not connected"

                    ScanButton {
                        visible: Network.wifiRadioEnabled
                        busy: Network.wifiScanning
                        onTapped: Network.scanWifiNetworks()
                    }

                    SettingsSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Network.wifiRadioEnabled
                        onToggled: {
                            Network.toggleWifiRadio()
                            if (!Network.wifiRadioEnabled) return
                            wifiRescan.restart()
                        }

                        // The radio takes a moment to come up before it can see anything.
                        Timer {
                            id: wifiRescan
                            interval: 2500
                            onTriggered: Network.scanWifiNetworks()
                        }
                    }
                }

                EmptyNote {
                    visible: !Network.wifiRadioEnabled
                    text: "Wi-Fi is off"
                }

                EmptyNote {
                    visible: Network.wifiRadioEnabled && Network.wifiNetworks.length === 0
                    text: Network.wifiScanning ? "Looking for networks…" : "No networks in range. Refresh to look again"
                }

                Column {
                    width: parent.width
                    spacing: 6
                    visible: Network.wifiRadioEnabled

                    Repeater {
                        model: Network.wifiNetworks

                        Column {
                            id: networkRow
                            required property var modelData
                            readonly property bool open: Network.wifiExpandedSsid === networkRow.modelData.ssid
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                width: parent.width
                                height: 46
                                radius: Theme.radiusMedium
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
                                            font.family: Theme.fontText
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
                                            font.family: Theme.fontText
                                        }
                                    }

                                    IconGlyph {
                                        visible: networkRow.modelData.secure
                                        text: "\u{F033E}"
                                        color: networkRow.modelData.inUse ? Theme.accentText : Theme.textMuted
                                        size: Theme.iconSmall
                                    }
                                }

                                // Saved and open networks connect at once, a new secured one asks
                                // for its password, the one in use offers to disconnect.
                                StateLayer {
                                    tint: networkRow.modelData.inUse ? Theme.accentText : Theme.foreground
                                    interactive: !Network.wifiConnecting
                                    onTapped: {
                                        var n = networkRow.modelData
                                        if (n.inUse || (n.secure && !n.saved))
                                            Network.toggleWifiExpand(n.ssid)
                                        else
                                            Network.connectToWifi(n.ssid, "", n.secure, n.savedName)
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
                                    available: !Network.wifiConnecting
                                    onClicked: Network.disconnectWifi()
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
                                    radius: height / 2
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
                                        font.family: Theme.fontText
                                        echoMode: reveal.shown ? TextInput.Normal : TextInput.Password
                                        clip: true
                                        activeFocusOnTab: true
                                        onAccepted: if (text.length > 0)
                                            Network.connectToWifi(networkRow.modelData.ssid, text, true, false)

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
                                    text: Network.wifiConnecting ? "…" : "Connect"
                                    emphasis: true
                                    available: !Network.wifiConnecting && wifiPasswordInput.text.length > 0
                                    onClicked: Network.connectToWifi(networkRow.modelData.ssid, wifiPasswordInput.text, true, false)
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: Network.wifiStatusMessage.length > 0
                    text: Network.wifiStatusMessage
                    color: /Wrong|Could not|out of range/.test(Network.wifiStatusMessage) ? Theme.error : Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            // Bluetooth
            Column {
                id: btPanel
                width: parent.width
                spacing: 10
                visible: statusItem.shownPanel === "bluetooth"

                readonly property var mine: Bluetooth.bluetoothDevices.filter(d => d.paired)
                readonly property var nearby: Bluetooth.bluetoothDevices.filter(d => !d.paired)

                PanelHeader {
                    title: "Bluetooth"
                    subtitle: !Bluetooth.btEnabled ? "Off"
                        : Bluetooth.btConnectedCount > 0 ? Bluetooth.btConnectedCount + " connected"
                        : "Nothing connected"

                    ScanButton {
                        visible: Bluetooth.btEnabled
                        busy: Bluetooth.btScanning
                        onTapped: Bluetooth.scanBluetoothDevices()
                    }

                    SettingsSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Bluetooth.btEnabled
                        onToggled: {
                            Bluetooth.toggleBluetoothPower()
                            if (Bluetooth.btEnabled) btRescan.restart()
                        }

                        Timer {
                            id: btRescan
                            interval: 1500
                            onTriggered: Bluetooth.scanBluetoothDevices()
                        }
                    }
                }

                EmptyNote {
                    visible: !Bluetooth.btEnabled
                    text: "Bluetooth is off"
                }

                EmptyNote {
                    visible: Bluetooth.btEnabled && Bluetooth.bluetoothDevices.length === 0
                    text: Bluetooth.btScanning ? "Looking for devices…" : "No devices found. Put yours in pairing mode, then refresh"
                }

                Repeater {
                    model: Bluetooth.btEnabled ? [
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
                                radius: Theme.radiusMedium
                                color: btDeviceRow.modelData.connected ? Theme.accent : Theme.surfaceContainer

                                Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                readonly property color ink: btDeviceRow.modelData.connected ? Theme.accentText : Theme.textPrimary

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 10
                                    // Over the row's StateLayer, so Forget takes its own taps.
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
                                            font.family: Theme.fontText
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }

                                        Text {
                                            text: btDeviceRow.modelData.connected ? "Connected · tap to disconnect"
                                                : btDeviceRow.modelData.paired ? "Paired" : "Tap to pair"
                                            color: btDeviceRow.modelData.connected ? Theme.accentText : Theme.textMuted
                                            opacity: btDeviceRow.modelData.connected ? 0.75 : 1
                                            font.pixelSize: 10
                                            font.family: Theme.fontText
                                        }
                                    }

                                    // Forget: paired, not in use, and asks twice.
                                    IconButton {
                                        id: forget
                                        property bool armed: false
                                        visible: btDeviceRow.modelData.paired && !btDeviceRow.modelData.connected
                                        icon: forget.armed ? "\u{F05E0}" : "\u{F01B4}"
                                        iconColor: forget.armed ? Theme.error : Theme.textMuted
                                        interactive: !Bluetooth.btActionInProgress
                                        onTapped: {
                                            if (!forget.armed) { forget.armed = true; disarmForget.restart(); return }
                                            forget.armed = false
                                            Bluetooth.forgetBluetoothDevice(btDeviceRow.modelData.mac, btDeviceRow.modelData.name)
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
                                    interactive: !Bluetooth.btActionInProgress
                                    onTapped: {
                                        var d = btDeviceRow.modelData
                                        if (d.connected) Bluetooth.disconnectBluetoothDevice(d.mac, d.name)
                                        else Bluetooth.connectBluetoothDevice(d.mac, d.name, d.paired)
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: Bluetooth.btStatusMessage.length > 0
                    text: Bluetooth.btStatusMessage
                    color: Bluetooth.btStatusMessage.indexOf("Could not") === 0 ? Theme.error : Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            // Sound
            Column {
                width: parent.width
                spacing: 14
                visible: statusItem.shownPanel === "audio"

                PanelHeader {
                    title: "Sound"
                    subtitle: {
                        for (var i = 0; i < Audio.audioSinks.length; i++)
                            if (Audio.audioSinks[i].isDefault) return Audio.audioSinks[i].name
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
                            Panels.openSettings("sound", statusItem.screen ? statusItem.screen.name : "")
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
                        readonly property bool muted: level.isMic ? Audio.micMuted : Audio.volumeMuted
                        width: parent.width
                        spacing: 10

                        IconButton {
                            icon: level.isMic ? (Audio.micMuted ? "\u{F036D}" : "\u{F036C}")
                                              : statusItem.volumeIcon(Audio.volumePercent, Audio.volumeMuted)
                            size: 30
                            glyphSize: Theme.iconMedium
                            iconColor: level.muted ? (level.isMic ? Theme.error : Theme.textMuted) : Theme.textPrimary
                            onTapped: level.isMic ? Audio.toggleMicMute() : Audio.toggleVolumeMute()
                        }

                        SettingsSlider {
                            id: levelSlider
                            Layout.fillWidth: true
                            compact: true
                            live: !level.isMic
                            opacity: level.muted ? 0.45 : 1
                            from: 0; to: level.isMic ? 150 : 100; step: 1
                            neutral: level.isMic ? 100 : NaN
                            value: level.isMic ? Audio.micVolume : Audio.volumePercent
                            // Moving the output's level unmutes it, as the wheel does; the
                            // microphone stays muted until asked.
                            onMoved: v => {
                                if (level.isMic) {
                                    Audio.setMicVolume(v)
                                } else {
                                    if (Audio.volumeMuted) Audio.setVolumeMuted(false)
                                    Audio.setVolume(v)
                                }
                            }

                            Behavior on opacity { NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            Layout.preferredWidth: 38
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(levelSlider.shown) + "%"
                            color: level.muted ? Theme.textMuted : Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            font.features: Theme.tabular
                        }
                    }
                }

                // Where it plays.
                Column {
                    width: parent.width
                    spacing: 4
                    visible: Audio.audioSinks.length > 1

                    PanelLabel { text: "Output" }

                    Repeater {
                        model: Audio.audioSinks

                        Rectangle {
                            id: sinkRow
                            required property var modelData
                            width: parent.width
                            height: 36
                            radius: Theme.radiusMedium
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
                                    font.family: Theme.fontText
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
                                onTapped: Audio.setDefaultSink(sinkRow.modelData.id)
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
                        visible: Audio.audioStreams.length === 0
                        text: "Nothing is playing"
                    }

                    Repeater {
                        model: Audio.audioStreams

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
                                    source: Audio.resolveAppIcon(streamRow.modelData.icons)
                                }

                                Text {
                                    text: Audio.streamName(streamRow.modelData.name)
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: Theme.fontText
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: Math.round(streamSlider.shown) + "%"
                                    color: Theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: Theme.fontText
                                    font.features: Theme.tabular
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
                                onDraggingChanged: Audio.audioStreamsDragging = streamSlider.dragging
                                onMoved: v => Audio.setStreamVolumeThrottled(streamRow.modelData.id, v)
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
