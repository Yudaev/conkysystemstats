#!/usr/bin/env bash
# Common helpers for GPU scripts (vendor detection, sysfs lookups).
# shellcheck shell=bash

detect_gpu_vendor() {
  local vendor_file vendor cards=()

  if [[ -n "${GPU_VENDOR:-}" ]]; then
    printf '%s\n' "${GPU_VENDOR,,}"
    return 0
  fi
 
  shopt -s nullglob
  cards=(/sys/class/drm/card?)
  shopt -u nullglob

  for card in "${cards[@]}"; do
    vendor_file="$card/device/vendor"
    [[ -r "$vendor_file" ]] || continue
    read -r vendor <"$vendor_file"
    case "${vendor,,}" in
      0x10de) printf 'nvidia\n'; return 0 ;;
      0x1002) printf 'amd\n'; return 0 ;;
    esac
  done

  if command -v nvidia-smi >/dev/null 2>&1; then
    printf 'nvidia\n'
    return 0
  fi

  if command -v amd-smi >/dev/null 2>&1 || command -v rocm-smi >/dev/null 2>&1; then
    printf 'amd\n'
    return 0
  fi

  printf 'unknown\n'
  return 0
}

select_gpu_card() {
  local target vendor card cards=() override vendor_file

  target=${1:-}
  if [[ -z "$target" || "$target" == "auto" ]]; then
    target=$(detect_gpu_vendor)
  else
    target=${target,,}
  fi

  override=${GPU_CARD:-${GPU_DRM_CARD:-}}
  if [[ -n "$override" ]]; then
    if [[ -d "/sys/class/drm/$override/device" ]]; then
      printf '/sys/class/drm/%s\n' "$override"
      return 0
    fi
  fi

  shopt -s nullglob
  cards=(/sys/class/drm/card?)
  shopt -u nullglob

  for card in "${cards[@]}"; do
    [[ -d "$card/device" ]] || continue
    vendor_file="$card/device/vendor"
    if [[ ! -r "$vendor_file" ]]; then
      continue
    fi
    read -r vendor <"$vendor_file"
    vendor=${vendor,,}
    case "$target" in
      nvidia)
        [[ "$vendor" == "0x10de" ]] && { printf '%s\n' "$card"; return 0; }
        ;;
      amd)
        [[ "$vendor" == "0x1002" ]] && { printf '%s\n' "$card"; return 0; }
        ;;
      *)
        printf '%s\n' "$card"
        return 0
        ;;
    esac
  done

  return 1
}

find_hwmon_dir() {
  local card hwmons=() hwmon name

  card=$1
  [[ -n "$card" ]] || return 1

  shopt -s nullglob
  hwmons=("$card"/device/hwmon/hwmon*)
  shopt -u nullglob

  for hwmon in "${hwmons[@]}"; do
    [[ -d "$hwmon" ]] || continue
    if [[ -r "$hwmon/name" ]]; then
      read -r name <"$hwmon/name"
      name=${name,,}
      case "$name" in
        amdgpu*|nvidia*)
          printf '%s\n' "$hwmon"
          return 0
          ;;
      esac
    fi
  done

  if [[ -n "${hwmons[*]}" ]]; then
    printf '%s\n' "${hwmons[0]}"
    return 0
  fi

  return 1
}
