#!/bin/bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
M1DDC="$DIR/m1ddc"
LOG="$DIR/mateview-brightness.log"
DISPLAYS="MateView:45:20 U27U2D:25:0"

now_min=$((10#$(date +%H) * 60 + 10#$(date +%M)))
list=$("$M1DDC" display list 2>/dev/null)
for entry in $DISPLAYS; do
    name="${entry%%:*}"
    rest="${entry#*:}"
    day="${rest%%:*}"
    night="${rest##*:}"
    if (( now_min < 450 || now_min >= 1140 )); then
        target=$night
    elif (( now_min <= 720 )); then
        target=$day
    else
        target=$(( day - (now_min - 720) * (day - night) / 420 ))
    fi
    num=$(echo "$list" | awk -v n="$name" '$3 == n {print $1}')
    if [[ -z "$num" ]]; then
        echo "$(date '+%F %T') $name not found, skip" >> "$LOG"
        continue
    fi
    cur=$("$M1DDC" display "$num" get luminance 2>/dev/null)
    [[ "$cur" =~ ^[0-9]+$ ]] || continue
    if [[ "$cur" != "$target" ]]; then
        if "$M1DDC" display "$num" set luminance "$target" 2>/dev/null; then
            echo "$(date '+%F %T') $name brightness $cur -> $target" >> "$LOG"
        else
            echo "$(date '+%F %T') $name set luminance failed (target=$target)" >> "$LOG"
        fi
    fi
done
exit 0
