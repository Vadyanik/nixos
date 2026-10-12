#!/usr/bin/env bash
set -uo pipefail

device_line="$(bluetoothctl devices Connected 2>/dev/null | sed -n 's/^Device //p' | head -n 1)"
if [[ -z "$device_line" ]]; then
    printf '{"connected":false,"address":"","name":"","battery":null}\n'
    exit 0
fi

address="${device_line%% *}"
info="$(bluetoothctl info "$address" 2>/dev/null || true)"
name="$(sed -nE 's/^[[:space:]]*(Alias|Name):[[:space:]]*//p' <<<"$info" | head -n 1)"
battery="$(sed -nE 's/^[[:space:]]*Battery Percentage:.*\(([0-9]{1,3})\).*$/\1/p' <<<"$info" | head -n 1)"
if [[ -z "$battery" ]]; then
    battery="$(sed -nE 's/^[[:space:]]*Battery Percentage:[[:space:]]*([0-9]{1,3})%?$/\1/p' <<<"$info" | head -n 1)"
fi
if [[ ! "$battery" =~ ^[0-9]{1,3}$ ]] || (( battery > 100 )); then battery=""; fi

python3 - "$name" "$battery" "$address" <<'PY'
import json, sys
print(json.dumps({"connected": True, "address": sys.argv[3], "name": sys.argv[1] or "Bluetooth device", "battery": int(sys.argv[2]) if sys.argv[2] else None}, ensure_ascii=False))
PY
