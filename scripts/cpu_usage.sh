#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
prev_idle=$((idle + iowait))

sleep 0.3

read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
new_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
new_idle=$((idle + iowait))

d_total=$(( new_total - prev_total ))
d_idle=$(( new_idle - prev_idle ))

if (( d_total <= 0 )); then
  echo 0
  exit 0
fi

usage=$(( (100 * (d_total - d_idle)) / d_total ))
(( usage < 0 )) && usage=0
(( usage > 100 )) && usage=100

echo "$usage"
