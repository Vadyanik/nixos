#!/usr/bin/env bash

# ponytail: poll once per second instead of subscribing to D-Bus; use a persistent client only if this becomes measurable.
state_file="${XDG_RUNTIME_DIR:-/tmp}/waybar-mpris-player"

players() {
    busctl --user --no-pager --no-legend list | while read -r player _; do
        [[ $player == org.mpris.MediaPlayer2.* ]] && printf '%s\n' "$player"
    done
}

choose_player() {
    mapfile -t available < <(players)
    ((${#available[@]})) || return 1

    local selected=""
    [[ -r $state_file ]] && selected=$(<"$state_file")
    for player in "${available[@]}"; do
        [[ $player == "$selected" ]] && {
            printf '%s\n' "$player"
            return
        }
    done

    for player in "${available[@]}"; do
        status=$(busctl --user get-property "$player" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus --json=short 2>/dev/null | jq -r '.data // empty')
        [[ $status == Playing ]] && {
            printf '%s\n' "$player" > "$state_file"
            printf '%s\n' "$player"
            return
        }
    done

    printf '%s\n' "${available[0]}" > "$state_file"
    printf '%s\n' "${available[0]}"
}

switch_player() {
    mapfile -t available < <(players)
    ((${#available[@]})) || exit 0
    current=$(choose_player) || exit 0

    for i in "${!available[@]}"; do
        [[ ${available[i]} == "$current" ]] && break
    done
    if [[ $1 == next-player ]]; then
        i=$(((i + 1) % ${#available[@]}))
    else
        i=$(((i - 1 + ${#available[@]}) % ${#available[@]}))
    fi
    printf '%s\n' "${available[i]}" > "$state_file"
}

player=$(choose_player) || {
    jq -cn '{text: "", class: "stopped"}'
    exit 0
}

case ${1:-status} in
    next-player|previous-player)
        switch_player "$1"
        exit 0
        ;;
    toggle|next|previous)
        method=PlayPause
        [[ $1 == next ]] && method=Next
        [[ $1 == previous ]] && method=Previous
        busctl --user call "$player" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player "$method" >/dev/null
        exit 0
        ;;
esac

metadata=$(busctl --user get-property "$player" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata --json=short 2>/dev/null)
status=$(busctl --user get-property "$player" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus --json=short 2>/dev/null | jq -r '.data // "stopped"')
if [[ $status == Stopped ]]; then
    jq -cn '{text: "", class: "stopped"}'
    exit 0
fi
artist=$(jq -r '.data["xesam:artist"].data[0] // ""' <<< "$metadata")
title=$(jq -r '.data["xesam:title"].data // ""' <<< "$metadata")
album=$(jq -r '.data["xesam:album"].data // ""' <<< "$metadata")
url=$(jq -r '.data["xesam:url"].data // ""' <<< "$metadata")

case $url in
    *youtube.com*|*youtu.be*) icon="󰗃" ;;
    *)
        case $player in
            *spotify*) icon="" ;;
            *) icon="" ;;
        esac
        ;;
esac

track=$title
[[ -n $artist && -n $title ]] && track="$artist - $title"
[[ ${#track} -gt 32 ]] && track="${track:0:29}..."
jq -cn --arg text "$icon $track" --arg class "${status,,}" '{text: $text, class: $class}'
