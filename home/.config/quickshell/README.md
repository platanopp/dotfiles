# quickshell

A desktop shell for [Quickshell](https://quickshell.org/), written as a flat set
of QML components and tuned for Hyprland on Wayland.

![The bar over the desktop](./screenshots/desktop.jpg)

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

Behind the bar, opened from the control panel or from a key: a keyboard
shortcut cheatsheet read out of the live Hyprland config, a wallpaper picker,
per-app volume, an in-process notification server with do-not-disturb, and a
fade either side of the lock screen.

## Running it

The config sits at `~/.config/quickshell/shell.qml`, which Quickshell picks up
as the default:

```sh
qs
```

It reloads itself when a file changes, so there is nothing to restart while
editing.

Colours, type and the motion scale all come from `Theme.qml`; nothing else
should be hardcoding a hex or a duration. `scripts/` holds the helpers the QML
shells out to.
