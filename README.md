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

## Restoring

`install.sh` moves anything it would overwrite into
`~/.local/share/dotfiles-backups/<timestamp>/`, keeping the original paths, so
undoing a run is copying that tree back over `$HOME`.
