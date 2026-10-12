#!/nix/store/svx59425zxp552p2b8gm11qj5r09b56i-bash-5.3p15/bin/bash
set -o errexit
set -o nounset
set -o pipefail

export PATH="$PATH"

#!/usr/bin/env bash
set -euo pipefail

runtime_dir="${STT_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}/stt-${UID}}"
status_file="${runtime_dir}/status"
status=""
owner=""
started=""
if [[ -r "${status_file}" ]]; then
  read -r status owner started < "${status_file}" || true
  if [[ ! "${owner}" =~ ^[0-9]+$ ]] || ! kill -0 "${owner}" 2>/dev/null; then
    status=""
  fi
fi

case "${status}" in
  recording) printf '%s\n' '{"text":"REC","tooltip":"Voice input: recording","class":"recording"}' ;;
  transcribing)
    elapsed=0
    [[ "${started}" =~ ^[0-9]+$ ]] && elapsed=$(( $(date +%s) - started ))
    printf '{"text":"ASR %ss","tooltip":"Voice input: transcribing for %s seconds","class":"transcribing"}\n' "${elapsed}" "${elapsed}"
    ;;
  *) printf '%s\n' '{"text":"","class":"idle"}' ;;
esac

