#!/usr/bin/env bash
# Records a monitor to ~/Vídeos/Recordings, until it is sent SIGINT.
#
#   screen_record.sh [MONITOR]
#
# The monitor in use when none is named. Prints the file it writes to as its
# first line, then becomes the recorder (exec), so the SIGINT the shell sends
# to stop it reaches gpu-screen-recorder itself -- which is what makes it
# finish the file properly.
#
# gpu-screen-recorder, not wf-recorder or OBS: it encodes on the GPU (NVENC
# on this RTX 3060), so a recording costs next to no CPU and nothing a game
# would notice. Settings, for clips that play anywhere and edit cleanly:
#
#   1080p       -s 1920x1080: the 1440p monitor is scaled down to it, the
#               1080p one recorded as it is
#   60 fps      -f 60, constant (-fm cfr): editors and phones expect a steady
#               rate, which a variable one is not
#   MP4, H.264  the format that opens everywhere -- Discord, WhatsApp, any
#               editor -- at very high quality
#   AAC audio   what the computer is playing (default_output)
set -euo pipefail

monitor="${1:-}"
if [ -z "$monitor" ]; then
    monitor=$(hyprctl monitors -j | python3 -c "import json,sys; print(next((m['name'] for m in json.load(sys.stdin) if m['focused']), ''))")
fi

dir="$(xdg-user-dir VIDEOS 2>/dev/null || echo "$HOME/Videos")/Recordings"
mkdir -p "$dir"
out="$dir/Recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
echo "$out"

exec gpu-screen-recorder \
    -w "$monitor" \
    -s 1920x1080 \
    -f 60 -fm cfr \
    -k h264 -q very_high \
    -a default_output -ac aac \
    -cursor yes \
    -v no \
    -o "$out"
