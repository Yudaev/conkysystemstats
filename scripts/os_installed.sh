#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

# Попытка 1: самая ранняя запись об установке в pacman.log
first=$({ zgrep -h "^\[[0-9-]\+ [0-9:]\+\] \[ALPM\] installed " /var/log/pacman.log* 2>/dev/null || true; } \
  | sed -E "s/^\[([0-9-]+) ([0-9:]+)\].*/\1 \2/" \
  | sort | head -n1)

# Попытка 2: самая старая запись в /var/lib/pacman/local
if [[ -z "${first}" ]]; then
  stamp=$(find /var/lib/pacman/local -type f -name desc -printf '%T@\n' 2>/dev/null | sort -n | head -n1 || true)
  if [[ -n "${stamp}" ]]; then
    first=$(date -d "@$stamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)
  fi
fi

if [[ -z "${first}" ]]; then
  echo "Installed: unknown"
  exit 0
fi

if ! first_ts=$(date -d "$first" +%s 2>/dev/null); then
  echo "Installed: $first"
  exit 0
fi

now_ts=$(date +%s)
diff=$(( now_ts - first_ts ))
(( diff < 0 )) && diff=0

days=$(( diff / 86400 ))
hrs=$(( (diff % 86400) / 3600 ))
mins=$(( (diff % 3600) / 60 ))
secs=$(( diff % 60 ))

parts=()
(( days > 0 )) && parts+=("${days}d")
# hrs > 0 )) && parts+=("${hrs}h")
#( mins > 0 )) && parts+=("${mins}m")
#( secs > 0 )) && parts+=("${secs}s")

if (( ${#parts[@]} == 0 )); then
  parts=("0s")
fi

elapsed=$(printf '%s ' "${parts[@]}")
elapsed=${elapsed%% }

printf "Installed: %s  (%s ago)\n" "$first" "$elapsed"
