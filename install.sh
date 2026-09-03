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
#   ./install.sh packages     only the package lists
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

    say "Repository packages"
    # Two lists, read as one. runtime.txt names what this configuration calls
    # and pacman.txt what the machine had; the overlap is harmless because
    # pacman is asked only for what is actually missing.
    local wanted
    wanted="$(cat "$repo/packages/runtime.txt" "$repo/packages/pacman.txt" \
              | sed 's/#.*//' | tr -d ' \t' | grep -v '^$' | sort -u)"

    # Filtered against what is already installed so the list pacman is handed
    # is only what is actually missing -- otherwise a rerun reinstalls 200
    # packages to end up where it started.
    local missing=()
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done <<< "$wanted"

    if [ ${#missing[@]} -eq 0 ]; then
        ok "all $(wc -l <<< "$wanted") already installed"
    else
        note "${#missing[@]} missing of $(wc -l <<< "$wanted")"
        run sudo pacman -S --needed --noconfirm "${missing[@]}"
    fi

    say "AUR packages"
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
        [ -z "$helper" ] && { warn "could not get an AUR helper; skipping AUR packages"; return; }
    fi

    local aur_missing=()
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        pacman -Qq "$pkg" >/dev/null 2>&1 || aur_missing+=("$pkg")
    done < "$repo/packages/aur.txt"

    if [ ${#aur_missing[@]} -eq 0 ]; then
        ok "all $(wc -l < "$repo/packages/aur.txt") already installed"
    else
        note "${#aur_missing[@]} missing: ${aur_missing[*]}"
        run "$helper" -S --needed --noconfirm "${aur_missing[@]}"
    fi
}

# ── Dotfiles ─────────────────────────────────────────────────────────────

install_config() {
    say "Configuration"
    local moved=0 placed=0

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
        fi
        placed=$((placed + 1))
    done < "$repo/manifest.txt"

    ok "$placed installed, $moved moved aside"
    [ "$moved" -gt 0 ] && [ "$DRY" = 0 ] && note "previous copies: $backup"
    return 0
}

# ── Everything that has its own manifest ─────────────────────────────────

install_post() {
    say "Plugins and themes"

    # Tracked as a lockfile rather than as the plugins themselves: the repo
    # keeps yazi's package.toml, and yazi fetches what it names.
    if command -v ya >/dev/null && [ -f "$HOME/.config/yazi/package.toml" ]; then
        note "yazi plugins"
        run ya pkg install
    else
        note "yazi not installed yet; skipping its plugins"
    fi

    # Spicetify patches the Spotify client in place, so it has to be re-run
    # on the target machine; the repo only carries which theme was chosen.
    if command -v spicetify >/dev/null; then
        note "spicetify"
        run spicetify backup apply
    else
        note "spicetify not installed; skipping"
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
    note "Vencord: run the installer once so it patches your Discord"
    note "Zen, Discord and Obsidian keep accounts and sessions, which this"
    note "repo deliberately does not carry -- sign in on the new machine"
}

case "$STAGE" in
    all)      install_packages; install_config; install_post ;;
    packages) install_packages ;;
    config)   install_config ;;
    post)     install_post ;;
esac

echo
[ "$DRY" = 1 ] && say "dry run: nothing was changed" || say "done"
