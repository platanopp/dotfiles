# dotfiles

The configuration for a Hyprland desktop on CachyOS/Arch, plus an installer
that puts a fresh machine into the same state.

![The bar over the desktop](home/.config/quickshell/screenshots/desktop.jpg)

The shell in that picture is `home/.config/quickshell/`, which has its own
[README](home/.config/quickshell/README.md).

```sh
git clone https://github.com/platanopp/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./install.sh
```

Four lines rather than one because the repo is private, and a private repo
cannot be cloned by the machine that has not been set up yet. `git clone` over
HTTPS fails with `could not read Username`: GitHub stopped accepting passwords
there, so it wants a token. `gh auth login` gets one through the browser and
leaves git able to use it, which is the only part of this that cannot come out
of the repo itself.

Run `./install.sh --dry-run` first if you want to see what it would touch.

## What is here

| | |
|---|---|
| `manifest.txt` | every path this repo tracks, relative to `$HOME` |
| `home/` | the files themselves, laid out as they sit in `$HOME` |
| `packages/` | what to install: repo, AUR, and this config's own runtime needs |
| `install.sh` | packages, then dotfiles, then the things with their own manifests |
| `sync.sh` | the other direction: pull the live config back into the repo |

## Where to change things

Config files cannot be moved — every program looks for its own in a fixed
place — so this is a map rather than a tidier layout.

Two files carry most of the desktop. `home/.config/hypr/hyprland.lua` is the
compositor: keybinds, monitors, window rules and everything that starts at
login, all in one Lua file rather than the usual `hyprland.conf`.
`home/.config/quickshell/` is the bar, the panels and the launcher, written in
QML. Everything else is a single program's own settings.

| I want to change | Go to |
|---|---|
| a keybind | `hypr/hyprland.lua`, the `hl.bind` lines |
| monitor layout, resolution, refresh | `hypr/hyprland.lua`, the `hl.monitor` blocks |
| what starts at login | `hypr/hyprland.lua`, the `hyprland.start` hook |
| which window opens where | `hypr/hyprland.lua`, the workspace rules |
| the wallpaper | `hypr/hyprpaper.conf` |
| the shell's colours or fonts | `quickshell/Theme.qml` |
| what sits on the bar, and where | `quickshell/shell.qml` |
| one widget's behaviour | the matching `quickshell/*.qml` — `MediaWidget`, `ClockWidget`, `Workspaces`, … |
| the lock screen | `veila/config.toml` |
| the terminal | `kitty/kitty.conf` |
| the file manager | `yazi/` |
| the shell prompt | `starship.toml`, and `zsh/` for the rest |

Two things that surprise people:

The shell's palette is **fixed**, written out at the top of `Theme.qml`, and
that is the one place to edit it. Changing a wallpaper will not recolour the
bar.

The confusing part is that it looks like it should. `matugen/` and `wallust/`
are both configured to generate a palette for the shell, and both still write
one — `~/.cache/{matugen,wallust}/quickshell.json`, last touched in August.
Nothing in the QML reads either file. The wiring is left over from before
`Theme.qml` was pinned to a fixed palette, so editing those templates changes
nothing on screen.

`quickshell/scripts/` is not decoration. The QML shells out to it for anything
it cannot do itself — audio devices, bluetooth scans, the weather, the gamepad
mapper, the virtual display for streaming, osu's current beatmap. The
`*.service` files in there are systemd user units, symlinked into
`~/.config/systemd/user/` rather than copied, so editing one in the repo edits
the unit.

### What is not in here

Some of this desktop lives outside `$HOME` and so cannot be tracked by a
dotfiles repo. A restored machine comes up without it:

| | |
|---|---|
| `/etc/udev/rules.d/70-wooting.rules` | keyboard configurable without root |
| `/etc/udev/rules.d/70-wacom-hidraw.rules` | tablet visible to osu |
| `/etc/fstab` | the second SSD mounting at boot |
| `/etc/default/limine`, `/etc/mkinitcpio.conf` | the forced EDID that makes a virtual display exist for game streaming |

## Restoring

`install.sh` moves anything it would overwrite into
`~/.local/share/dotfiles-backups/<timestamp>/`, keeping the original paths, so
undoing a run is copying that tree back over `$HOME`.
