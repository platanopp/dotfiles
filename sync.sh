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
if [ ${#missing[@]} -gt 0 ]; then
    echo "not on this machine (skipped):"
    printf '  %s\n' "${missing[@]}"
fi
