#!/usr/bin/env bash
# Pull the live configuration into the repo.
#
# The repo is a copy, not a set of symlinks pointing back at it. Symlinks read
# better in a listing but they make the working tree the live configuration:
# a half-finished edit is live the moment it is saved, and `git checkout` is a
# way to change the running desktop by accident. Copying keeps the two apart,
# and this script is the one direction, install.sh the other.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dest="$repo/home"

copied=0
missing=()

while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs || true)"
    [ -z "$line" ] && continue

    src="$HOME/$line"
    if [ ! -e "$src" ]; then
        missing+=("$line")
        continue
    fi

    mkdir -p "$dest/$(dirname "$line")"
    if [ -d "$src" ]; then
        # --delete so a file removed from the live config leaves the repo too,
        # which a plain copy would never notice.
        rsync -a --delete \
              --exclude '.git/' \
              --exclude '*.log' \
              --exclude 'Cache/' \
              --exclude 'GPUCache/' \
              "$src/" "$dest/$line/"
    else
        cp -a "$src" "$dest/$line"
    fi
    copied=$((copied + 1))
done < "$repo/manifest.txt"

echo "synced $copied entries"

# A few files hold this machine's home as an absolute path: GTK's bookmarks,
# qt6ct's colour scheme, qBittorrent's and spicetify's own records -- formats
# that read neither $HOME nor ~ -- and hyprpaper's wallpaper, which the shell
# writes out in full. Copied as they are, they pointed a fresh install into
# this user's home. The
# repo keeps @HOME@ in its place instead, and install.sh (and the shell's
# updater) writes back the home of whoever installs. Only a whole path
# segment is replaced: /home/ana, not the start of /home/ana2.
while IFS= read -r -d '' f; do
    perl -pi -e 's/\Q$ENV{HOME}\E(?![A-Za-z0-9._-])/\@HOME\@/g' "$f"
done < <(grep -rlIZF -- "$HOME" "$dest" 2>/dev/null || true)

# Configuration directories bring their own .gitignore, and git honours them
# wherever they sit -- so a rule written for somebody's upstream repo silently
# decides what this backup keeps. Only one file was being dropped when this
# was found, and it was harmless; the point is that it was being dropped
# without a word. Rules from this repo's own .gitignore are the intended ones
# and stay quiet. Anything else gets named.
surprises=()
while IFS= read -r f; do
    [ -z "$f" ] && continue
    source_rule="$(cd "$repo" && git check-ignore -v "$f" 2>/dev/null | cut -d: -f1)"
    case "$source_rule" in
        .gitignore|"") ;;
        *) surprises+=("$f  (by $source_rule)") ;;
    esac
done < <(cd "$repo" && git ls-files --others --ignored --exclude-standard home/ 2>/dev/null)

if [ ${#surprises[@]} -gt 0 ]; then
    echo
    echo "held back by a .gitignore that came with a config, not by this repo:"
    printf '  %s\n' "${surprises[@]}"
    echo "  keep one with: git add -f <path>"
fi
if [ ${#missing[@]} -gt 0 ]; then
    echo "not on this machine (skipped):"
    printf '  %s\n' "${missing[@]}"
fi
