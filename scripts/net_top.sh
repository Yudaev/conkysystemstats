#!/usr/bin/env bash
set -euo pipefail

command -v nethogs >/dev/null 2>&1 || { echo "-- nethogs не установлен --"; exit 0; }
LC_ALL=C

CACHE=${CACHE:-/tmp/systemstats_net_top.cache}
LOCKDIR="${CACHE}.lock"
MAX_AGE=${MAX_AGE:-3}
LINES=${LINES:-5}
placeholder=$(printf "%-20s [%7s] ↓ %7.1f ↑ %7.1f" "none" "-------" 0.0 0.0)

collect() {
  tmp=$(mktemp)
  trap 'rm -f "$tmp"; rmdir "$LOCKDIR" >/dev/null 2>&1 || true' EXIT

  mapfile -t lines < <(nethogs -t -d 1 -c 2 -a 2>/dev/null \
    | awk -F '\t' 'NF==3 && $1 ~ /\/[0-9]+\/[0-9]+$/ {print $1"\t"$2"\t"$3}') || true

  out=()
  for raw in "${lines[@]}"; do
    IFS=$'\t' read -r cmd sent recv <<<"$raw"
    [[ -z "$cmd" ]] && continue
    [[ "$cmd" =~ ^[Uu]nknown ]] && continue

    pid=${cmd%/*}
    pid=${pid##*/}
    name=$(ps -p "$pid" -o comm= 2>/dev/null | tr -d '\n')
    if [[ -z "$name" ]]; then
      cmd_no_uid=${cmd%/*}
      cmd_no_pid=${cmd_no_uid%/*}
      name=${cmd_no_pid##*/}
      name=${name%% *}
    fi
    [[ -z "$name" ]] && name="pid:$pid"

    sent_clean=$(awk -v v="${sent:-0}" 'BEGIN{gsub(/[^0-9.]/, "", v); if(v=="") v="0"; printf "%.3f", v+0}')
    recv_clean=$(awk -v v="${recv:-0}" 'BEGIN{gsub(/[^0-9.]/, "", v); if(v=="") v="0"; printf "%.3f", v+0}')
    total=$(awk -v s="$sent_clean" -v r="$recv_clean" 'BEGIN{printf "%.3f", s+r}')

    out+=( "$(printf "%012.3f\t%-20.20s\t%7d\t%.1f\t%.1f" "$total" "$name" "$pid" "$recv_clean" "$sent_clean")" )
  done

  mapfile -t top_lines < <(
    if (( ${#out[@]} > 0 )); then
      printf '%s\n' "${out[@]}" \
        | sort -r \
        | head -n "$LINES" \
        | awk -F'\t' '{ printf "%-20.20s [%7s] ↓ %7.1f ↑ %7.1f\n", $2, $3, $4, $5 }'
    fi
  )

  if (( ${#top_lines[@]} == 0 )); then
    top_lines=("$placeholder")
  fi

  while (( ${#top_lines[@]} < LINES )); do
    top_lines+=("$placeholder")
  done

  {
    printf '%s\n' "$(date +%s)"
    printf '%s\n' "${top_lines[@]}"
  } >"$tmp"

  mv "$tmp" "$CACHE"
}

print_cache() {
  tail -n +2 "$CACHE"
}

now=$(date +%s)
printed=false
if [[ -f "$CACHE" ]]; then
  read -r ts <"$CACHE" || ts=0
  if [[ "$ts" =~ ^[0-9]+$ ]]; then
    age=$(( now - ts ))
    print_cache
    printed=true
    if (( age > MAX_AGE )); then
      if mkdir "$LOCKDIR" 2>/dev/null; then
        ( collect ) &
      fi
    fi
  else
    rm -f "$CACHE"
  fi
fi

if ! $printed; then
  for (( i=0; i<LINES; i++ )); do
    echo "$placeholder"
  done
  if mkdir "$LOCKDIR" 2>/dev/null; then
    ( collect ) &
  fi
fi
