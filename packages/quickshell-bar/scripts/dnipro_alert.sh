#!/usr/bin/env bash

set -u

day="$(date +%u)"
hour="$(date +%H)"
minute="$(date +%M)"
now=$((10#$hour * 60 + 10#$minute))

case "$day" in
    1) start=480; end=780 ;;
    2|3|4) start=480; end=875 ;;
    5) start=510; end=875 ;;
    *) start=0; end=0 ;;
esac

if ((now < start || now >= end)); then
    printf '{"text":""}\n'
    exit
fi

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar"
[[ -r "$config_dir/.env" ]] && source "$config_dir/.env"
token="${ALERTS_API:-}"

if [[ -z "$token" ]]; then
    printf '{"text":" ","tooltip":"ALERTS_API не задано у .env","class":"error"}\n'
    exit
fi

response="$(curl --fail --silent --show-error --max-time 10 \
    -H "Authorization: Bearer $token" \
    https://api.alerts.in.ua/v1/alerts/active.json 2>/dev/null)" || response=""

if [[ -z "$response" ]] || ! jq -e '.alerts | arrays' >/dev/null 2>&1 <<< "$response"; then
    printf '{"text":" ","tooltip":"Помилка оновлення alerts.in.ua","class":"error"}\n'
elif jq -e '.alerts[] | select(
    (.location_uid == "9" or .location_uid == "44" or .location_raion == "Дніпровський район")
)' >/dev/null <<< "$response"; then
    printf '{"text":" ","tooltip":"У Дніпровському районі є активна загроза","class":"alert"}\n'
else
    printf '{"text":" ","tooltip":"У Дніпровському районі активних загроз немає","class":"safe"}\n'
fi
