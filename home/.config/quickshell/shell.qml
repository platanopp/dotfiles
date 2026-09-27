//@ pragma UseQApplication

import "."
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

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

	    // The strip is only as tall as it needs to hold the pill at the
	    // gap, and its height is what Hyprland reserves -- so raising the
	    // top gap moves the bar down and the windows with it, instead of
	    // sliding the pill out of a strip that stayed 51px tall.
	    implicitHeight: AppState.gapTop + leftPill.implicitHeight + 3
            color: "transparent"

            // See the pills: masked rather than unmapped, so the layer surface
            // keeps its place at the bottom of the overlay stack.
            mask: bar.barHidden ? barBlankMask : null

            Region {
                id: barBlankMask
                width: 0
                height: 0
            }

            // This window spans the whole strip and sits under the pills, so
            // it is what notices the pointer between them -- that is how the
            // bar stays up anywhere along its length, not just on a pill.
            HoverHandler {
                id: barHover
            }

            WlrLayershell.namespace: "quickshell:bar-blur"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (statusWidget.expandedPanel === "wifi" && AppState.wifiExpandedSsid.length > 0) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            property var monitor: Hyprland.monitorFor(modelData)
            property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0

            // Right edge of the workspace pill. The media widget is its own
            // window and has to start past it, and the pill's width changes
            // with the workspace indicators.
            readonly property int leftPillRight: leftPill.x + leftPill.width

            // The right-hand pills are one row: gear, then status, then tray.
            // Each parks itself off the live width of the one to its right, so
            // a panel that expands pushes its neighbours along rather than
            // growing out underneath them.
            readonly property int pillGap: 10

            // ── Auto-hide while an app is fullscreen ─────────────────────
            readonly property bool fullscreen: monitor && monitor.activeWorkspace
                ? monitor.activeWorkspace.hasFullscreen : false

            // Any pill under the pointer keeps the bar up. The reveal zone
            // alone is not enough: it sits below the pills, so the moment the
            // bar appears under the cursor the zone loses the pointer, and the
            // bar would flicker between shown and hidden.
            readonly property bool barHovered: barHover.hovered || revealZone.hovered
                || mediaWidget.barHovered || statusWidget.barHovered
                || controlPanelWidget.barHovered || clockWidget.barHovered
                || trayWidget.barHovered || notesWidget.barHovered

            // An open panel also holds it, so the bar cannot vanish from under
            // someone reading it.
            readonly property bool panelsOpen: statusWidget.expandedPanel !== ""
                || controlPanelWidget.panelOpen || mediaWidget.panelOpen
                || clockWidget.panelOpen || notesWidget.panelOpen

            // Settings -> Shell can keep the bar up over fullscreen windows.
            readonly property bool wantBar: !(fullscreen && ShellSettings.barHideFullscreen)
                                            || barHovered || panelsOpen

            // Shows at once, hides on a short delay. Revealing drops the pills
            // under the cursor, and for a frame the zone can have lost the
            // pointer before a pill has registered it; without the delay that
            // gap collapses the bar and it oscillates.
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

            // Every pill insets its glass 12px inside its own window, so two
            // windows have to overlap by 24 for the visible edges to end up
            // pillGap apart. Reads rightMargin rather than margins.right: a
            // plain property is guaranteed to notify, so the row actually
            // follows when a neighbour moves.
            //
            // A pill's width here is its box as drawn (visualWidth, which
            // animates) rather than its window, which is sized to hold the
            // box's whole move and so is wider mid-animation (see PillStage).
            // The pills that follow take the value frame by frame with no
            // animation of their own: one animation at the source, and the
            // row moves with it instead of chasing it.
            function pillLeftOf(w) {
                // rowWidth where a pill has one: the control panel keeps its
                // place in the row at the panel's width while it grows into
                // Settings, so its neighbours are not pushed into the clock.
                var wide = w.rowWidth !== undefined ? w.rowWidth
                         : w.visualWidth !== undefined ? w.visualWidth : w.width
                return Math.round(w.rightMargin + wide + pillGap - 24)
            }

            // Same arithmetic the other way, for a pill that parks off the
            // right edge of a left-anchored neighbour: visualRight is where
            // its box ends, in screen coordinates.
            function pillRightOf(w) {
                var right = w.visualRight !== undefined ? w.visualRight : w.leftMargin + w.width
                return Math.round(right + pillGap - 24)
            }

            // Which MPRIS player the media widget drives.
            //
            // Taking list[0] meant whoever registered on the bus first won, and
            // the browser is usually up long before the music is -- so a
            // background Zen tab held the widget while Spotify played. Playback
            // state cannot break the tie either: Firefox reports Playing for a
            // tab that makes no sound, so both players look active. The tie is
            // broken by identity instead, earlier in this list winning.
            //
            // osu ahead of Spotify: while osu is open its own music is what is
            // actually coming out of the speakers, so that is what the bar
            // should be naming. Spotify next, and everything else -- browser
            // tabs, mostly -- last.
            //
            // Note this also widens the lock below: with two preferred players,
            // the cycle control is hidden whenever either of them is around,
            // not just Spotify.
            readonly property var preferredPlayers: ["osu", "spotify"]

            // Set only when the user cycles players by hand. Holds a dbusName
            // rather than a list index: the list reorders as players come and
            // go, so an index quietly starts meaning somebody else. It only
            // decides between unlisted players -- a preferred one always wins.
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

                // A preferred player holds the widget for as long as it is
                // open; nothing overrides it, by request.
                if (playerRank(best) < preferredPlayers.length) return best

                // Otherwise a hand-picked player wins until it goes away.
                for (var i = 0; i < list.length; i++) {
                    if (list[i].dbusName === pinnedPlayer) return list[i]
                }
                return best
            }

            // True while a preferred player is forcing the choice, so the
            // widget can stop offering a cycle control that would do nothing.
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

            Rectangle {
                id: leftPill
                visible: !bar.barHidden
                anchors.left: parent.left
                anchors.top: parent.top
                // The one pill anchored to the screen rather than to a
                // neighbour, so it is where the left edge of the row is set.
                anchors.leftMargin: AppState.gapLeft
                anchors.topMargin: AppState.gapTop
                implicitWidth: leftRow.implicitWidth + Theme.pillPaddingH * 2
                implicitHeight: 40
                radius: 20
                color: Theme.glass

                Behavior on implicitWidth {
                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
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

            NotesWidget {
                id: notesWidget
                bar: bar
                covered: controlPanelWidget.settingsOpen
                leftMargin: bar.pillRightOf(clockWidget)
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

            ClockWidget {
                id: clockWidget
                bar: bar
            }

            KeybindsOverlay {
                bar: bar
            }

            WallpaperOverlay {
                bar: bar
            }

            // Last, so its surface is created last and sits on top of every
            // other overlay this shell puts up -- the fade has to cover the
            // bar and any open panel, not slide in behind them.
            AppLauncher {
                bar: bar
            }

            BlankOverlay {
                bar: bar
            }

        }
    }

    // The session lock. Outside Variants because WlSessionLock puts up its
    // own surface on every screen by itself -- a per-screen copy would have
    // each of them trying to claim the one session lock.
    //
    // Raised by Super + L through AppState.lockSession(), by the control
    // panel, by `loginctl lock-session` from anywhere, and once on the first
    // start after a boot -- see the claim in LockEngine, which is what stands
    // in for a greeter on a seat that is handed over already logged in.
    LockScreen {
    }

    // `qs ipc call screens blank HDMI-A-1` / `unblank`. Driven by hypridle
    // through ~/.config/hypr/scripts/idle-screens.sh; see BlankOverlay for why
    // some screens are covered rather than powered off.
    IpcHandler {
        target: "screens"

        function blank(names: string): void {
            AppState.blankedScreens = names.split(/[\s,]+/).filter(n => n.length > 0)
        }

        function unblank(): void {
            AppState.blankedScreens = []
        }
    }

    // Outside Variants: one registration for the whole shell, where a
    // per-screen copy would try to claim the same name once per monitor.
    // Hyprland reaches it as `hl.dsp.global("quickshell:keybinds")`.
    GlobalShortcut {
        appid: "quickshell"
        name: "keybinds"
        description: "Show the keyboard shortcuts"

        onPressed: AppState.toggleKeybinds()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "wallpapers"
        description: "Choose the wallpaper"

        onPressed: AppState.toggleWallpapers()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "launcher"
        description: "Search and launch an application"

        onPressed: AppState.toggleLauncher()
    }

    // The lock is this shell's own surface, so the bind has to reach the shell
    // rather than run a locker of its own -- see AppState.lockSession(), which
    // is also where the control panel and its suspend go.
    GlobalShortcut {
        appid: "quickshell"
        name: "lock"
        description: "Lock the screen"

        onPressed: AppState.lockSession()
    }

    // Routed through the shell rather than run as a bare wpctl bind, so the
    // bar's microphone indicator moves with the key instead of waiting for
    // the next poll to notice -- and so the cue is played by the thing that
    // knows which way the toggle went.
    GlobalShortcut {
        appid: "quickshell"
        name: "micmute"
        description: "Mute or unmute the microphone"

        onPressed: AppState.toggleMicMute()
    }
}
