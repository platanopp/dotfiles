# quickshell

A desktop shell for [Quickshell](https://quickshell.org/), tuned for Hyprland on
Wayland.

![The bar over the desktop](./screenshots/desktop-2026-09.jpg)

## What is on screen

The bar is not one window. Every pill is its own layer surface, parked off the
live width of its neighbour, so a panel that expands pushes the others along
instead of growing out underneath them.

- **Left** — the workspace pill (the active workspace is labelled, the rest are
  dots, dimmer where the workspace is empty), then the media widget.
- **Centre** — the clock and date, and the quick-capture pill that writes
  straight into the Obsidian vault.
- **Right** — the system tray, then the status pill (network, Bluetooth,
  volume, microphone, battery), then the control panel.

The whole row hides itself while an app is fullscreen and comes back when the
pointer reaches the top of the screen.

Over the desktop, opened from the control panel or from a key: the launcher
(Super+Space), the workspace overview (Super+Tab), the wallpaper picker, a
keyboard shortcut sheet read out of the live Hyprland config, notification
toasts with do-not-disturb, screen recording, the Settings window, and a lock
screen the shell draws itself.

## How it is laid out

```
shell.qml        the entry point: one bar per screen, the overlays, global shortcuts
services/        state and logic, no UI -- one singleton per subject
config/          Theme (colours, type, motion) and ShellSettings (the user's choices)
bar/             the pills along the top and the panels they open
overlays/        full-screen or floating layers: launcher, overview, wallpapers,
                 keybinds sheet, notification toasts, the black screen cover
lock/            the lock screen and the engine behind it (PAM, the session lock)
settings/        the Settings window, its building blocks, and pages/ -- one per page
components/      small pieces used everywhere: icons, buttons, switches, sliders
scripts/         the helpers the QML shells out to (Python, shell, Lua)
```

Views mostly read a service's properties and call its functions rather than
run commands of their own, so to see how something works, start from its
service.

| Service | What it holds |
| --- | --- |
| `Audio` | Volume and mute, output and input devices, the microphone, per-app streams |
| `Network` | Wi-Fi and wired state, the scan list, connecting |
| `Bluetooth` | Power, devices, scanning, pairing |
| `Wallpaper` | Pictures and videos, the crop hyprpaper shows, pausing a video under a fullscreen window |
| `KeyboardRgb` | The Wooting keyboard's colours, taken from the wallpaper |
| `Panels` | Which panel or overlay is open and where; Escape, the IPC targets, Hyprland's `shell-modal` submap |
| `Keybinds` | Hyprland's and Yazi's binds, for the shortcut sheet |
| `Recorder` | Screen recording: the countdown, the timer, the file |
| `Display` | Monitors: mode, scale, layout, VRR, colour; keep-or-revert |
| `Hypr` | Hyprland options for Settings, and the gaps the bar lines up with |
| `Power` | Battery, power profile, idle timeouts, lock and suspend |
| `Profile` | User name and avatar |
| `System` | Distribution, About, the dotfiles backup |
| `Tablet` | OpenTabletDriver on and off |
| `Notes` | The Obsidian quick-capture note |
| `Clock` | The time and date |
| `Notifications` | The notification server, the centre and the toasts |
| `Spectrum`, `AlbumColors` | The media widget's spectrum ring and its colour |
| `SteamGames`, `AppImages`, `LauncherHistory` | The launcher's Steam library, the AppImages in `~/Applications`, and what it has opened most |
| `Weather` | Current conditions and the forecast, for the clock's panel and the lock screen |

A file uses another folder's types by importing it: `import qs.services`,
`import qs.components`, and so on. Files in the same folder see each other
without one.

`Bluetooth` and `Network` share their names with singletons in Quickshell's
own `Quickshell.Bluetooth` and `Quickshell.Networking` modules. A file that
needs one of those as well imports it with a qualifier (see
`lock/LockEngine.qml`).

## Apps in the launcher

The launcher (Super+Space) lists three kinds of things you can start:

- **Applications**: every `.desktop` file, as Quickshell's `DesktopEntries`
  reads them from the usual places (`/usr/share/applications`,
  `~/.local/share/applications`). A new `.desktop` file shows up
  on its own within a second or two; no reload is needed.
- **Steam games**: read off Steam's own files by `scripts/steam_games.py`
  (`services/SteamGames.qml`). Checked each time the launcher opens, at most
  once a minute.
- **AppImages**: see below.

### AppImages

To add one, move it into **`~/Applications`**. That is all. The next time
the launcher opens, the app is in its list, with its own name and icon.

Each time the launcher opens (at most every 5 seconds), and once as the
shell starts, `services/AppImages.qml` runs `scripts/appimage_sync.py`. The
script works through `~/Applications`:

- **A new AppImage.**
  - The script marks it executable.
  - It reads the `.desktop` file and the icon the image carries inside itself.
  - It writes `~/.local/share/applications/appimage-<name>.desktop`, and the
    icon under `~/.local/share/icons/hicolor/`.
  - These are real `.desktop` files, so the app also shows up in "Open with"
    menus and handles its links (Wootility's `wootwoot://`, for one).
- **An AppImage that is gone.** Its entry and icon are removed.
- **Two versions of one app.** When a new version sits beside an old one
  (`App-1.2.AppImage`, `App-1.3.AppImage`), the higher version is the one
  listed. Deleting the old file cleans up after it.
- **Already listed.** An AppImage that already has a `.desktop` of its own,
  written by hand, is left alone. The script recognises it by what its
  `Exec` runs, through symlinks, or else by name. osu!'s is one: it sets an
  environment variable the script would not know about. If that AppImage
  later leaves the folder, the hand-made entry is removed too, since it
  would open nothing.
- **Nothing new.** A run takes about 30 ms, in a process of its own, so
  opening the launcher never waits for it.

The file names do not matter. Keeping them without the version
(`RPCS3.AppImage`) still helps anything else that points at the file
directly.

**One exception: Taller.** Its entry runs `~/.local/bin/taller`, a script
that looks for the newest `Taller*.AppImage` itself. The sync cannot tell
that this entry depends on the file, so deleting Taller's AppImage leaves
its entry in place.

To run the sync by hand (it only prints on errors):

```sh
python3 ~/.config/quickshell/scripts/appimage_sync.py
```

## Running it

The config sits at `~/.config/quickshell/shell.qml`, which Quickshell picks up
as the default:

```sh
qs
```

It reloads itself when a file changes, so there is nothing to restart while
editing. One caveat: an editor that saves by writing a new file and renaming
it over the old one can go unnoticed in the subfolders (only the top folder
is watched as a whole). If a change does not show, `touch shell.qml`.

Colours, type and the motion scale all come from `config/Theme.qml`; nothing
else should be hardcoding a hex or a duration. `shell-settings.json` holds what
the Settings window changes.
