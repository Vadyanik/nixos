#!/usr/bin/env bash

set -euo pipefail

journalctl --list-boots --no-pager | awk '
    /^[[:space:]-]*[0-9]+/ { dates[$4] = 1 }
    END {
        for (date in dates) print date
    }
' | sort | while read -r date; do
    date -d "$date" +%s
done | sort -n | awk '
    NR == 1 { streak = 1; previous = $1; next }
    $1 - previous == 86400 { streak++ }
    $1 - previous != 86400 { streak = 1 }
    { previous = $1 }
    END { print streak }
'
