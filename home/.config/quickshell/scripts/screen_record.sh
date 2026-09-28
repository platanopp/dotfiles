#!/usr/bin/env bash
# Records a monitor until it is sent SIGINT.
#
#   screen_record.sh [--monitor NAME] [--height native|2160|1440|1080|720]
#                    [--fps N] [--quality medium|high|very_high|ultra]
#                    [--codec h264|hevc] [--audio none|system|mic|both]
#                    [--cursor yes|no] [--dir FOLDER]
#
# Everything has a default (the monitor in use, 1080p, 60 fps, very high,
# H.264, the computer's sound, ~/Vídeos/Recordings); Settings -> Recording
# picks them (ShellSettings, passed in by AppState.startRecording).
#
# Prints the file it writes to as its first line, then becomes the recorder
# (exec), so the SIGINT the shell sends to stop it reaches
# gpu-screen-recorder itself -- which is what makes it finish the file.
#
# gpu-screen-recorder, not wf-recorder or OBS: it encodes on the GPU (NVENC
# on this RTX 3060), so a recording costs next to no CPU and nothing a game
# would notice. Always MP4 at a constant frame rate (-fm cfr): what editors
# and phones expect, where a variable rate stutters.
set -euo pipefail

monitor="" height="1080" fps="60" quality="very_high" codec="h264"
audio="system" cursor="yes" dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --monitor) monitor="$2"; shift 2 ;;
        --height)  height="$2";  shift 2 ;;
        --fps)     fps="$2";     shift 2 ;;
        --quality) quality="$2"; shift 2 ;;
        --codec)   codec="$2";   shift 2 ;;
        --audio)   audio="$2";   shift 2 ;;
        --cursor)  cursor="$2";  shift 2 ;;
        --dir)     dir="$2";     shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# The monitor, and its size, from Hyprland: the one in use unless named.
read -r monitor mw mh < <(hyprctl monitors -j | python3 -c "
import json, sys
want = sys.argv[1]
ms = json.load(sys.stdin)
m = next((m for m in ms if m['name'] == want), None) or next((m for m in ms if m['focused']), ms[0])
print(m['name'], m['width'], m['height'])
" "$monitor")

# Scaled down to the height asked for, the width following the monitor's
# shape -- and never up: a 1440p recording of a 1080p monitor is recorded
# at 1080p rather than stretched.
args=()
if [ "$height" != "native" ] && [ "$height" -lt "$mh" ]; then
    w=$(( (height * mw / mh + 1) / 2 * 2 ))
    args+=(-s "${w}x${height}")
fi

case "$audio" in
    system) args+=(-a default_output -ac aac) ;;
    mic)    args+=(-a default_input -ac aac) ;;
    both)   args+=(-a "default_output|default_input" -ac aac) ;;
    none)   ;;
esac

if [ -z "$dir" ]; then
    dir="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")/Recordings"
fi
dir="${dir/#\~/$HOME}"
mkdir -p "$dir"
out="$dir/Recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
echo "$out"

exec gpu-screen-recorder \
    -w "$monitor" \
    -f "$fps" -fm cfr \
    -k "$codec" -q "$quality" \
    -cursor "$cursor" \
    -v no \
    "${args[@]}" \
    -o "$out"
