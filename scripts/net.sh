#!/usr/bin/env bash
set -euo pipefail
LC_ALL=C

iface="$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -z "${iface:-}" ] && iface="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1)"
[ -z "${iface:-}" ] && { echo "NET: интерфейс не найден"; exit 0; }

ip4=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
[ -z "${ip4:-}" ] && ip4="n/a"
ssid=""; command -v iwgetid >/dev/null 2>&1 && ssid="$(iwgetid -r 2>/dev/null || true)"

rx1=$(< /sys/class/net/"$iface"/statistics/rx_bytes)
tx1=$(< /sys/class/net/"$iface"/statistics/tx_bytes)
sleep 1
rx2=$(< /sys/class/net/"$iface"/statistics/rx_bytes)
tx2=$(< /sys/class/net/"$iface"/statistics/tx_bytes)

dr=$(( rx2 - rx1 )) ; dt=$(( tx2 - tx1 ))

human() {
  local b=$1 fmt val
  if   [ "$b" -ge 1073741824 ]; then
    val=$(awk -v v="$b" 'BEGIN{printf "%.1f", v/1073741824}')
    fmt="GiB/s"
  elif [ "$b" -ge 1048576 ]; then
    val=$(awk -v v="$b" 'BEGIN{printf "%.1f", v/1048576}')
    fmt="MiB/s"
  elif [ "$b" -ge 1024 ]; then
    val=$(awk -v v="$b" 'BEGIN{printf "%.1f", v/1024}')
    fmt="KiB/s"
  else
    val=$b
    fmt="B/s"
  fi
  printf "%s %s" "$val" "$fmt"
}

total_rx=$(< /sys/class/net/"$iface"/statistics/rx_bytes)
total_tx=$(< /sys/class/net/"$iface"/statistics/tx_bytes)
tot_rx_h=$(awk -v v="$total_rx" 'BEGIN{printf "%.1f", v/1073741824}')
tot_tx_h=$(awk -v v="$total_tx" 'BEGIN{printf "%.1f", v/1073741824}')

printf "IF: %-6s IP:%-15s%s\n" "$iface" "$ip4" "${ssid:+ SSID:$ssid}"
printf "↓ %-11s ↑ %-11s\n" "$(human "$dr")" "$(human "$dt")"
printf "Tot↓ %5sG  Tot↑ %5sG\n" "$tot_rx_h" "$tot_tx_h"
