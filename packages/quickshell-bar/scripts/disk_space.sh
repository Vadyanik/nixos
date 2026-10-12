#!/usr/bin/env bash

set -euo pipefail

state_file="${XDG_RUNTIME_DIR:-/tmp}/waybar-disk-path"
signal=8

current_path() {
    local now saved_minute saved_path next_path
    now="$(date +%s)"
    now=$((now / 60))

    if [[ -f "$state_file" ]]; then
        read -r saved_minute saved_path < "$state_file" || true
    else
        saved_minute="$now"
        saved_path="/home"
    fi

    if [[ "$saved_path" != "/" && "$saved_path" != "/home" ]]; then
        saved_path="/home"
    fi

    if [[ "${saved_minute:-}" != "$now" ]]; then
        if [[ "$saved_path" == "/home" ]]; then
            next_path="/"
        else
            next_path="/home"
        fi

        printf '%s %s\n' "$now" "$next_path" > "$state_file"
        printf '%s' "$next_path"
        return
    fi

    printf '%s' "$saved_path"
}

toggle_path() {
    local now path
    now="$(date +%s)"
    now=$((now / 60))
    path="$(current_path)"

    if [[ "$path" == "/home" ]]; then
        printf '%s /\n' "$now" > "$state_file"
    else
        printf '%s /home\n' "$now" > "$state_file"
    fi

    quickshell ipc -c bar call bar refresh disk >/dev/null 2>&1 || true
}

print_status() {
    local path avail used percent total used_percent free_percent bucket tooltip
    path="$(current_path)"

    read -r total used avail percent < <(df -h --output=size,used,avail,pcent "$path" | awk 'NR == 2 { print $1, $2, $3, $4 }')
    used_percent="${percent%\%}"
    free_percent=$((100 - used_percent))
    if ((free_percent >= 30)); then
        bucket=ok
    elif ((free_percent >= 20)); then
        bucket=warn
    elif ((free_percent >= 10)); then
        bucket=low
    else
        bucket=critical
    fi
    tooltip="$path: $avail free of $total, $used used ($percent used, $free_percent% free)"

    printf '{"text":"%s %s","tooltip":"%s","class":"%s"}\n' \
        "$path" "$avail" "$tooltip" "$bucket"
}

print_both() {
    df -h --output=target,size,used,avail,pcent / /home | tail -n +2 | jq -Rn '
        [inputs | split(" ") | map(select(length > 0))
         | {path: .[0], total: .[1], used: .[2], free: .[3], usedPercent: (.[4] | rtrimstr("%") | tonumber), freePercent: (100 - (.[4] | rtrimstr("%") | tonumber))}]
        | {mounts: .}'
}

case "${1:-status}" in
    toggle)
        toggle_path
        ;;
    both)
        print_both
        ;;
    status)
        print_status
        ;;
    *)
        printf 'Usage: %s [status|toggle]\n' "$0" >&2
        exit 2
        ;;
esac
