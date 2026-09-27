import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
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
    mask: bar.barHidden ? blankMask : stageMask

    Region {
        id: blankMask
        width: 0
        height: 0
    }

    // Input only where the pill is: the window also holds the room the panel
    // and Settings grow into (see PillStage).
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
    // Never the keyboard, Settings included. Asking for it while the panel is
    // open -- so Escape could step back from Settings -- ends the Hyprland
    // focus grab below, and the panel shut the instant Settings was opened.
    // Holding it all the time would work, but then every click on the bar
    // button would take the keyboard away from the window being typed in.
    // Back, the close button and a click outside do the job instead.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        right: true
    }
    // The content inside insets itself by 12, so the window sits back by
    // that much and the drawn edge lands exactly on Hyprland's gap.
    margins.top: Math.max(0, AppState.gapTop - 12)

    // Anchor of the right-hand pill row; the others park off this one.
    property int rightMargin: AppState.gapRight - 12
    margins.right: rightMargin

    property bool panelOpen: false
    // The notification centre, the pill's other face: the bell beside the
    // logo opens it, in the same glass. One or the other, never both.
    property bool notifOpen: false

    onNotifOpenChanged: {
        Notifications.centreOpen = notifOpen
        if (notifOpen) {
            panelOpen = false
            Notifications.markRead()
        }
    }

    // ── Settings ─────────────────────────────────────────────────────────
    //
    // The panel grows into the Settings window instead of opening a second
    // one: the same glass widens and drops from the corner it already hangs
    // from, and the contents cross over. Back returns to the panel; closing
    // the panel closes both.
    property bool settingsOpen: false
    property string settingsPage: "displays"

    onPanelOpenChanged: {
        if (!panelOpen) settingsOpen = false
        else notifOpen = false
    }

    // qs ipc call notifications toggle (see AppState): only the pill on the
    // screen that asked answers, except to close.
    Connections {
        target: AppState
        function onNotificationsRequested(how, screenName) {
            if (how === "close") { settingsItem.notifOpen = false; return }
            if (settingsItem.screen && screenName.length > 0 && settingsItem.screen.name !== screenName) return
            settingsItem.notifOpen = how === "open" ? true : !settingsItem.notifOpen
        }
    }

    // The bar's own panels link to their page here (AppState.openSettings).
    // Only the panel on the screen that asked answers.
    Connections {
        target: AppState
        // An empty page toggles: closes Settings if it is open here, else
        // opens it at the page it was last left on.
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
        AppState.refreshDisplay()
        AppState.refreshIdle()
        AppState.refreshPowerProfiles()
    }

    // Wide enough for a list of pages and a page, never so wide that it
    // reaches the clock: the clock sits in the middle of the bar and is drawn
    // above this window, so on the 1920px Samsung the width stops short of
    // the centre. On the 2560px Xiaomi it gets the full thousand.
    readonly property int settingsWidth: Math.min(1000, Math.round(settingsItem.screen.width / 2 - 170))
    readonly property int settingsHeight: Math.min(720, settingsItem.screen.height - 110)

    // What the pills to the left park off (see pillLeftOf in shell.qml). With
    // Settings open it stays at the panel's width, so the tray and the status
    // pill hold still under the Settings window instead of being shoved along
    // into the clock.
    //
    // The box as drawn, capped at the panel's width: while Settings closes
    // the box is still far wider than the panel, and the row would be flung
    // left and slide back as it shrank.
    readonly property real rowWidth: Math.min(stage.width, 372)

    // Small uppercase heading over a group of controls, in place of the rules
    // and full-size titles that used to split the panel into strips.
    component SectionLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 10
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
        font.family: Theme.fontMono
    }

    function runPowerAction(action) {
        settingsItem.panelOpen = false
        // Both go through AppState so the button gets the same fade the
        // Super+L bind does; see lockSession() there.
        if (action === "lock") AppState.lockSession()
        else if (action === "suspend") AppState.suspendSession()
        else if (action === "reboot") rebootProc.running = true
        else if (action === "shutdown") shutdownProc.running = true
    }

    // The pill's box, animated inside a window that is not (see PillStage):
    // the window takes the panel's or Settings' full size at the start of
    // the move and gives it back at the end, and the glass grows in between.
    PillStage {
        id: stage
        anchors.top: parent.top
        anchors.right: parent.right
        // Sized for Settings (and the tallest the panel gets) from the start
        // and never resized: a window anchored on the right that grows moves
        // its left edge, and for a frame the compositor showed the old buffer
        // there -- the pill flicked left before growing.
        minWindowWidth: settingsItem.settingsWidth
        minWindowHeight: Math.max(settingsItem.settingsHeight, settingsItem.screen.height - 48)
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

    // On targetHeight above: content-driven rather than a fixed 664; chrome is the 12px inset plus
    // the flickable's 16px margins.
    //
    // The ceiling is what the screen can actually give, not a number picked by
    // hand. It was 700, and the panel settles at 661 of content -- 717 with
    // chrome -- so it was clipped by seventeen pixels and scrolled for them.
    // Expanding the network list or the audio devices needs far more than that
    // again.
    //
    // 48 is the 8px the panel hangs below the top edge plus a margin off the
    // bottom, so it stops short of the screen instead of running into it. The
    // flickable underneath stays: it is the fallback for content that outgrows
    // even the screen, which an expanded list on a short display still can.

    Item {
        id: contentArea
        visible: !bar.barHidden
        anchors.fill: stage
        anchors.margins: 12
        // The Settings view is laid out at its full size from the first frame
        // and uncovered as the glass grows -- clipped here so the part not yet
        // uncovered does not draw past the glass's edge.
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
        shadowColor: "#000000"
        shadowOpacity: 0.5
        shadowBlur: 0.7
        shadowVerticalOffset: 4
        autoPaddingEnabled: true
    }

    // ── The pill, closed ─────────────────────────────────────────────────
    //
    // Two ways in, side by side in the one glass: the bell for the
    // notification centre, the CachyOS logo for the panel. Each takes its
    // own taps and lights up under the pointer, so it reads as two buttons.
    Row {
        id: compactRow
        anchors.centerIn: parent
        spacing: 4
        visible: opacity > 0
        opacity: !settingsItem.panelOpen && !settingsItem.notifOpen ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 150 }
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
                    // The CachyOS logo rather than a gear: the panel is the way
                    // into the whole machine, not a settings page. Nerd Font's
                    // linux-cachyos glyph, sized and coloured like every other
                    // icon on the bar. The bell is struck through under do not
                    // disturb.
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
                        AppState.refreshWallpaperList()
                    }
                }
            }
        }
    }

    // ── The notification centre ──────────────────────────────────────────
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

    // Host and uptime for the header. Read when the panel opens and once a
    // minute while it stays open -- nothing else in the shell wants them.
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

    // Collapsed, this used to keep drawing: the panel shrinks to the 64px
    // button, and a light accent fill stayed clipped to a sliver at the
    // centre, reading as a white line struck through the icon.
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

            // ── Header ───────────────────────────────────────────────────
            //
            // Who, where and how long. The power actions are the last row of
            // the panel; their state lives here because it is this header's
            // second line that asks for the confirming tap.
            RowLayout {
                id: powerRow
                width: parent.width
                spacing: 8

                // Restart and shut down need a second tap, so a stray click
                // cannot end the session. While one is waiting, the line under
                // the name says so.
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

                // The user's picture (~/.face and friends, AppState.avatarPath),
                // or their initial when there is none.
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
                            source: AppState.avatarSource
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize.width: 128
                            visible: status === Image.Ready
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: avatarImage.status !== Image.Ready
                            text: AppState.username.length > 0 ? AppState.username.charAt(0).toUpperCase() : "?"
                            color: Theme.textPrimary
                            font.pixelSize: 18
                            font.bold: true
                            font.family: Theme.fontMono
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        // Host on the line below: user@host beside four
                        // buttons ran out of room and was cut to "gone@naruka…".
                        text: AppState.username
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.bold: true
                        font.family: Theme.fontMono
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
                        font.family: Theme.fontMono
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: AppState.distro
                        color: Theme.textMuted
                        opacity: 0.7
                        font.pixelSize: 10
                        font.family: Theme.fontMono
                        elide: Text.ElideRight
                    }
                }

            }

            // ── Quick toggles ────────────────────────────────────────────
            GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F05A9}"
                    label: "Wi-Fi"
                    active: AppState.wifiRadioEnabled
                    detail: !AppState.wifiRadioEnabled ? "Off"
                          : AppState.wifiSsid.length > 0 ? AppState.wifiSsid
                          : "Not connected"
                    onTapped: AppState.toggleWifiRadio()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F00AF}"
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
                    icon: AppState.micMuted ? "\u{F036D}" : "\u{F036C}"
                    label: "Microphone"
                    active: !AppState.micMuted
                    detail: AppState.micMuted ? "Muted" : "Live"
                    onTapped: AppState.toggleMicMute()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F009B}"
                    label: "Do not disturb"
                    active: AppState.dndEnabled
                    detail: AppState.dndEnabled ? "Silenced" : "Showing"
                    onTapped: AppState.toggleDnd()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: AppState.gamepadConnected ? "\u{F0274}" : "\u{F0EB5}"
                    label: "Controller"
                    active: AppState.gamepadModeActive
                    detail: AppState.gamepadMode === "stopped" ? "Service off"
                          : !AppState.gamepadConnected ? "Not connected"
                          : AppState.gamepadModeActive ? "Drives desktop"
                          : "Gamepad only"
                    onTapped: AppState.toggleGamepadMode()
                }

                ToggleTile {
                    Layout.fillWidth: true
                    icon: "\u{F0DCB}"
                    label: "Tablet"
                    active: AppState.otdRunning
                    // Switching it off leaves the pen dead: a udev rule has the
                    // compositor ignore the kernel's own device, so there is no
                    // fallback underneath.
                    detail: AppState.otdRunning ? "Driver on" : "No pen"
                    onTapped: AppState.toggleOtd()
                }
            }

            // ── Wallpaper ────────────────────────────────────────────────
            //
            // The picture itself, the way the desktop shows it -- the framed
            // crop, or a video's poster frame -- rather than a file name next
            // to a stamp-sized thumbnail. Opens the picker.
            Rectangle {
                id: wallpaperCard
                width: parent.width
                height: 96
                radius: 16
                color: Theme.surfaceContainer

                readonly property bool isVideo: AppState.activeVideoWallpaper !== ""
                readonly property string name: {
                    var p = wallpaperCard.isVideo ? AppState.activeVideoWallpaper
                                                  : AppState.selectedWallpaper
                    return p.length > 0 ? p.split("/").pop().replace(/\.[^.]+$/, "") : "Choose a wallpaper"
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: wallpaperCard.radius
                    color: "transparent"

                    Image {
                        anchors.fill: parent
                        source: AppState.wallpaperStill.length > 0 ? "file://" + AppState.wallpaperStill : ""
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
                        text: wallpaperCard.isVideo ? "WALLPAPER · VIDEO" : "WALLPAPER"
                        color: Theme.textSecondary
                        font.pixelSize: 9
                        font.letterSpacing: 1.2
                        font.family: Theme.fontMono
                    }

                    Text {
                        width: parent.width
                        text: wallpaperCard.name
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.bold: true
                        font.family: Theme.fontMono
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    width: changeRow.implicitWidth + 20
                    height: 26
                    radius: 13
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
                            font.family: Theme.fontMono
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
                        AppState.wallpapersOpen = true
                    }
                }
            }

            // ── Power mode ───────────────────────────────────────────────
            //
            // One choice out of three, so one row: a segmented control where
            // the stack of three full-width rows used to be.
            Column {
                width: parent.width
                spacing: 8
                visible: AppState.powerProfiles.length > 0

                SectionLabel { text: "Power mode" }

                Rectangle {
                    id: modeSwitch
                    width: parent.width
                    height: 42
                    radius: height / 2
                    color: Theme.surfaceContainer

                    readonly property int count: AppState.powerProfiles.length
                    readonly property real segment: (width - 8) / Math.max(1, count)
                    readonly property int activeIndex: {
                        for (var i = 0; i < AppState.powerProfiles.length; i++)
                            if (AppState.powerProfiles[i].active) return i
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
                            NumberAnimation { duration: Theme.durMedium; easing.type: Easing.OutCubic }
                        }
                    }

                    Row {
                        x: 4
                        y: 4

                        Repeater {
                            model: AppState.powerProfiles

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
                                        font.family: Theme.fontMono
                                        color: mode.modelData.active ? Theme.accentText : Theme.textSecondary
                                        Behavior on color { ColorAnimation { duration: Theme.durMedium } }
                                    }
                                }

                                StateLayer {
                                    radius: height / 2
                                    interactive: !mode.modelData.active
                                    onTapped: AppState.setPowerProfile(mode.modelData.name)
                                }
                            }
                        }
                    }
                }
            }

            // ── Elsewhere ────────────────────────────────────────────────
            //
            // Settings, which the panel grows into, and the shortcut sheet.
            RowLayout {
                width: parent.width
                spacing: 8

                Repeater {
                    model: [
                        { key: "settings", icon: "\u{F0493}", label: "Settings",
                          detail: "Display, idle" },
                        { key: "binds", icon: "\u{F030C}", label: "Shortcuts",
                          detail: AppState.hyprBindsError.length > 0 ? "Config unread"
                                : AppState.hyprOverlayKeys.length > 0 ? AppState.hyprOverlayKeys
                                : AppState.hyprBindCount + " binds" }
                    ]

                    Rectangle {
                        id: link
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        radius: 16
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
                                    font.family: Theme.fontMono
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: link.modelData.detail
                                    color: link.modelData.key === "binds" && AppState.hyprBindsError.length > 0
                                         ? Theme.error : Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontMono
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
                                AppState.keybindsOpen = true
                            }
                        }
                    }
                }
            }

            // ── Power ────────────────────────────────────────────────────
            //
            // Full width and a comfortable size. They sat in the header for a
            // while as 28px circles, which saved height and made them fiddly to
            // hit. Restart and shut down carry their red before they are
            // touched, and ask for a second tap -- the header says so.
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
                        radius: 16
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
                            command: ["bash", "-lc", "systemctl reboot"]
                        }

                        Process {
                            id: shutdownProc
                            running: false
                            command: ["bash", "-lc", "systemctl poweroff"]
                        }
}
}
