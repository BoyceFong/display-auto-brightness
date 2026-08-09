#!/bin/bash
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
M1DDC="$DIR/m1ddc"
LOG="$DIR/mateview-brightness.log"
STATE="$DIR/mateview-brightness.state"
DISPLAYS="MateView:45:20 U27U2D:25:0"
CONFIRM=3
TODAY=$(date '+%Y-%m-%d')

now_min=$((10#$(date +%H) * 60 + 10#$(date +%M)))
list=$("$M1DDC" display list 2>/dev/null)

# State file format: name|date|last_set|paused|anomaly_count
get_state() { grep "^$1|" "$STATE" 2>/dev/null | head -1 | cut -d'|' -f"$2"; }
save_state() {
    grep -v "^$1|" "$STATE" 2>/dev/null > "$STATE.tmp"
    echo "$1|$2|$3|$4|$5" >> "$STATE.tmp"
    mv "$STATE.tmp" "$STATE"
}

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

    # Read state
    st_date=$(get_state "$name" 2)
    st_last=$(get_state "$name" 3)
    st_paused=$(get_state "$name" 4)
    st_anom=$(get_state "$name" 5)
    [[ -z "$st_last" ]] && st_last=-1
    [[ -z "$st_paused" ]] && st_paused=0
    [[ -z "$st_anom" ]] && st_anom=0

    # Daily reset
    if [[ "$st_date" != "$TODAY" ]]; then
        st_date="$TODAY"
        st_paused=0
        st_last=-1
        st_anom=0
    fi

    # Find display
    num=$(echo "$list" | awk -v n="$name" '$3 == n {print $1}')
    if [[ -z "$num" ]]; then
        st_last=-1
        save_state "$name" "$st_date" "$st_last" "$st_paused" "$st_anom"
        continue
    fi

    # Paused — skip
    if [[ "$st_paused" == "1" ]]; then
        continue
    fi

    # Read current brightness
    cur=$("$M1DDC" display "$num" get luminance 2>/dev/null)
    [[ "$cur" =~ ^[0-9]+$ ]] || continue

    if [[ "$st_last" == "-1" ]]; then
        # First run of day or after reconnect: sync to target
        if [[ "$cur" != "$target" ]]; then
            if "$M1DDC" display "$num" set luminance "$target" 2>/dev/null; then
                echo "$(date '+%F %T') $name brightness $cur -> $target" >> "$LOG"
            fi
        fi
        st_last=$target
        st_anom=0
    elif [[ "$cur" == "$target" ]]; then
        st_last=$cur
        st_anom=0
    elif [[ "$cur" == "$st_last" ]]; then
        # Target changed (transition period), normal update
        if "$M1DDC" display "$num" set luminance "$target" 2>/dev/null; then
            echo "$(date '+%F %T') $name brightness $cur -> $target" >> "$LOG"
        fi
        st_last=$target
        st_anom=0
    else
        # Value matches neither target nor last-set: manual adjustment or a
        # transient DDC read glitch. Require CONFIRM consecutive ticks before
        # pausing, so a single glitch never pauses a display.
        st_anom=$((st_anom + 1))
        if (( st_anom >= CONFIRM )); then
            st_paused=1
            echo "$(date '+%F %T') $name manual adjustment detected ($cur, target $target, confirmed $st_anom ticks), paused until tomorrow or restart" >> "$LOG"
        fi
    fi

    save_state "$name" "$st_date" "$st_last" "$st_paused" "$st_anom"
done
exit 0
