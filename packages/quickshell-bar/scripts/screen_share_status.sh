#!/usr/bin/env bash
set -o pipefail

/run/current-system/sw/bin/pw-dump 2>/dev/null | /run/current-system/sw/bin/jq -r '
  any(.[];
    .type == "PipeWire:Interface:Node" and
    ((.info.props["media.role"] // "") | ascii_downcase) == "screen"
  )
' 2>/dev/null || printf 'false\n'
