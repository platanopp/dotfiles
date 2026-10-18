#!/usr/bin/env bash
wpctl status | sed -n '/Sinks:/,/Sources:/p' | grep -E '[0-9]+\.' | while read -r line; do
    is_default=0
    if [[ "$line" == *"*"* ]]; then
        is_default=1
    fi
    id=$(echo "$line" | grep -oE '[0-9]+\.' | head -1 | tr -d '.')
    name=$(echo "$line" | sed -E 's/\s*\[vol:.*//; s/^[^0-9]*[0-9]+\.\s*//; s/\s+$//')
    # "[vol: 0.47]" as a percentage, for the per-device levels.
    volume=$(echo "$line" | sed -nE 's/.*\[vol: ([0-9.]+).*/\1/p' | awk '{ printf "%d", $1 * 100 + 0.5 }')
    echo "${id}|${name}|${is_default}|${volume:-100}"
done
