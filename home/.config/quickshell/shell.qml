//@ pragma UseQApplication
//@ pragma Env QSG_RENDER_LOOP=basic

// The basic render loop draws every window in one pass; Qt stopped picking it on its own (seen
// on Qt 6.12). The threaded loop runs a thread per window and the pills land a frame apart.
// Basic's cost: animations tick on Qt's 16 ms timer, not the monitor's refresh. Set here so
// the restart in shell_update.py gets it.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.bar
import qs.components
import qs.config
import qs.desktop
import qs.lock
import qs.overlays
import qs.services

Scope {
    id: root

    // Services are lazy singletons; named here so they all start with the shell (the IPC targets,
    // the keyboard's colours) even when only a panel reads them.
    readonly property var services: [Accent, AppImages, Audio, Bluetooth, Clock, Display, Hypr, KeyboardRgb,
                                     Keybinds, Network, Panels, Power, Profile, Recorder, Stats, System, Tablet,
                                     Wallpaper, Widgets]

    Variants {
        model: Quickshell.screens

        Item {
            id: screenRoot
            required property var modelData

            PanelWindow {
                id: bar
                screen: screenRoot.modelData

            anchors {
                top: true
                left: true
                right: true
            }

	    // The strip is as tall as the pill at the gap, and that is what Hyprland reserves: its own
	    // gap then sets the windows as far under the pill as the pill is from the screen's edge, and
	    // a bigger top gap moves both. The window runs 16px deeper for the pill's shadow;
	    // reserved space and input stay on the strip.
	    readonly property int stripHeight: Hypr.gapTop + leftPill.implicitHeight
	    implicitHeight: stripHeight + 16
	    exclusionMode: ExclusionMode.Normal
	    exclusiveZone: stripHeight
            color: "transparent"

            // Masked rather than unmapped, like the pills, so the surface keeps its place at
            // the bottom of the overlay stack.
            mask: bar.barHidden ? barBlankMask : barStripMask

            Region {
                id: barBlankMask
                width: 0
                height: 0
            }

            Region {
                id: barStripMask
                width: bar.width
                height: bar.stripHeight
            }

            // Spans the whole strip under the pills, so it notices the pointer between
            // them and the bar stays up along it.
            HoverHandler {
                id: barHover
            }

            WlrLayershell.namespace: "quickshell:bar-blur"
            WlrLayershell.layer: WlrLayer.Overlay

            property var monitor: Hyprland.monitorFor(modelData)

            // Right edge of the workspace pill: the media widget's window starts past it, and the
            // width changes with the indicators.
            readonly property int leftPillRight: leftPill.x + leftPill.width

            // The right-hand pills are one row (gear, status, tray), each parked off the live width
            // of the one to its right, so an expanding panel pushes its neighbours along.
            readonly property int pillGap: 10

            // Auto-hide while an app is fullscreen
            readonly property bool fullscreen: monitor && monitor.activeWorkspace
                ? monitor.activeWorkspace.hasFullscreen : false

            // Any pill under the pointer keeps the bar up: the reveal zone sits below the pills and
            // loses the pointer as soon as the bar appears, so alone it would flicker.
            readonly property bool barHovered: barHover.hovered || revealZone.hovered
                || mediaWidget.barHovered || statusWidget.barHovered
                || controlPanelWidget.barHovered || clockWidget.barHovered
                || trayWidget.barHovered

            // An open panel also holds it up, so the bar can't vanish while being read.
            readonly property bool panelsOpen: statusWidget.expandedPanel !== ""
                || controlPanelWidget.panelOpen || controlPanelWidget.notifOpen
                || mediaWidget.panelOpen
                || clockWidget.panelOpen

            // Settings -> Shell can keep the bar up over fullscreen windows.
            readonly property bool wantBar: !(fullscreen && ShellSettings.barHideFullscreen)
                                            || barHovered || panelsOpen

            // Shows at once, hides after a short delay: for a frame after revealing, neither the
            // zone nor a pill may have the pointer.
            property bool barHidden: false

            onWantBarChanged: {
                if (wantBar) {
                    hideDelay.stop()
                    bar.barHidden = false
                } else {
                    hideDelay.restart()
                }
            }

            Timer {
                id: hideDelay
                interval: 250
                onTriggered: bar.barHidden = true
            }

            // Starting up already fullscreen fires no change signal.
            Component.onCompleted: if (!bar.wantBar) hideDelay.restart()

            // Pills inset their glass 12px inside their windows, so windows overlap by 24 for
            // pillGap between visible edges. Reads rightMargin (always notifies) and visualWidth
            // (the box as drawn), so the row follows one animation.
            function pillLeftOf(w) {
                // rowWidth where a pill has one: the control panel keeps its row width
                // while growing into Settings.
                var wide = w.rowWidth !== undefined ? w.rowWidth
                         : w.visualWidth !== undefined ? w.visualWidth : w.width
                return Math.round(w.rightMargin + wide + pillGap - 24)
            }

            // Which MPRIS player the media widget drives, earlier in the list winning: list[0] let
            // a background Zen tab hold the widget, and playback state can't break the tie (Firefox
            // says Playing for silent tabs). osu first: its music is what plays while it's open.
            // The cycle control is hidden while either is around.
            readonly property var preferredPlayers: ["osu", "spotify"]

            // Set only when cycling by hand: a dbusName, since indexes shift as players come and
            // go. Decides only among unlisted players.
            property string pinnedPlayer: ""

            // Lower is better; anything unlisted sorts after every preference.
            function playerRank(p) {
                var key = ((p.desktopEntry || "") + " " + (p.dbusName || "")
                          + " " + (p.identity || "")).toLowerCase()
                for (var i = 0; i < preferredPlayers.length; i++) {
                    if (key.indexOf(preferredPlayers[i]) !== -1) return i
                }
                return preferredPlayers.length
            }

            property var activePlayer: {
                var list = Mpris.players.values
                if (list.length === 0) return null

                var best = list[0]
                for (var j = 1; j < list.length; j++) {
                    if (playerRank(list[j]) < playerRank(best)) best = list[j]
                }

                // A preferred player holds the widget as long as it's open, by request.
                if (playerRank(best) < preferredPlayers.length) return best

                // Otherwise a hand-picked player wins until it goes away.
                for (var i = 0; i < list.length; i++) {
                    if (list[i].dbusName === pinnedPlayer) return list[i]
                }
                return best
            }

            // True while a preferred player forces the choice, so the widget hides a
            // cycle control that would do nothing.
            readonly property bool playerLocked:
                activePlayer !== null && playerRank(activePlayer) < preferredPlayers.length

            // Position of the active player in the list, for the "1/2" counter.
            readonly property int activePlayerIndex: {
                var list = Mpris.players.values
                for (var i = 0; i < list.length; i++) {
                    if (list[i] === activePlayer) return i
                }
                return 0
            }

            function cyclePlayer() {
                var list = Mpris.players.values
                if (list.length < 2) return
                pinnedPlayer = list[(activePlayerIndex + 1) % list.length].dbusName
            }

            property string trackTitle: activePlayer ? activePlayer.trackTitle : ""
            property string trackArtist: activePlayer ? activePlayer.trackArtist : ""
            property bool isPlaying: activePlayer ? activePlayer.isPlaying : false
            property string trackArtUrl: activePlayer ? activePlayer.trackArtUrl : ""
            property bool canGoNext: activePlayer ? activePlayer.canGoNext : false
            property bool canGoPrevious: activePlayer ? activePlayer.canGoPrevious : false
            property bool canTogglePlaying: activePlayer ? activePlayer.canTogglePlaying : false

            Item {
                id: leftPill
                visible: !bar.barHidden
                anchors.left: parent.left
                anchors.top: parent.top
                // The one pill anchored to the screen, so it sets the row's left edge.
                anchors.leftMargin: Hypr.gapLeft
                anchors.topMargin: Hypr.gapTop
                implicitWidth: leftRow.implicitWidth + Theme.pillPaddingH * 2
                implicitHeight: Theme.pillHeight

                // Glass and shadow as every pill draws them (a hidden layered rectangle
                // through MultiEffect): a shadow item under plain translucency showed
                // through and darkened this pill.
                Rectangle {
                    id: leftGlass
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.glass
                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    source: leftGlass
                    anchors.fill: leftGlass
                    shadowEnabled: true
                    shadowColor: Theme.shadow
                    shadowOpacity: 0.5
                    shadowBlur: 0.7
                    shadowVerticalOffset: 4
                    autoPaddingEnabled: true
                }

                Behavior on implicitWidth {
                    Elastic { small: true }
                }

                RowLayout {
                    id: leftRow
                    anchors.centerIn: parent
                    spacing: 10

                    Workspaces {
                        monitor: bar.monitor
                    }
                }
            }
            }

            MediaWidget {
                id: mediaWidget
                bar: bar
            }

            StatusWidget {
                id: statusWidget
                bar: bar
                covered: controlPanelWidget.settingsOpen
                rightMargin: bar.pillLeftOf(controlPanelWidget)
            }

            TrayWidget {
                id: trayWidget
                bar: bar
                covered: controlPanelWidget.settingsOpen
                rightMargin: bar.pillLeftOf(statusWidget)
            }

            RevealZone {
                id: revealZone
                bar: bar
            }

            ControlPanel {
                id: controlPanelWidget
                bar: bar
            }

            NotificationPopups {
                bar: bar
            }

            LayoutToast {
                bar: bar
            }

            ClockWidget {
                id: clockWidget
                bar: bar
            }

            // The desktop widgets, under every window.
            DesktopLayer {
                bar: bar
            }
            KeybindsOverlay {
                bar: bar
            }

            WallpaperOverlay {
                bar: bar
            }
            WidgetPicker {
                bar: bar
            }

            // Last, so its surface is created last and sits above every other overlay,
            // the bar and open panels included.
            WorkspaceOverview {
                bar: bar
            }

            AppLauncher {
                bar: bar
            }

            BlankOverlay {
                bar: bar
            }

        }
    }

    // The session lock, outside Variants: WlSessionLock puts a surface on every screen by itself.
    // Raised by Super+L (Power.lockSession()), the control panel, `loginctl lock-session`, and
    // once per boot (the claim in LockEngine).
    LockScreen {
    }

    // `qs ipc call screens blank HDMI-A-1` / `unblank`, driven by hypridle via
    // ~/.config/hypr/scripts/idle-screens.sh (see BlankOverlay for why some screens are
    // covered rather than powered off).
    IpcHandler {
        target: "screens"

        function blank(names: string): void {
            Power.blankedScreens = names.split(/[\s,]+/).filter(n => n.length > 0)
        }

        function unblank(): void {
            Power.blankedScreens = []
        }
    }

    // Outside Variants: one registration per shell, not per monitor. Hyprland calls it as
    // `hl.dsp.global("quickshell:keybinds")`.
    GlobalShortcut {
        appid: "quickshell"
        name: "keybinds"
        description: "Show the keyboard shortcuts"

        onPressed: Panels.toggleKeybinds()
    }

    // Escape while a bar panel is open, bound by Panels only while one is (escapeBind).
    GlobalShortcut {
        appid: "quickshell"
        name: "dismiss"
        description: "Close the open panel"

        onPressed: Panels.dismissPanels()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "settings"
        description: "Open or close Settings"

        onPressed: Panels.toggleSettings()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "wallpapers"
        description: "Choose the wallpaper"

        onPressed: Panels.toggleWallpapers()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "widgets"
        description: "Put widgets on the desktop, move them, take them off"
        onPressed: Panels.toggleWidgets()
    }
    GlobalShortcut {
        appid: "quickshell"
        name: "launcher"
        description: "Search and launch an application"

        onPressed: Panels.toggleLauncher()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "record"
        description: "Start or stop recording the screen"

        onPressed: Recorder.toggleRecording("")
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "overview"
        description: "Show every workspace and its windows"

        onPressed: Panels.toggleOverview()
    }

    // The lock is this shell's own surface, so the bind goes through the shell
    // (Power.lockSession(), as the control panel does).
    GlobalShortcut {
        appid: "quickshell"
        name: "lock"
        description: "Lock the screen"

        onPressed: Power.lockSession()
    }

    // Through the shell rather than a bare wpctl bind, so the mic indicator updates at once and
    // the cue knows which way the toggle went.
    GlobalShortcut {
        appid: "quickshell"
        name: "micmute"
        description: "Mute or unmute the microphone"

        onPressed: Audio.toggleMicMute()
    }
}
