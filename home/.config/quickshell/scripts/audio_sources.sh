#!/usr/bin/env bash
# The capture devices wpctl knows, one per line: id|name|default(1/0).
# Same shape as audio_sinks.sh, for the other half of the device list.
wpctl status | sed -n '/Sources:/,/Filters:/p' | grep -E '[0-9]+\.' | while read -r line; do
    is_default=0
    [[ "$line" == *"*"* ]] && is_default=1
    id=$(echo "$line" | grep -oE '[0-9]+\.' | head -1 | tr -d '.')
    name=$(echo "$line" | sed -E 's/\s*\[vol:.*//; s/^[^0-9]*[0-9]+\.\s*//; s/\s+$//')
    echo "${id}|${name}|${is_default}"
done
