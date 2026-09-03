# dotfiles

The configuration for a Hyprland desktop on CachyOS/Arch, plus an installer
that puts a fresh machine into the same state.

```sh
git clone <this repo> ~/dotfiles && cd ~/dotfiles && ./install.sh
```

Run `./install.sh --dry-run` first if you want to see what it would touch.

## What is here

| | |
|---|---|
| `manifest.txt` | every path this repo tracks, relative to `$HOME` |
| `home/` | the files themselves, laid out as they sit in `$HOME` |
| `packages/` | what to install: repo, AUR, and this config's own runtime needs |
| `install.sh` | packages, then dotfiles, then the things with their own manifests |
| `sync.sh` | the other direction: pull the live config back into the repo |

The repo holds **copies**, not symlinks into `$HOME`. Symlinks read better in a
listing but they make the working tree the live desktop: a half-finished edit
applies the moment it is saved, and `git checkout` becomes a way to change the
running session by accident. Two directions, two scripts.

`manifest.txt` is an **allowlist**. `~/.config` is 1.5 GB here and almost all
of it is state — browser profiles, Electron caches, session tokens, game saves.
Naming what to keep means a new application dropping a token in there is
excluded by default. A denylist would have been one forgotten entry away from
publishing one.

## Applications

The full lists are in `packages/`; this is what they amount to.

**Desktop** — `hyprland` with `hyprlock`, `hyprpaper`, `hyprsunset`,
`hyprpolkitagent` and `xdg-desktop-portal-hyprland`. The bar, panels and
wallpaper picker are `quickshell`, configured in `home/.config/quickshell`.
`rofi` and `fuzzel` launch things, `cliphist` keeps clipboard history,
`grim` + `slurp` + `grimblast-git` take screenshots, `veila-bin` locks.

**Terminal and shell** — `kitty`, `zsh` with `starship`, `zoxide` and
`eza`. `yazi` is the file manager, `micro` and `neovim` the editors, `btop`
and `glances` the monitors, `fastfetch` the greeter.

**Audio** — PipeWire (`pipewire-pulse`, `pipewire-alsa`, `wireplumber`) with
`pamixer`, `pavucontrol` and `playerctl`. The shell's per-application volume
reads `pactl` from `libpulse`.

**Theming** — `matugen` and `python-pywal` derive colours from the wallpaper;
`qt5ct`, `qt6ct`, `kvantum` and `nwg-look` apply them to toolkits.
`rose-pine-hyprcursor` is the cursor.

**Fonts** — `nerd-fonts-sf-mono` is not optional: the shell asks for
*SFMono Nerd Font Mono* by exact name, and without it every icon falls back to
whatever font happens to cover that glyph. `otf-apple-sf-pro`, `ttf-meslo-nerd`
and the `noto-fonts` family cover the rest.

**Applications** — `zen-browser-bin`, `discord` with `Vencord`, `obsidian`,
`spotify` with `spicetify-cli`, `qbittorrent`, `vlc`, `dolphin`,
`prismlauncher` and `modrinth-app`.

**NVIDIA** — `nvidia-open` kernel modules against `linux-cachyos`, plus
`nvidia-utils`, `libva-nvidia-driver`, `opencl-nvidia` and `nvibrant-bin`.

### The three that were nearly missed

`imagemagick`, `lua` and `libpulse` were installed on this machine only as
someone else's dependency, so they never appeared in the explicit package list.
A fresh install would have got them by luck. They are what the wallpaper
cropper, the keybind cheatsheet and the per-app volume list actually call, so
`packages/runtime.txt` names them outright.

## What this repo deliberately does not carry

Anything that identifies you rather than configures a machine: Zen's profile,
Discord's session, Obsidian's local cache, `qBittorrent`'s runtime sockets.
Sign in to those on the new machine.

Nor the pictures the configuration points at: `~/Pictures/Wallpapers` and
the avatar the clock panel shows. Configuration can name a picture, it
cannot carry one, and a missing path fails as a blank desktop with nothing
in any log to explain it — so `install.sh` checks them and says so.

Downloaded plugins are left out too —
yazi's `package.toml`, spicetify's ini and the AUR list are manifests, and
`install.sh` replays them.

## Restoring

`install.sh` moves anything it would overwrite into
`~/.local/share/dotfiles-backups/<timestamp>/`, keeping the original paths, so
undoing a run is copying that tree back over `$HOME`.
