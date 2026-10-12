#!/usr/bin/env bash
set -u
identity="${1:-}"
desktop="${2:-}"
bus="${3:-}"
pid="$(sed -n 's/^.*\.instance\([0-9][0-9]*\)$/\1/p' <<<"$bus")"
base="$(sed 's/^org\.mpris\.MediaPlayer2\.//; s/\.instance[0-9][0-9]*$//' <<<"$bus")"
desktop-focus --pid "$pid" --app "$identity" --desktop "${desktop:-$base}"
