#!/usr/bin/env bash
set -eu
LC_ALL=C

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
COMMON_LIB="$SCRIPT_DIR/lib/gpu_common.sh"

if [[ -r "$COMMON_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$COMMON_LIB"
else
  echo 0
  exit 0
fi

vendor=$(detect_gpu_vendor)

case "$vendor" in
  nvidia)
    if ! command -v nvidia-smi >/dev/null 2>&1; then
      echo 0
      exit 0
    fi
    util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')
    if [[ "$util" =~ ^[0-9]+$ ]]; then
      echo "$util"
    else
      echo 0
    fi
    ;;
  amd)
    card=$(select_gpu_card amd) || { echo 0; exit 0; }
    if [[ -r "$card/device/gpu_busy_percent" ]]; then
      util=$(<"$card/device/gpu_busy_percent")
      if [[ "$util" =~ ^[0-9]+$ ]]; then
        echo "$util"
      else
        echo 0
      fi
    else
      echo 0
    fi
    ;;
  *)
    echo 0
    ;;
esac
