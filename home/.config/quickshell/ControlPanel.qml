import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

PanelWindow {
    id: settingsItem
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

    // Anchor of the right-hand pill row; the others park off this one.
    property int rightMargin: AppState.gapRight - 12
    margins.right: rightMargin

    property bool panelOpen: false

    function runPowerAction(action) {
        settingsItem.panelOpen = false
        // Both go through AppState so the button gets the same fade the
        // Super+L bind does; see lockSession() there.
        if (action === "lock") AppState.lockSession()
        else if (action === "suspend") AppState.suspendSession()
        else if (action === "reboot") rebootProc.running = true
        else if (action === "shutdown") shutdownProc.running = true
    }

    implicitWidth: panelOpen ? 372 : settingsText.implicitWidth + 64

    // Content-driven rather than a fixed 664; chrome is the 12px inset plus
    // the flickable's 16px margins.
    implicitHeight: panelOpen ? Math.min(panelColumn.implicitHeight + 56, 700) : 64

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
        id: panelGlass
        anchors.fill: parent
        radius: settingsItem.panelOpen ? 26 : 20
        color: Theme.glass
        visible: false
        layer.enabled: true

        Behavior on radius {
            NumberAnimation { duration: 200 }
        }
    }

    MultiEffect {
        source: panelGlass
        anchors.fill: panelGlass
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.5
        shadowBlur: 0.7
        shadowVerticalOffset: 4
        autoPaddingEnabled: true
    }

    IconGlyph {
        id: settingsText
        anchors.centerIn: parent
        visible: !settingsItem.panelOpen
        opacity: !settingsItem.panelOpen ? 1 : 0
        text: "󰢻"
        color: Theme.textPrimary
        size: Theme.iconLarge

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
    }

    TapHandler {
        enabled: !settingsItem.panelOpen
        onTapped: {
            settingsItem.panelOpen = true
            AppState.refreshWallpaperList()
        }
    }

    HyprlandFocusGrab {
        id: controlPanelGrab
        windows: [settingsItem]
        active: settingsItem.panelOpen
        onCleared: settingsItem.panelOpen = false
    }

                                    // Collapsed, this used to keep drawing: the
                                    // panel shrinks to the 64px button, and the
                                    // Wi-Fi tile -- a light accent fill -- stayed
                                    // clipped to a sliver at the centre, reading
                                    // as a white line struck through the gear.
                                    Flickable {
                                        visible: settingsItem.panelOpen
                                        opacity: settingsItem.panelOpen ? 1 : 0
                                        anchors.fill: parent
                                        anchors.margins: 16
                                        contentHeight: panelColumn.height
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        Behavior on opacity {
                                            NumberAnimation { duration: 200 }
                                        }

                                        Column {
                                            id: panelColumn
                                            width: parent.width
                                            spacing: 14

                                            Text {
                                                text: "Control panel"
                                                color: Theme.textPrimary
                                                font.pixelSize: 16
                                                font.bold: true
                                                font.family: Theme.fontMono
                                            }

                                            GridLayout {
                                                width: parent.width
                                                columns: 2
                                                columnSpacing: 8
                                                rowSpacing: 8

                                                ToggleTile {
                                                    Layout.fillWidth: true
                                                    icon: "󰤨"
                                                    label: "Wi-Fi"
                                                    active: AppState.wifiRadioEnabled
                                                    detail: !AppState.wifiRadioEnabled ? "Off"
                                                          : AppState.wifiSsid.length > 0 ? AppState.wifiSsid
                                                          : "Not connected"
                                                    onTapped: AppState.toggleWifiRadio()
                                                }

                                                ToggleTile {
                                                    Layout.fillWidth: true
                                                    icon: "󰂯"
                                                    label: "Bluetooth"
                                                    active: AppState.btEnabled
                                                    detail: !AppState.btEnabled ? "Off"
                                                          : AppState.btConnectedCount === 0 ? "No devices"
                                                          : AppState.btConnectedCount === 1 ? "1 connected"
                                                          : AppState.btConnectedCount + " connected"
                                                    onTapped: AppState.toggleBluetoothPower()
                                                }

                                                ToggleTile {
                                                    Layout.fillWidth: true
                                                    icon: AppState.micMuted ? "󰍭" : "󰍬"
                                                    label: "Microphone"
                                                    active: !AppState.micMuted
                                                    detail: AppState.micMuted ? "Muted" : "Live"
                                                    onTapped: AppState.toggleMicMute()
                                                }

                                                ToggleTile {
                                                    Layout.fillWidth: true
                                                    icon: "󰂛"
                                                    label: "Do not disturb"
                                                    active: AppState.dndEnabled
                                                    detail: AppState.dndEnabled ? "Silenced" : "Showing"
                                                    onTapped: AppState.toggleDnd()
                                                }

                                                // Full width on its own row: it
                                                // is the fifth of four paired
                                                // tiles, and a half-width one
                                                // beside a gap reads as a tile
                                                // that failed to load.
                                                ToggleTile {
                                                    Layout.fillWidth: true
                                                    Layout.columnSpan: 2
                                                    icon: AppState.gamepadConnected ? "󰊴" : "󰺵"
                                                    label: "Controller"
                                                    active: AppState.gamepadModeActive
                                                    detail: AppState.gamepadMode === "stopped" ? "Service off"
                                                          : !AppState.gamepadConnected ? "Not connected"
                                                          : AppState.gamepadModeActive ? "Driving the desktop"
                                                          : "Gamepad only"
                                                    onTapped: AppState.toggleGamepadMode()
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
                                                    text: "Wallpaper"
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 13
                                                    font.family: Theme.fontMono
                                                }

                                                Text {
                                                    visible: AppState.wallpaperFiles.length === 0
                                                    text: "No images in ~/Pictures/Wallpapers"
                                                    color: Theme.textMuted
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontMono
                                                }

                                                // Opens the picker instead of being one: the strip
                                                // that used to sit here drew every wallpaper at
                                                // 56x40, too small to tell two photos apart.
                                                Rectangle {
                                                    visible: AppState.wallpaperFiles.length > 0
                                                    width: parent.width
                                                    height: 56
                                                    radius: 12
                                                    color: Theme.surfaceContainer

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 12
                                                        spacing: 10

                                                        Item {
                                                            Layout.preferredWidth: 64
                                                            Layout.preferredHeight: 40

                                                            Rectangle {
                                                                id: currentThumbMask
                                                                anchors.fill: parent
                                                                radius: 8
                                                                color: Theme.surfaceContainerHigh
                                                                visible: false
                                                                layer.enabled: true
                                                            }

                                                            Rectangle {
                                                                anchors.fill: parent
                                                                radius: currentThumbMask.radius
                                                                color: Theme.surfaceContainerHigh
                                                                visible: currentThumb.status !== Image.Ready
                                                            }

                                                            Image {
                                                                id: currentThumb
                                                                anchors.fill: parent
                                                                source: AppState.selectedWallpaper.length > 0
                                                                    ? "file://" + AppState.selectedWallpaper : ""
                                                                fillMode: Image.PreserveAspectCrop
                                                                asynchronous: true
                                                                visible: status === Image.Ready
                                                                sourceSize.width: 128
                                                                layer.enabled: true
                                                                layer.effect: MultiEffect {
                                                                    maskEnabled: true
                                                                    maskSource: currentThumbMask
                                                                }
                                                            }
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                var path = AppState.selectedWallpaper
                                                                return path.length > 0 ? path.split("/").pop() : "Choose"
                                                            }
                                                            color: Theme.textSecondary
                                                            font.pixelSize: 11
                                                            font.family: Theme.fontMono
                                                            elide: Text.ElideMiddle
                                                        }

                                                        IconGlyph {
                                                            text: "󰅂"
                                                            color: Theme.textMuted
                                                            size: Theme.iconSmall
                                                        }
                                                    }

                                                    StateLayer {
                                                        onTapped: {
                                                            settingsItem.panelOpen = false
                                                            AppState.wallpapersOpen = true
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
                                                spacing: 10

                                                Text {
                                                    text: "System resources"
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 13
                                                    font.family: Theme.fontMono
                                                }

                                                GridLayout {
                                                    width: parent.width
                                                    columns: 3
                                                    columnSpacing: 8
                                                    rowSpacing: 8

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 64
                                                        radius: 14
                                                        color: Theme.surfaceContainer

                                                        Column {
                                                            anchors.fill: parent
                                                            anchors.margins: 10
                                                            spacing: 6

                                                            Text {
                                                                text: "CPU"
                                                                color: Theme.textSecondary
                                                                font.pixelSize: 10
                                                                font.family: Theme.fontMono
                                                            }

                                                            Text {
                                                                text: Math.round(AppState.cpuPercent) + "%"
                                                                color: Theme.textPrimary
                                                                font.pixelSize: 16
                                                                font.bold: true
                                                                font.family: Theme.fontMono
                                                            }

                                                            Rectangle {
                                                                width: parent.width
                                                                height: 4
                                                                radius: 2
                                                                color: Theme.track

                                                                Rectangle {
                                                                    width: parent.width * (AppState.cpuPercent / 100)
                                                                    height: parent.height
                                                                    radius: 2
                                                                    color: AppState.themeAccent
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 64
                                                        radius: 14
                                                        color: Theme.surfaceContainer

                                                        Column {
                                                            anchors.fill: parent
                                                            anchors.margins: 10
                                                            spacing: 6

                                                            Text {
                                                                text: "RAM"
                                                                color: Theme.textSecondary
                                                                font.pixelSize: 10
                                                                font.family: Theme.fontMono
                                                            }

                                                            Text {
                                                                text: Math.round(AppState.ramPercent) + "%"
                                                                color: Theme.textPrimary
                                                                font.pixelSize: 16
                                                                font.bold: true
                                                                font.family: Theme.fontMono
                                                            }

                                                            Rectangle {
                                                                width: parent.width
                                                                height: 4
                                                                radius: 2
                                                                color: Theme.track

                                                                Rectangle {
                                                                    width: parent.width * (AppState.ramPercent / 100)
                                                                    height: parent.height
                                                                    radius: 2
                                                                    color: AppState.themeAccent
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 64
                                                        radius: 14
                                                        color: Theme.surfaceContainer

                                                        Column {
                                                            anchors.fill: parent
                                                            anchors.margins: 10
                                                            spacing: 6

                                                            Text {
                                                                text: "Disk"
                                                                color: Theme.textSecondary
                                                                font.pixelSize: 10
                                                                font.family: Theme.fontMono
                                                            }

                                                            Text {
                                                                text: Math.round(AppState.diskPercent) + "%"
                                                                color: Theme.textPrimary
                                                                font.pixelSize: 16
                                                                font.bold: true
                                                                font.family: Theme.fontMono
                                                            }

                                                            Rectangle {
                                                                width: parent.width
                                                                height: 4
                                                                radius: 2
                                                                color: Theme.track

                                                                Rectangle {
                                                                    width: parent.width * (AppState.diskPercent / 100)
                                                                    height: parent.height
                                                                    radius: 2
                                                                    color: AppState.themeAccent
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                RowLayout {
                                                    width: parent.width

                                                    IconGlyph {
                                                        text: "󰔏"
                                                        color: Theme.textPrimary
                                                        size: Theme.iconSmall
                                                    }

                                                    Text {
                                                        text: "Temperature"
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 13
                                                        font.family: Theme.fontMono
                                                        Layout.fillWidth: true
                                                        Layout.leftMargin: 4
                                                    }

                                                    Text {
                                                        text: Math.round(AppState.tempCelsius) + "°C"
                                                        color: AppState.tempCelsius >= 80 ? Theme.error : Theme.textSecondary
                                                        font.pixelSize: 12
                                                        font.family: Theme.fontMono
                                                    }
                                                }

                                                Rectangle {
                                                    width: parent.width
                                                    height: 5
                                                    radius: 3
                                                    color: Theme.track

                                                    Rectangle {
                                                        width: parent.width * Math.min(AppState.tempCelsius / 100, 1)
                                                        height: parent.height
                                                        radius: 3
                                                        color: AppState.tempCelsius >= 80 ? Theme.error : AppState.themeAccent
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Theme.outline
                                            }

                                            // Opens the overlay rather than
                                            // unfolding here: thirty-odd rows
                                            // in a 372px column is a scroll
                                            // with no end, and the same list
                                            // reads in two columns full-screen.
                                            Rectangle {
                                                id: bindsButton
                                                width: parent.width
                                                height: 46
                                                radius: 14
                                                color: bindsState.hovered ? Theme.surfaceContainerHigh
                                                                          : Theme.surfaceContainer

                                                Behavior on color { ColorAnimation { duration: Theme.durShort } }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 14
                                                    anchors.rightMargin: 14
                                                    spacing: 10

                                                    IconGlyph {
                                                        text: "󰌌"
                                                        color: Theme.textPrimary
                                                        size: Theme.iconMedium
                                                    }

                                                    Column {
                                                        Layout.fillWidth: true
                                                        spacing: 1

                                                        Text {
                                                            text: "Keyboard shortcuts"
                                                            color: Theme.textPrimary
                                                            font.pixelSize: 13
                                                            font.family: Theme.fontMono
                                                        }

                                                        Text {
                                                            text: AppState.hyprBindsError.length > 0
                                                                  ? "Config unread"
                                                                  : AppState.hyprBindCount + " in Hyprland"
                                                            color: AppState.hyprBindsError.length > 0 ? Theme.error
                                                                                                      : Theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontMono
                                                        }
                                                    }

                                                    // Read back out of the config rather than
                                                    // written in here, so it still tells the
                                                    // truth after the bind is moved.
                                                    Rectangle {
                                                        visible: AppState.hyprOverlayKeys.length > 0
                                                        Layout.preferredWidth: overlayKeyLabel.implicitWidth + 12
                                                        Layout.preferredHeight: overlayKeyLabel.implicitHeight + 6
                                                        radius: 6
                                                        color: Theme.alpha(Theme.foreground, 0.10)

                                                        Text {
                                                            id: overlayKeyLabel
                                                            anchors.centerIn: parent
                                                            text: AppState.hyprOverlayKeys
                                                            color: Theme.textSecondary
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontMono
                                                        }
                                                    }
                                                }

                                                StateLayer {
                                                    id: bindsState
                                                    onTapped: {
                                                        settingsItem.panelOpen = false
                                                        AppState.keybindsOpen = true
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Theme.outline
                                            }

                                            RowLayout {
                                                id: powerRow
                                                width: parent.width
                                                spacing: 8

                                                // Reboot and shutdown need a second tap to fire, so a
                                                // stray click in the panel cannot kill the session.
                                                property string armed: ""

                                                Timer {
                                                    id: disarmTimer
                                                    interval: 3000
                                                    onTriggered: powerRow.armed = ""
                                                }

                                                Repeater {
                                                    model: [
                                                        { action: "lock",     icon: "󰌾", label: "Lock",  danger: false },
                                                        { action: "suspend",  icon: "󰖔", label: "Suspend", danger: false },
                                                        { action: "reboot",   icon: "󰜉", label: "Restart", danger: true },
                                                        { action: "shutdown", icon: "󰐥", label: "Shut down",    danger: true }
                                                    ]

                                                    Rectangle {
                                                        id: powerButton
                                                        required property var modelData

                                                        readonly property bool isArmed: powerRow.armed === modelData.action
                                                        readonly property bool danger: modelData.danger

                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 60
                                                        radius: 16

                                                        // Reboot and shutdown carry a red cast before they are
                                                        // touched, not only once armed: the warning is worth more
                                                        // ahead of the first tap than after it.
                                                        color: isArmed ? Theme.alpha(Theme.error, 0.24)
                                                             : danger ? Theme.alpha(Theme.error, powerState.hovered ? 0.18 : 0.09)
                                                             : powerState.hovered ? Theme.surfaceContainerHigh
                                                             : Theme.alpha(Theme.foreground, 0.05)

                                                        scale: powerState.pressed ? 0.95 : 1.0
                                                        transformOrigin: Item.Center

                                                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                        Behavior on scale {
                                                            NumberAnimation { duration: Theme.durShort; easing.type: Easing.OutQuad }
                                                        }

                                                        Column {
                                                            anchors.centerIn: parent
                                                            spacing: 3

                                                            IconGlyph {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                text: powerButton.modelData.icon
                                                                color: powerButton.isArmed ? Theme.error
                                                                     : powerButton.danger ? Theme.alpha(Theme.error, 0.9)
                                                                     : Theme.textPrimary
                                                                size: Theme.iconLarge

                                                                Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                            }

                                                            Text {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                text: powerButton.isArmed ? "Sure?" : powerButton.modelData.label
                                                                color: powerButton.isArmed ? Theme.error
                                                                     : powerButton.danger ? Theme.textSecondary
                                                                     : Theme.textMuted
                                                                font.pixelSize: 10
                                                                font.family: Theme.fontMono

                                                                Behavior on color { ColorAnimation { duration: Theme.durShort } }
                                                            }
                                                        }

                                                        StateLayer {
                                                            id: powerState
                                                            onTapped: {
                                                                if (powerButton.modelData.danger && !powerButton.isArmed) {
                                                                    powerRow.armed = powerButton.modelData.action
                                                                    disarmTimer.restart()
                                                                    return
                                                                }
                                                                powerRow.armed = ""
                                                                settingsItem.runPowerAction(powerButton.modelData.action)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                        Process {
                            id: rebootProc
                            running: false
                            command: ["bash", "-lc", "systemctl reboot"]
                        }

                        Process {
                            id: shutdownProc
                            running: false
                            command: ["bash", "-lc", "systemctl poweroff"]
                        }
}
}
