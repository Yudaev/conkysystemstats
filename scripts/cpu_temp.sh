#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

declare -A temps
for hw in /sys/class/hwmon/hwmon*; do
  [[ -d "$hw" ]] || continue
  [[ -r "$hw/name" ]] || continue
  name=$(<"$hw/name")
  case "$name" in
    k10temp*|zenpower*|coretemp*|it87*|nct*|asusec*) ;;
    *) continue ;;
  esac

  for input in "$hw"/temp*_input; do
    [[ -r "$input" ]] || continue
    raw=$(<"$input")
    [[ "$raw" =~ ^[0-9]+$ ]] || continue

    label_file=${input/_input/_label}
    if [[ -r "$label_file" ]]; then
      label=$(<"$label_file")
    else
      label=$(basename "$input")
    fi
    label=${label//$'\n'/}
    label=${label// /}

    temps["$label"]=$(( raw / 1000 ))
  done
done

parts=()
for key in Tctl Tdie Packageid0; do
  if [[ -n "${temps[$key]:-}" ]]; then
    parts+=("$key ${temps[$key]}°C")
    break
  fi
done

declare -A ccd
for label in "${!temps[@]}"; do
  if [[ "$label" =~ ^Tccd([0-9]+)$ ]]; then
    idx=${BASH_REMATCH[1]}
    ccd[$idx]=${temps[$label]}
  fi
done

if (( ${#ccd[@]} > 0 )); then
  mapfile -t ccd_idx < <(printf '%s\n' "${!ccd[@]}" | sort -n)
  ccd_vals=()
  for idx in "${ccd_idx[@]}"; do
    ccd_vals+=("${ccd[$idx]}°C")
  done
  ccd_str=$( (IFS='/'; echo "${ccd_vals[*]}") )
  parts+=("CCD ${ccd_str}")
fi

if (( ${#parts[@]} == 0 )); then
  parts=("temp n/a")
fi

output=$( (
  IFS=' | '
  echo "${parts[*]}"
) )

echo "$output"
