#!/usr/bin/env bash
set -euo pipefail

LINES=${LINES:-5}
placeholder=$(printf "%-20s [%7s]  SM:%3d%%  MEM:%3d%%" "none" "-------" 0 0)

if ! command -v nvidia-smi >/dev/null 2>&1; then
  for (( i=0; i<LINES; i++ )); do
    echo "$placeholder"
  done
  exit 0
fi

mapfile -t rows < <(nvidia-smi pmon -c 1 2>/dev/null | awk 'NR>2 && $2 ~ /^[0-9]+$/ {print $2, $4, $5}')

tmp=()
for line in "${rows[@]}"; do
  pid=$(awk '{print $1}' <<<"$line")
  sm=$(awk '{print $2}' <<<"$line")
  mem=$(awk '{print $3}' <<<"$line")
  [[ "$sm" =~ ^[0-9]+$ ]]  || sm=0
  [[ "$mem" =~ ^[0-9]+$ ]] || mem=0
  name=$(ps -p "$pid" -o comm= 2>/dev/null | tr -d '\n')
  [ -z "$name" ] && name="pid:$pid"
  tmp+=( "$(printf "%d\t%d\t%s\t%d" "$sm" "$mem" "$name" "$pid")" )
done

if (( ${#tmp[@]} > 0 )); then
  mapfile -t lines < <(printf "%s\n" "${tmp[@]}" \
    | sort -nr -k1,1 \
    | head -n "$LINES" \
    | awk -F'\t' '{printf "%-20.20s [%7d]  SM:%3d%%  MEM:%3d%%\n", $3, $4, $1, $2}')
else
  lines=()
fi

while (( ${#lines[@]} < LINES )); do
  lines+=("$placeholder")
done

printf "%s\n" "${lines[@]}"
