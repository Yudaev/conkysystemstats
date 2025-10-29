#!/usr/bin/env bash
set -euo pipefail

command -v nethogs >/dev/null 2>&1 || { echo "-- nethogs не установлен --"; exit 0; }
LC_ALL=C

CACHE=${CACHE:-/tmp/systemstats_net_top.cache}
LOCKDIR="${CACHE}.lock"
MAX_AGE=${MAX_AGE:-3}
LINES=${LINES:-5}
placeholder=$(printf "%-18s [%7s] ↓%s ↑%s" "none" "-------" "0 B/s" "0 B/s")

collect() {
  tmp=$(mktemp)
  trap 'rm -f "$tmp"; rmdir "$LOCKDIR" >/dev/null 2>&1 || true' EXIT

  mapfile -t lines < <(nethogs -t -d 1 -c 2 -a 2>/dev/null \
    | awk -F '\t' '
      BEGIN { refresh = 0 }
      /^Refreshing:/ { refresh++; next }
      function to_kib(raw, lower, num, unit) {
        lower = tolower(raw)
        if (match(lower, /-?[0-9]+(\.[0-9]+)?/)) {
          num = substr(lower, RSTART, RLENGTH) + 0
        } else {
          num = 0
        }
        if (match(lower, /(t|g|m|k)?i?b\/?s(ec)?/)) {
          unit = substr(lower, RSTART, RLENGTH)
        } else if (match(lower, /(t|g|m|k)?i?b/)) {
          unit = substr(lower, RSTART, RLENGTH)
        } else {
          unit = "kb/s"
        }
        if (unit ~ /^ti?b/) return num * 1024 * 1024 * 1024
        if (unit ~ /^gi?b/) return num * 1024 * 1024
        if (unit ~ /^mi?b/) return num * 1024
        if (unit ~ /^ki?b/) return num
        if (unit ~ /^b/)     return num / 1024
        return num
      }
      NF==3 && $1 ~ /\/[0-9]+\/[0-9]+$/ {
        sent = to_kib($2)
        recv = to_kib($3)
        printf "%s\t%.6f\t%.6f\t%d\n", $1, sent, recv, refresh
      }') || true

  last_refresh=-1
  for raw in "${lines[@]}"; do
    IFS=$'\t' read -r _cmd _sent _recv refresh <<<"$raw"
    [[ -z "${refresh:-}" ]] && continue
    (( refresh > last_refresh )) && last_refresh=$refresh
  done

  if (( last_refresh == -1 )); then
    lines=()
  fi

  declare -A recv_map=()
  declare -A sent_map=()
  declare -A name_map=()
  declare -A pid_map=()
  keys=()

  for raw in "${lines[@]}"; do
    IFS=$'\t' read -r cmd sent recv refresh <<<"$raw"
    (( refresh != last_refresh )) && continue
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

    key=$pid
    [[ -z "$key" ]] && key="$cmd"

    [[ -z "$pid" ]] && pid="-------"

    if [[ -z "${recv_map[$key]+_}" ]]; then
      keys+=("$key")
      recv_map[$key]=0
      sent_map[$key]=0
      name_map[$key]="$name"
      pid_map[$key]="$pid"
    else
      if [[ "${name_map[$key]}" == pid:* && "$name" != "${name_map[$key]}" ]]; then
        name_map[$key]="$name"
      fi
      if [[ "${pid_map[$key]}" == "-------" && "$pid" != "-------" ]]; then
        pid_map[$key]="$pid"
      fi
    fi

    recv_map[$key]=$(awk -v a="${recv_map[$key]}" -v b="${recv:-0}" 'BEGIN{printf "%.6f", a + b}')
    sent_map[$key]=$(awk -v a="${sent_map[$key]}" -v b="${sent:-0}" 'BEGIN{printf "%.6f", a + b}')
  done

  out=()
  for key in "${keys[@]}"; do
    recv_clean=${recv_map[$key]:-0}
    sent_clean=${sent_map[$key]:-0}
    total=$(awk -v s="$sent_clean" -v r="$recv_clean" 'BEGIN{printf "%.6f", s+r}')
    out+=( "$(printf "%018.6f\t%-18.18s\t%7s\t%.6f\t%.6f" "$total" "${name_map[$key]}" "${pid_map[$key]}" "$recv_clean" "$sent_clean")" )
  done

  mapfile -t top_lines < <(
    if (( ${#out[@]} > 0 )); then
      printf '%s\n' "${out[@]}" \
        | sort -r \
        | head -n "$LINES" \
        | awk -F'\t' '
            function human(kib) {
              if (kib >= 1048576) {
                return sprintf("%.1f GiB/s", kib / 1048576)
              } else if (kib >= 1024) {
                return sprintf("%.1f MiB/s", kib / 1024)
              } else if (kib >= 1) {
                return sprintf("%.1f KiB/s", kib)
              } else if (kib > 0) {
                return sprintf("%.0f B/s", kib * 1024)
              }
              return "0 B/s"
            }
            {
              recv=human($4)
              sent=human($5)
              printf "%-18.18s [%7s] ↓%s ↑%s\n", $2, $3, recv, sent
            }'
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
