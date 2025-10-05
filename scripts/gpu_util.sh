#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

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
