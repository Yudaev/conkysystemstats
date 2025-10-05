#!/usr/bin/env bash
# NVIDIA подробная сводка (util, mem, clk, fan, power, temp)
mode=${1:-all}

if ! command -v nvidia-smi >/dev/null 2>&1; then
  if [[ "$mode" != "footer" ]]; then
    echo "GPU: NVIDIA не обнаружена (nvidia-smi нет)"
  fi
  exit 0
fi

# Основные метрики
IFS=',' read -r util_g temp mem_used mem_total pwr fan clk_sm clk_mem < <(
  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,fan.speed,clocks.sm,clocks.mem \
             --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' %'
)

# Защита от пустых значений
util_g=${util_g:-0}; temp=${temp:-0}; mem_used=${mem_used:-0}; mem_total=${mem_total:-0}
pwr=${pwr:-0}; fan=${fan:-0}; clk_sm=${clk_sm:-0}; clk_mem=${clk_mem:-0}

hotspot=""
if hotspot_raw=$(nvidia-smi --query-gpu=temperature.hotspot --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' %'); then
  if [[ "$hotspot_raw" =~ ^[0-9]+$ ]]; then
    hotspot="$hotspot_raw"
  fi
fi

if [[ -z "$hotspot" ]]; then
  hotspot=$(nvidia-smi -q -d TEMPERATURE 2>/dev/null | awk -F':' '
    /GPU Hotspot Temp/ { gsub(/[^0-9]/, "", $2); if($2!="") { print $2; exit } }
  ')
fi

if [[ "$hotspot" =~ ^[0-9]+$ ]]; then
  hotspot_disp="${hotspot}°C"
else
  hotspot_disp="${temp}°C"
fi

printf -v util_str "%d%%" "${util_g:-0}"

line1="\${font Ubuntu:bold:size=11}GPU\${font} ${util_str}"
line1+="\${alignr}Temp: ${temp}°C  Hotspot: ${hotspot_disp}  Fan: ${fan}%"

line3="Clocks: SM ${clk_sm} MHz  MEM ${clk_mem} MHz"
line3+="\${alignr}Pw: ${pwr} W"

line4="VRAM: ${mem_used}/${mem_total} MiB"

case "$mode" in
  header)
    printf '%s\n' "$line1"
    ;;
  footer)
    printf '%s\n' "$line3"
    printf '%s\n' "$line4"
    ;;
  *)
    printf '%s\n' "$line1"
    printf '%s\n' "$line3"
    printf '%s\n' "$line4"
    ;;
esac
