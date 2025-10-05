#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

memtotal=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
memavail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)

if [[ -z "$memtotal" || -z "$memavail" || $memtotal -eq 0 ]]; then
  echo 0
  exit 0
fi

used=$(( memtotal - memavail ))
usage=$(( used * 100 / memtotal ))

echo "$usage"
