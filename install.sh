#!/usr/bin/env bash
# Bring a machine up to this configuration.
#
# Safe to run on a machine that already has some of this: packages already
# installed are skipped by pacman, and anything about to be overwritten in
# $HOME is moved into a timestamped backup first rather than replaced. Run it
# twice and the second run changes nothing.
#
#   ./install.sh              everything
#   ./install.sh --dry-run    say what it would do, touch nothing
#   ./install.sh packages     only the packages (packages/shell.txt)
#   ./install.sh config       only the dotfiles
#   ./install.sh post         only the post-install steps

set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stamp="$(date +%Y%m%d-%H%M%S)"
backup="$HOME/.local/share/dotfiles-backups/$stamp"

DRY=0
STAGE=all
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        packages|config|post) STAGE="$arg" ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

bold=$'\e[1m'; dim=$'\e[2m'; red=$'\e[31m'; green=$'\e[32m'; reset=$'\e[0m'
say()  { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
note() { printf '    %s%s%s\n' "$dim" "$*" "$reset"; }
warn() { printf '    %s%s%s\n' "$red" "$*" "$reset"; }
ok()   { printf '    %s%s%s\n' "$green" "$*" "$reset"; }
run()  { if [ "$DRY" = 1 ]; then note "would run: $*"; else "$@"; fi; }

if [ "$(id -u)" = 0 ]; then
    echo "Run this as your own user. It will ask for sudo when it needs to." >&2
    exit 1
fi

# ── Packages ─────────────────────────────────────────────────────────────

install_packages() {
    if ! command -v pacman >/dev/null; then
        warn "no pacman here; skipping packages (the dotfiles below still apply)"
        return
    fi

    say "Packages"
    # Every list under packages/ -- here shell.txt, what the shell and its
    # configuration need, and only that. Filtered against what is already
    # installed, so a rerun asks for nothing; then split by where each one
    # lives -- the repositories this machine has, or the AUR. A name the
    # repositories lack would make pacman refuse the whole list, and which
    # side a package is on varies between Arch and its derivatives.
    local wanted
    wanted="$(cat "$repo"/packages/*.txt | sed 's/#.*//' | tr -d ' \t' | grep -v '^$' | sort -u)"

    local repo_missing=() aur_missing=()
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        pacman -Qq "$pkg" >/dev/null 2>&1 && continue
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            repo_missing+=("$pkg")
        else
            aur_missing+=("$pkg")
        fi
    done <<< "$wanted"

    if [ ${#repo_missing[@]} -eq 0 ] && [ ${#aur_missing[@]} -eq 0 ]; then
        ok "all $(wc -l <<< "$wanted") already installed"
        return
    fi

    if [ ${#repo_missing[@]} -gt 0 ]; then
        note "${#repo_missing[@]} from the repositories"
        run sudo pacman -S --needed --noconfirm "${repo_missing[@]}"
    fi

    [ ${#aur_missing[@]} -eq 0 ] && return
    note "${#aur_missing[@]} from the AUR: ${aur_missing[*]}"
    local helper=""
    for candidate in paru yay; do
        command -v "$candidate" >/dev/null && { helper="$candidate"; break; }
    done

    if [ -z "$helper" ]; then
        note "no AUR helper found; building paru once, by hand"
        if [ "$DRY" = 0 ]; then
            local tmp
            tmp="$(mktemp -d)"
            sudo pacman -S --needed --noconfirm base-devel git \
              && git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin" \
              && (cd "$tmp/paru-bin" && makepkg -si --noconfirm) \
              && helper=paru
            rm -rf "$tmp"
        fi
        [ -z "$helper" ] && { warn "could not get an AUR helper; skipping: ${aur_missing[*]}"; return; }
    fi

    run "$helper" -S --needed --noconfirm "${aur_missing[@]}"
}

# ── Dotfiles ─────────────────────────────────────────────────────────────

install_config() {
    say "Configuration"
    local moved=0 placed=0
    # $HOME as a sed replacement: the characters sed would read as its own.
    local home_sed
    home_sed="$(printf '%s' "$HOME" | sed 's/[\\&|]/\\&/g')"

    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(echo "$line" | xargs || true)"
        [ -z "$line" ] && continue

        local src="$repo/home/$line"
        local dst="$HOME/$line"
        [ -e "$src" ] || continue

        # Anything already there is moved aside whole, keeping its path, so a
        # bad run is undone by copying the backup tree back over $HOME.
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            if [ "$DRY" = 1 ]; then
                note "would back up and replace ~/$line"
            else
                mkdir -p "$backup/$(dirname "$line")"
                mv "$dst" "$backup/$line"
            fi
            moved=$((moved + 1))
        fi

        if [ "$DRY" = 1 ]; then
            note "would install ~/$line"
        else
            mkdir -p "$(dirname "$dst")"
            cp -a "$src" "$dst"
            # Paths into the home folder are kept as @HOME@ in the repo
            # (see sync.sh); this user's home goes in their place.
            grep -rlIZF -- '@HOME@' "$dst" 2>/dev/null \
                | xargs -0r sed -i "s|@HOME@|${home_sed}|g"
        fi
        placed=$((placed + 1))
    done < "$repo/manifest.txt"

    ok "$placed installed, $moved moved aside"
    [ "$moved" -gt 0 ] && [ "$DRY" = 0 ] && note "previous copies: $backup"
    return 0
}

# ── Everything that has its own manifest ─────────────────────────────────

install_post() {
    say "Services and fonts"

    # The units live in the configuration they belong to, and systemd only
    # knows about them through symlinks in ~/.config/systemd/user, which this
    # repo does not carry. Without the target, hyprland.lua's
    # `systemctl --user start hyprland-session.target` fails at every login
    # and nothing wanted by graphical-session.target ever starts.
    if command -v systemctl >/dev/null; then
        note "user units"
        run systemctl --user enable "$HOME/.config/hypr/hyprland-session.target" \
                                    "$HOME/.config/quickshell/scripts/osu-mpris.service"
    fi

    if command -v fc-cache >/dev/null; then
        note "font cache"
        run fc-cache -f
    fi

    # Configuration can name a picture; it cannot carry one. These paths are
    # checked rather than assumed, because what they fail as is a blank
    # desktop with nothing in any log to explain it.
    say "Files this configuration points at"
    if [ ! -d "$HOME/Pictures/Wallpapers" ]; then
        warn "~/Pictures/Wallpapers is missing -- the picker will be empty"
        note "put wallpapers there, then pick one with Super + W"
    else
        ok "wallpapers: $(find "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f | wc -l) found"
    fi

    # hyprpaper is pointed at a crop under ~/.cache, which is per-machine and
    # not in this repo, so a fresh install inherits a path to nothing.
    local paper="$HOME/.config/hypr/hyprpaper.conf"
    if [ -f "$paper" ]; then
        local target
        target="$(sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$paper" | head -1)"
        if [ -n "$target" ] && [ ! -f "$target" ]; then
            warn "hyprpaper points at a wallpaper that is not on this machine"
            note "pick one with Super + W and it will rewrite itself"
        fi
    fi

    say "Left to do by hand"
    note "ddcutil needs i2c-dev at boot, for switching a side display off:"
    note "  echo i2c-dev | sudo tee /etc/modules-load.d/i2c-dev.conf"
    note "hypr/monitors.lua describes the publisher's two monitors; set yours"
    note "in Settings -> Displays and it is rewritten for this machine"
}

case "$STAGE" in
    all)      install_packages; install_config; install_post ;;
    packages) install_packages ;;
    config)   install_config ;;
    post)     install_post ;;
esac

echo
[ "$DRY" = 1 ] && say "dry run: nothing was changed" || say "done"
