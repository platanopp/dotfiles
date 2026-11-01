import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services
import qs.settings

PanelWindow {
    id: settingsItem
    property var bar: null
    screen: bar.screen
    visible: true

    // Hidden by cutting input and drawing nothing, never by unmapping: a remapped layer is
    // restacked above the pills and swallowed their clicks. The blur rule ignores pixels
    // under 0.3 alpha, so nothing shows.
    mask: bar.barHidden ? blankMask : stageMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Input only where the pill is; the window also holds the room the panel and
    // Settings grow into (PillStage).
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
    // Never the keyboard: asking for it while open ends the Hyprland focus grab and shuts the
    // panel, and holding it always would take the keyboard on every bar click. Back, close
    // and click-outside do the job instead.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        right: true
    }
    // The content insets by 12, so the window sits back that much and the
    // drawn edge lands on Hyprland's gap.
    margins.top: Math.max(0, Hypr.gapTop - 12)

    // Anchor of the right-hand pill row; the others park off this one.
    property int rightMargin: Hypr.gapRight - 12
    margins.right: rightMargin

    property bool panelOpen: false

    // Escape closes it (Panels.dismissPanels, bound while any panel is up).
    readonly property bool escapeOpen: settingsItem.panelOpen || settingsItem.notifOpen
    readonly property string escapeKey: "control:" + (settingsItem.screen ? settingsItem.screen.name : "")
    onEscapeOpenChanged: Panels.setPanelOpen(settingsItem.escapeKey, settingsItem.escapeOpen)
    Component.onDestruction: if (settingsItem.escapeOpen) Panels.setPanelOpen(settingsItem.escapeKey, false)

    Connections {
        target: Panels
        function onDismissRequested() { settingsItem.panelOpen = false; settingsItem.notifOpen = false }
    }
    // The notification centre, the pill's other face: the bell opens it
    // in the same glass. Never both.
    property bool notifOpen: false

    onNotifOpenChanged: {
        Notifications.centreOpen = notifOpen
        if (notifOpen) {
            panelOpen = false
            Notifications.markRead()
        }
    }

    // Settings: the panel grows into the Settings window in the same glass. Back returns
    // to the panel; closing closes both.
    property bool settingsOpen: false
    property string settingsPage: "displays"

    onPanelOpenChanged: {
        if (!panelOpen) settingsOpen = false
        else notifOpen = false
    }

    // qs ipc call notifications toggle (see Panels): only the pill on the screen
    // that asked answers, except to close.
    Connections {
        target: Panels
        function onNotificationsRequested(how, screenName) {
            if (how === "close") { settingsItem.notifOpen = false; return }
            if (settingsItem.screen && screenName.length > 0 && settingsItem.screen.name !== screenName) return
            settingsItem.notifOpen = how === "open" ? true : !settingsItem.notifOpen
        }
    }

    // The bar's panels link to their page here (Panels.openSettings); only
    // the screen that asked answers.
    Connections {
        target: Panels
        // An empty page toggles: closes Settings if open here, else opens it at the last page.
        function onSettingsRequested(page, screenName) {
            if (settingsItem.screen && screenName.length > 0 && settingsItem.screen.name !== screenName) return
            if (page.length === 0 && settingsItem.settingsOpen) {
                settingsItem.panelOpen = false
                return
            }
            if (page.length > 0) settingsItem.settingsPage = page
            settingsItem.panelOpen = true
            settingsItem.settingsOpen = true
        }
    }
    onSettingsOpenChanged: {
        if (!settingsOpen) return
        Display.refreshDisplay()
        Power.refreshIdle()
        Power.refreshPowerProfiles()
    }

    // Never wide enough to reach the clock, which is drawn above this window: shorter on the 1920px
    // Samsung, the full 1000 on the 2560px Xiaomi.
    readonly property int settingsWidth: Math.min(1000, Math.round(settingsItem.screen.width / 2 - 170))
    readonly property int settingsHeight: Math.min(720, settingsItem.screen.height - 110)

    // What the pills to the left park off (pillLeftOf in shell.qml), capped at the panel's width so
    // the tray and status pill hold still under Settings instead of being flung and sliding back.
    readonly property real rowWidth: Math.min(stage.width, 372)

    // Small heading over a group of controls.
    component SectionLabel: Text {
        color: Theme.textSecondary
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.family: Theme.fontText
    }

    function runPowerAction(action) {
        settingsItem.panelOpen = false
        // Both go through Power, so the button gets the same fade as Super+L (lockSession()).
        if (action === "lock") Power.lockSession()
        else if (action === "suspend") Power.suspendSession()
        else if (action === "reboot") rebootProc.running = true
        else if (action === "shutdown") shutdownProc.running = true
    }

    // The pill's box, animated inside a window that is not (see PillStage).
    PillStage {
        id: stage
        collapsed: bar.barHidden
        anchors.top: parent.top
        anchors.right: parent.right
        // Sized for Settings from the start and never resized: a right-anchored window that grows
        // moves its left edge, and for a frame the old buffer showed there.
        minWindowWidth: settingsItem.settingsWidth
        minWindowHeight: Math.max(settingsItem.settingsHeight, settingsItem.screen.height - 48)
        // The spring's room on top of that would run off the screen.
        maxWindowHeight: settingsItem.screen.height
        targetWidth: settingsItem.settingsOpen ? settingsItem.settingsWidth
                   : settingsItem.panelOpen || settingsItem.notifOpen ? 372
                   : compactRow.implicitWidth + 24 + Theme.pillPaddingH * 2
        targetHeight: settingsItem.settingsOpen ? settingsItem.settingsHeight
            : settingsItem.panelOpen ? Math.min(panelColumn.implicitHeight + 56,
                                                settingsItem.screen.height - 48)
            : settingsItem.notifOpen ? Math.min(notifCentre.wantedHeight + 56,
                                                settingsItem.screen.height - 48)
            : 64
    }

    implicitWidth: stage.windowWidth
    implicitHeight: stage.windowHeight

    // targetHeight above is content-driven; chrome is the 12px inset plus the flickable's
    // 16px margins. Capped to the screen (48 = the 8px hang plus a bottom margin); the
    // flickable scrolls anything taller.

    Item {
        id: contentArea
        visible: !bar.barHidden
        anchors.fill: stage
        anchors.margins: 12
        // Settings is laid out at full size from the first frame and uncovered as
        // the glass grows, so clip it here.
        clip: settingsItem.settingsOpen || settingsLoader.visible

    Rectangle {
        id: panelGlass
        anchors.fill: parent
        radius: settingsItem.settingsOpen ? 28 : settingsItem.panelOpen || settingsItem.notifOpen ? 26 : 20
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
        shadowColor: Theme.shadow
        shadowOpacity: 0.5
        shadowBlur: 0.7
        shadowVerticalOffset: 4
        autoPaddingEnabled: true
    }

    // The pill, closed: the bell for the notification centre and the CachyOS logo for
    // the panel, two buttons in one glass.
    Row {
        id: compactRow
        anchors.centerIn: parent
        spacing: 4
        visible: opacity > 0
        opacity: !settingsItem.panelOpen && !settingsItem.notifOpen ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }

        // Recording: the count of three, then a red dot and the time, so it's never
        // forgotten. A click cancels or stops.
        Item {
            id: recIndicator
            readonly property bool counting: Recorder.recordCountdown > 0 && !Recorder.recording
            visible: Recorder.recording || recIndicator.counting
            width: recRow.implicitWidth + 16
            height: 30

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Theme.error
                opacity: recArea.pressed ? 0.32 : recArea.containsMouse ? 0.24 : 0.16

                Behavior on opacity { NumberAnimation { duration: Theme.durShort } }
            }

            Row {
                id: recRow
                anchors.centerIn: parent
                spacing: 6

                // Hollow while counting, filled once recording. Steady: the
                // timer beside it already moves.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: recIndicator.counting ? "transparent" : Theme.error
                    border.width: recIndicator.counting ? 1.5 : 0
                    border.color: Theme.error
                }

                Text {
                    id: recText
                    anchors.verticalCenter: parent.verticalCenter
                    text: recIndicator.counting ? String(Recorder.recordCountdown)
                                                : Recorder.recordingClock(Recorder.recordingSeconds)
                    color: Theme.textPrimary
                    font.pixelSize: 12
                    font.bold: recIndicator.counting
                    font.family: Theme.fontText
                    font.features: Theme.tabular

                    // Each number of the count drops in.
                    onTextChanged: if (recIndicator.counting) countDrop.restart()

                    ParallelAnimation {
                        id: countDrop
                        NumberAnimation { target: recText; property: "scale"; from: 1.6; to: 1; duration: 360; easing.type: Easing.OutBack }
                        NumberAnimation { target: recText; property: "opacity"; from: 0; to: 1; duration: 180 }
                    }
                }
            }

            MouseArea {
                id: recArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Recorder.toggleRecording("")
            }
        }

        Repeater {
            model: [
                { key: "notifications" },
                { key: "panel" }
            ]

            Item {
                id: compactButton
                required property var modelData
                readonly property bool bell: compactButton.modelData.key === "notifications"
                width: 30
                height: 30

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.foreground
                    opacity: compactTap.pressed ? 0.16 : compactHover.hovered ? 0.09 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.durShort }
                    }
                }

                IconGlyph {
                    anchors.centerIn: parent
                    // The CachyOS logo (Nerd Font linux-cachyos) rather than a gear: the
                    // panel is the way into the whole machine. The bell is struck
                    // through under do not disturb.
                    text: !compactButton.bell ? "\u{F385}"
                        : Notifications.dnd ? "\u{F009B}"
                        : Notifications.unread > 0 ? "\u{F009E}" : "\u{F009C}"
                    color: compactButton.bell && Notifications.dnd ? Theme.textMuted : Theme.textPrimary
                    size: Theme.iconLarge
                }

                // Unread, as a dot on the bell's shoulder.
                Rectangle {
                    visible: compactButton.bell && Notifications.unread > 0
                    width: 8
                    height: 8
                    radius: 4
                    x: parent.width - width - 4
                    y: 4
                    color: Theme.accent
                    border.width: 1.5
                    border.color: Theme.glass
                }

                HoverHandler {
                    id: compactHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: compactTap
                    enabled: !settingsItem.panelOpen && !settingsItem.notifOpen
                    onTapped: {
                        if (compactButton.bell) {
                            settingsItem.notifOpen = true
                            return
                        }
                        settingsItem.panelOpen = true
                        Wallpaper.refreshWallpaperList()
                    }
                }
            }
        }
    }

    // The notification centre
    NotificationCentre {
        id: notifCentre
        anchors.fill: parent
        anchors.margins: 16
        visible: opacity > 0
        opacity: settingsItem.notifOpen ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }
    }

    HyprlandFocusGrab {
        id: controlPanelGrab
        windows: [settingsItem]
        active: settingsItem.panelOpen || settingsItem.notifOpen
        onCleared: {
            settingsItem.panelOpen = false
            settingsItem.notifOpen = false
        }
    }

    // Host and uptime for the header, read on open and once a minute while open.
    property string hostName: ""
    property int uptimeSecs: 0

    Process {
        id: sysInfoProc
        running: false
        command: ["sh", "-c", "cat /proc/uptime; cat /etc/hostname 2>/dev/null || uname -n"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n")
                contentArea.uptimeSecs = Math.floor(parseFloat(lines[0]) || 0)
                if (lines.length > 1) contentArea.hostName = lines[1].trim()
            }
        }
    }

    Timer {
        running: settingsItem.panelOpen
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: sysInfoProc.running = true
    }

    function uptimeText(s) {
        var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        if (d > 0) return "up " + d + "d " + h + "h"
        if (h > 0) return "up " + h + "h " + m + "m"
        return "up " + m + "m"
    }

    Loader {
        id: settingsLoader
        anchors.top: parent.top
        anchors.right: parent.right
        width: settingsItem.settingsWidth - 24
        height: settingsItem.settingsHeight - 24
        active: settingsItem.settingsOpen || settingsFade.running
        opacity: settingsItem.settingsOpen ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { id: settingsFade; duration: 260; easing.type: Easing.OutCubic }
        }

        sourceComponent: SettingsView {
            page: settingsItem.settingsPage
            hostName: contentArea.hostName
            onPageChanged: settingsItem.settingsPage = page
            onBackRequested: settingsItem.settingsOpen = false
            onCloseRequested: settingsItem.panelOpen = false
        }
    }

    // Not drawn while collapsed: an accent fill stayed clipped to a sliver,
    // a white line through the icon.
    Flickable {
        visible: settingsItem.panelOpen && opacity > 0
        opacity: settingsItem.panelOpen && !settingsItem.settingsOpen ? 1 : 0
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
            spacing: 16

            // Header: who, where and how long. The power buttons' armed state lives here, since its
            // second line asks for the confirming tap.
            RowLayout {
                id: powerRow
                width: parent.width
                spacing: 8

                // Restart and shut down need a second tap; while one waits, the
                // line under the name says so.
                property string armed: ""
                readonly property var actions: [
                    { action: "lock",     icon: "\u{F033E}", label: "Lock",      danger: false },
                    { action: "suspend",  icon: "\u{F0594}", label: "Suspend",   danger: false },
                    { action: "reboot",   icon: "\u{F0709}", label: "Restart",   danger: true },
                    { action: "shutdown", icon: "\u{F0425}", label: "Shut down", danger: true }
                ]

                Timer {
                    id: disarmTimer
                    interval: 3000
                    onTriggered: powerRow.armed = ""
                }

                // The user's picture (Profile.avatarPath) or their initial.
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
                            id: avatarImage
                            anchors.fill: parent
                            source: Profile.avatarSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize.width: 128
                            visible: status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: avatarImage.status !== Image.Ready
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
                        // Host on the line below: user@host beside four buttons was cut off.
                        text: Profile.username
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.bold: true
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            for (var i = 0; i < powerRow.actions.length; i++)
                                if (powerRow.actions[i].action === powerRow.armed)
                                    return "Tap again to " + powerRow.actions[i].label.toLowerCase()
                            var up = contentArea.uptimeText(contentArea.uptimeSecs)
                            return contentArea.hostName.length > 0 ? contentArea.hostName + " · " + up : up
                        }
                        color: powerRow.armed !== "" ? Theme.error : Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: System.distro
                        color: Theme.textMuted
                        opacity: 0.7
                        font.pixelSize: 10
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }
                }

            }

            // Quick toggles
            GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F05A9}"
                    label: "Wi-Fi"
                    active: Network.wifiRadioEnabled
                    detail: !Network.wifiRadioEnabled ? "Off"
                          : Network.wifiSsid.length > 0 ? Network.wifiSsid
                          : "Not connected"
                    onTapped: Network.toggleWifiRadio()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F00AF}"
                    label: "Bluetooth"
                    active: Bluetooth.btEnabled
                    detail: !Bluetooth.btEnabled ? "Off"
                          : Bluetooth.btConnectedCount === 0 ? "No devices"
                          : Bluetooth.btConnectedCount === 1 ? "1 connected"
                          : Bluetooth.btConnectedCount + " connected"
                    onTapped: Bluetooth.toggleBluetoothPower()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: Audio.micMuted ? "\u{F036D}" : "\u{F036C}"
                    label: "Microphone"
                    active: !Audio.micMuted
                    detail: Audio.micMuted ? "Muted" : "Live"
                    onTapped: Audio.toggleMicMute()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F009B}"
                    label: "Do not disturb"
                    active: Notifications.dnd
                    detail: Notifications.dnd ? "Silenced" : "Showing"
                    onTapped: Notifications.toggleDnd()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: Recorder.recording ? "\u{F04DB}" : "\u{F044B}"
                    label: Recorder.recording ? "Recording" : "Record"
                    active: Recorder.recording
                    detail: Recorder.recording
                            ? Recorder.recordingClock(Recorder.recordingSeconds) + "  ·  tap to stop"
                            : Recorder.recordCountdown > 0 ? "Starting in " + Recorder.recordCountdown
                            : (ShellSettings.recordResolution === "native" ? "Native" : ShellSettings.recordResolution + "p")
                              + "  ·  " + ShellSettings.recordFps + " fps"
                    onTapped: {
                        if (Recorder.recording) {
                            Recorder.stopRecording()
                            return
                        }
                        // Close the panel first so the recording doesn't start on it; the
                        // countdown follows on this screen.
                        settingsItem.panelOpen = false
                        Recorder.countdownRecording(settingsItem.screen ? settingsItem.screen.name : "")
                    }
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F0DCB}"
                    label: "Tablet"
                    active: Tablet.otdRunning
                    // Switching it off leaves the pen dead: a udev rule hides the kernel's
                    // own device from the compositor.
                    detail: Tablet.otdRunning ? "Driver on" : "No pen"
                    onTapped: Tablet.toggleOtd()
                }
            }

            // Wallpaper: the picture as the desktop shows it (framed crop or
            // video poster); opens the picker.
            Rectangle {
                id: wallpaperCard
                width: parent.width
                height: 96
                radius: Theme.radiusLarge
                color: Theme.surfaceContainer

                readonly property bool isVideo: Wallpaper.activeVideoWallpaper !== ""
                readonly property string name: {
                    var p = wallpaperCard.isVideo ? Wallpaper.activeVideoWallpaper
                                                  : Wallpaper.selectedWallpaper
                    return p.length > 0 ? p.split("/").pop().replace(/\.[^.]+$/, "") : "Choose a wallpaper"
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: wallpaperCard.radius
                    color: "transparent"

                    Image {
                        anchors.fill: parent
                        source: Wallpaper.wallpaperStill.length > 0 ? "file://" + Wallpaper.wallpaperStill : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 640
                    }

                    // Keeps the caption readable over any picture.
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.alpha(Theme.background, 0.82) }
                            GradientStop { position: 0.7; color: Theme.alpha(Theme.background, 0.05) }
                        }
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.bottomMargin: 12
                    width: parent.width - 110
                    spacing: 2

                    Text {
                        text: wallpaperCard.isVideo ? "Wallpaper · video" : "Wallpaper"
                        color: Theme.textSecondary
                        font.weight: Font.DemiBold
                        font.pixelSize: 11
                        font.family: Theme.fontText
                    }

                    Text {
                        width: parent.width
                        text: wallpaperCard.name
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    width: changeRow.implicitWidth + 20
                    height: 26
                    radius: height / 2
                    color: Theme.alpha(Theme.background, 0.7)

                    Row {
                        id: changeRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Change"
                            color: Theme.textPrimary
                            font.pixelSize: 10
                            font.family: Theme.fontText
                        }

                        IconGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{F0142}"
                            color: Theme.textPrimary
                            size: Theme.iconTiny
                        }
                    }
                }

                StateLayer {
                    radius: wallpaperCard.radius
                    onTapped: {
                        settingsItem.panelOpen = false
                        Panels.wallpapersOpen = true
                    }
                }
            }

            // Power mode: one of three, as a segmented control.
            Column {
                width: parent.width
                spacing: 8
                visible: Power.powerProfiles.length > 0

                SectionLabel { text: "Power mode" }

                Rectangle {
                    id: modeSwitch
                    width: parent.width
                    height: 42
                    radius: height / 2
                    color: Theme.surfaceContainer

                    readonly property int count: Power.powerProfiles.length
                    readonly property real segment: (width - 8) / Math.max(1, count)
                    readonly property int activeIndex: {
                        for (var i = 0; i < Power.powerProfiles.length; i++)
                            if (Power.powerProfiles[i].active) return i
                        return -1
                    }

                    // The fill slides to the chosen mode instead of blinking.
                    Rectangle {
                        visible: modeSwitch.activeIndex >= 0
                        x: 4 + modeSwitch.segment * Math.max(0, modeSwitch.activeIndex)
                        y: 4
                        width: modeSwitch.segment
                        height: modeSwitch.height - 8
                        radius: height / 2
                        color: Theme.accent

                        Behavior on x {
                            Elastic { small: true }
                        }
                    }

                    Row {
                        x: 4
                        y: 4

                        Repeater {
                            model: Power.powerProfiles

                            Item {
                                id: mode
                                required property var modelData
                                width: modeSwitch.segment
                                height: modeSwitch.height - 8

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    IconGlyph {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: mode.modelData.icon
                                        size: Theme.iconSmall
                                        color: mode.modelData.active ? Theme.accentText : Theme.textSecondary
                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: mode.modelData.label
                                        font.pixelSize: 11
                                        font.bold: mode.modelData.active
                                        font.family: Theme.fontText
                                        color: mode.modelData.active ? Theme.accentText : Theme.textSecondary
                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                    }
                                }

                                StateLayer {
                                    radius: height / 2
                                    interactive: !mode.modelData.active
                                    onTapped: Power.setPowerProfile(mode.modelData.name)
                                }
                            }
                        }
                    }
                }
            }

            // Elsewhere: Settings and the shortcut sheet.
            RowLayout {
                width: parent.width
                spacing: 8

                Repeater {
                    model: [
                        // No second line unless there's a problem (binds that could not be read).
                        { key: "settings", icon: "\u{F0493}", label: "Settings", detail: "" },
                        { key: "binds", icon: "\u{F030C}", label: "Shortcuts",
                          detail: Keybinds.hyprBindsError.length > 0 ? "Config unread" : "" }
                    ]

                    Rectangle {
                        id: link
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        radius: Theme.radiusLarge
                        color: Theme.surfaceContainer

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 10

                            IconGlyph {
                                text: link.modelData.icon
                                color: Theme.textSecondary
                                size: Theme.iconMedium
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: link.modelData.label
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: Theme.fontText
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: link.modelData.detail
                                    color: Theme.error
                                    font.pixelSize: 10
                                    font.family: Theme.fontText
                                    elide: Text.ElideRight
                                }
                            }

                            IconGlyph {
                                text: "\u{F0142}"
                                color: Theme.textMuted
                                size: Theme.iconTiny
                            }
                        }

                        StateLayer {
                            radius: link.radius
                            onTapped: {
                                if (link.modelData.key === "settings") {
                                    settingsItem.settingsOpen = true
                                    return
                                }
                                settingsItem.panelOpen = false
                                Panels.keybindsOpen = true
                            }
                        }
                    }
                }
            }

            // Power: full width and easy to hit. Restart and shut down are red from the
            // start and ask for a second tap.
            RowLayout {
                width: parent.width
                spacing: 8

                Repeater {
                    model: powerRow.actions

                    Rectangle {
                        id: powerButton
                        required property var modelData
                        readonly property bool isArmed: powerRow.armed === modelData.action

                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        radius: Theme.radiusLarge
                        color: powerButton.isArmed ? Theme.error
                             : modelData.danger
                                 ? Theme.alpha(Theme.error, powerState.hovered ? 0.22 : 0.1)
                             : powerState.hovered ? Theme.surfaceContainerHigh
                             : Theme.surfaceContainer
                        scale: powerState.pressed ? 0.95 : 1.0

                        Behavior on color { ColorAnimation { duration: Theme.durShort } }
                        Behavior on scale { NumberAnimation { duration: Theme.durShort } }

                        IconGlyph {
                            anchors.centerIn: parent
                            text: powerButton.modelData.icon
                            size: Theme.iconLarge
                            color: powerButton.isArmed ? Theme.background
                                 : powerButton.modelData.danger ? Theme.alpha(Theme.error, 0.95)
                                 : Theme.textPrimary
                        }

                        StateLayer {
                            id: powerState
                            radius: powerButton.radius
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
                            command: ["bash", "-c", "systemctl reboot"]
                        }

                        Process {
                            id: shutdownProc
                            running: false
                            command: ["bash", "-c", "systemctl poweroff"]
                        }
}
}
