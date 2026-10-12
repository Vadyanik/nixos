#!/usr/bin/env bash

set -o pipefail

state_file="${XDG_RUNTIME_DIR:-/tmp}/waybar-codex-usage-mode"
cache_file="${XDG_RUNTIME_DIR:-/tmp}/waybar-codex-usage.json"
lock_file="${XDG_RUNTIME_DIR:-/tmp}/waybar-codex-usage.fetch.lock"
log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/waybar"
log_file="$log_dir/codex_usage.csv"
signal=9

time_until() {
    local seconds=$(( $1 - $(date +%s) ))
    ((seconds < 0)) && seconds=0
    if [[ "${2:-}" == "hours" ]]; then
        printf '%02dh %02dm' "$((seconds / 3600))" "$((seconds % 3600 / 60))"
    else
        printf '%dd %02dh %02dm' "$((seconds / 86400))" "$((seconds % 86400 / 3600))" "$((seconds % 3600 / 60))"
    fi
}

criticality() {
    local data="$1" now pace_result

    now="$(date +%s)"
    pace_result="$(python3 "$(dirname "${BASH_SOURCE[0]}")/codex_pace.py" "$log_file" "$data" "$now" 2>/dev/null)" || pace_result='{"five":"N/A","weekly":"N/A"}'
    jq -cn --argjson pace "$pace_result" --argjson limits "$data" --argjson now "$now" '
        def assess($duration; $name):
            ([$limits.primary, $limits.secondary]
             | map(select(. != null and .windowDurationMins == $duration))
             | .[0]) as $limit
            | if $limit == null then null else
                (($limit.resetsAt // $now) - $now) as $seconds
                | (if $seconds <= 0 then 999 else
                    ((100 - ($limit.usedPercent // 0)) / 100) / ($seconds / ($duration * 60))
                   end) as $score
                | (if $score >= 1.50 then {class: "excess", rank: 0}
                   elif $score >= 1.25 then {class: "surplus", rank: 0}
                   elif $score >= 0.90 then {class: "full", rank: 1}
                   elif $score >= 0.75 then {class: "warn", rank: 2}
                   elif $score >= 0.50 then {class: "low", rank: 3}
                   else {class: "critical", rank: 4}
                   end) + {name: $name, score: $score,
                           normal_at: (if $score >= 0.90 then null
                                       elif ($limit.usedPercent // 0) >= 100 then $limit.resetsAt
                                       else ($limit.resetsAt - ((100 - ($limit.usedPercent // 0)) / 100) * $duration * 60 / 0.90 | ceil)
                                       end)}
              end;
        [assess(300; "5h"), assess(10080; "Weekly")] | map(select(. != null)) as $results
        | if ($results | length) != 2 then
            {class: "error", tooltip: "Codex limits are unavailable."}
          else
            {
                five_class: $results[0].class,
                weekly_class: $results[1].class,
                tooltip: ($results | map("\(.name): \(.score * 100 | round / 100)" +
                    (if .normal_at == null then "" else " → \(.normal_at / 60 | ceil * 60 | strflocaltime("%d.%m %H:%M"))" end) +
                    (if .name == "5h" then "\n  Pace (1h): \($pace.five)"
                     else "\n  Pace (24h): \($pace.weekly)" end)) | join("\n"))
              }
          end
    ' || jq -nc '{class: "error", tooltip: "Could not calculate limit criticality."}'
}

fetch() (
    local data previous now

    # Kernel-managed lock: released even when a refresh is interrupted.
    exec 9> "$lock_file"
    flock -n 9 || return 0
    now="$(date +%s)"
    if [[ -r "$cache_file" ]] && (( now - $(stat -c %Y "$cache_file") < 20 )); then
        return 0
    fi
    data="$({
        printf '%s\n' '{"id":1,"method":"initialize","params":{"clientInfo":{"name":"waybar","version":"1"}}}'
        sleep 1
        printf '%s\n' '{"method":"initialized"}'
        sleep 1
        printf '%s\n' '{"id":2,"method":"account/rateLimits/read","params":null}'
        sleep 5
    } | timeout 10s codex app-server --stdio 2>/dev/null | jq -c 'select(.id == 2) | .result.rateLimits' 2>/dev/null)" || true

    if ! jq -e '
        [.primary, .secondary] | sort_by(.windowDurationMins)
        | map(.windowDurationMins) == [300, 10080]
    ' <<< "$data" >/dev/null 2>&1; then
        printf '%s\n' 'Codex limit refresh failed; keeping the previous snapshot.' >&2
        return 1
    fi
    previous='{}'
    [[ -r "$cache_file" ]] && previous="$(< "$cache_file")"
    now="$(date +%s)"
    python3 "$(dirname "${BASH_SOURCE[0]}")/codex_history.py" "$log_file" "$data" "$previous" "$now" || return 1
    printf '%s\n' "$data" > "$cache_file.tmp"
    mv "$cache_file.tmp" "$cache_file"
    quickshell ipc -c bar call bar refresh codex >/dev/null 2>&1 || true
)

render() {
    local data="$1" window="${2:-five}"
    local used minutes reset remaining
    local switched mode
    local five_remaining="" weekly_remaining=""
    local five_reset="" weekly_reset=""
    local five_text weekly_text text class tooltip criticality_result

    mode="limits"

    if [[ -r "$state_file" ]]; then
        read -r switched < "$state_file" || true

        if [[ "$switched" =~ ^[0-9]+$ ]] &&
           (( $(date +%s) - switched < 30 )); then
            mode="reset"
        else
            rm -f "$state_file"
        fi
    fi

    if [[ -z "$data" || "$data" == "null" ]]; then
        printf '%s\n' '{"text":"?","class":"error","tooltip":"Codex limits are unavailable."}'
        return
    fi

    while IFS=$'\t' read -r used minutes reset; do
        [[ -n "$used" ]] || continue

        remaining=$((100 - used))

        case "$minutes" in
            300)
                five_remaining="$remaining"

                if [[ "$reset" =~ ^[0-9]+$ ]]; then
                    five_reset="$(time_until "$reset" hours)"
                fi
                ;;

            10080)
                weekly_remaining="$remaining"

                if [[ "$reset" =~ ^[0-9]+$ ]]; then
                    weekly_reset="$(time_until "$reset")"
                fi
                ;;
        esac

    done < <(
        jq -r '
            [.primary, .secondary][]?
            | select(.)
            | "\(.usedPercent // 0)\t\(.windowDurationMins // 0)\t\(.resetsAt // 0)"
        ' <<< "$data"
    )

    criticality_result="$(criticality "$data")"
    class="$(jq -r --arg window "$window" '.[$window + "_class"] // .class // "error"' <<< "$criticality_result")"
    tooltip="$(jq -r '.tooltip' <<< "$criticality_result")"
    if [[ "$mode" == "reset" ]]; then
        five_text="${five_reset:-?}"
        weekly_text="${weekly_reset:-?}"
    else
        five_text="${five_remaining:-?}%"
        weekly_text="${weekly_remaining:-?}%"
    fi
    if [[ "$window" == "weekly" ]]; then
        text="$weekly_text"
    else
        text="$five_text"
    fi

    jq -nc \
        --arg text "$text" \
        --arg class "$class" \
        --arg tooltip "$tooltip" \
        '{text: $text, class: $class, tooltip: $tooltip}'
}

status() {
    local data=""
    [[ -r "$cache_file" ]] && data="$(< "$cache_file")"
    render "$data" "${1:-five}"
}

toggle() {
    local switched now
    systemctl --user start --no-block quickshell-codex-usage.service 2>/dev/null || true
    now="$(date +%s)"
    if [[ -r "$state_file" ]]; then
        read -r switched < "$state_file" || true
    fi
    if [[ "$switched" =~ ^[0-9]+$ ]] && (( now - switched < 30 )); then
        rm -f "$state_file"
    else
        printf '%s\n' "$now" > "$state_file"
        (sleep 30; quickshell ipc -c bar call bar refresh codex >/dev/null 2>&1 || true) >/dev/null 2>&1 &
    fi
    quickshell ipc -c bar call bar refresh codex >/dev/null 2>&1 || true
}

# Allow the small regression check to source the shared calculations.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return
fi

case "${1:-status}" in
    toggle)
        toggle
        ;;
    status)
        case "${2:-five}" in
            five|weekly) status "${2:-five}" ;;
            *) exit 2 ;;
        esac
        ;;
    fetch)
        fetch
        ;;
    *)
        printf 'Usage: %s [status [five|weekly]|toggle|fetch]\n' "$0" >&2
        exit 2
        ;;
esac
