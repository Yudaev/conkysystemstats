#!/usr/bin/env bash
# GPU summary for Conky. Supports NVIDIA (nvidia-smi) and AMD (sysfs / amdgpu).

set -u
LC_ALL=C

mode=${1:-all}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
COMMON_LIB="$SCRIPT_DIR/lib/gpu_common.sh"

if [[ -r "$COMMON_LIB" ]]; then
  # shellcheck disable=SC1090
  source "$COMMON_LIB"
else
  echo "GPU: helper library not found"
  exit 1
fi

render_nvidia() {
  local util_g temp mem_used mem_total pwr fan clk_sm clk_mem util_str line1 line3 line4

  if ! command -v nvidia-smi >/dev/null 2>&1; then
    if [[ "$mode" != "footer" ]]; then
      echo "GPU: NVIDIA не обнаружена (nvidia-smi нет)"
    fi
    return
  fi

  IFS=',' read -r util_g temp mem_used mem_total pwr fan clk_sm clk_mem < <(
    nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,fan.speed,clocks.sm,clocks.mem \
               --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' %'
  )

  util_g=${util_g:-0}; temp=${temp:-0}; mem_used=${mem_used:-0}; mem_total=${mem_total:-0}
  pwr=${pwr:-0}; fan=${fan:-0}; clk_sm=${clk_sm:-0}; clk_mem=${clk_mem:-0}

  printf -v util_str "%d%%" "${util_g:-0}"

  line1="\${font Ubuntu:bold:size=11}GPU\${font} ${util_str}"
  line1+="\${alignr}Temp: ${temp}°C  Fan: ${fan}%"

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
}

read_hwmon_temp() {
  local hwmon=$1 match=$2 label_file idx value_file label
  for label_file in "$hwmon"/temp*_label; do
    [[ -e "$label_file" ]] || continue
    read -r label <"$label_file"
    label=${label,,}
    if [[ "$label" == *"$match"* ]]; then
      idx=${label_file##*/temp}
      idx=${idx%_label}
      value_file="$hwmon/temp${idx}_input"
      if [[ -r "$value_file" ]]; then
        awk '{printf "%.0f", $1/1000}' "$value_file"
        return 0
      fi
    fi
  done
  return 1
}

read_current_clock() {
  local file=$1 freq
  [[ -r "$file" ]] || return 1
  freq=$(awk '/\*/ {print $2; exit}' "$file")
  freq=${freq//[^0-9.]/}
  [[ -n "$freq" ]] || return 1
  printf '%s\n' "$freq"
}

render_amd() {
  local card hwmon util temp_core temp_hotspot mem_used mem_total fan_percent power_w clk_s clk_m
  local line1 line3 line4 util_str mem_used_str mem_total_str fan_display power_display clk_s_display clk_m_display

  card=$(select_gpu_card amd) || card=""
  if [[ -z "$card" ]]; then
    if [[ "$mode" != "footer" ]]; then
      echo "GPU: AMD не обнаружена"
    fi
    return
  fi

  hwmon=$(find_hwmon_dir "$card") || hwmon=""

  if [[ -r "$card/device/gpu_busy_percent" ]]; then
    util=$(<"$card/device/gpu_busy_percent")
  else
    util=0
  fi
  [[ "$util" =~ ^[0-9]+$ ]] || util=0
  printf -v util_str "%d%%" "$util"

  local mem_used_file mem_total_file
  for candidate in memory_info_vram_used mem_info_vram_used; do
    if [[ -r "$card/device/$candidate" ]]; then
      mem_used_file="$card/device/$candidate"
      break
    fi
  done
  for candidate in memory_info_vram_total mem_info_vram_total; do
    if [[ -r "$card/device/$candidate" ]]; then
      mem_total_file="$card/device/$candidate"
      break
    fi
  done

  if [[ -n "${mem_used_file:-}" ]]; then
    mem_used=$(awk '{printf "%.0f", $1/1048576}' "$mem_used_file")
  else
    mem_used=""
  fi

  if [[ -n "${mem_total_file:-}" ]]; then
    mem_total=$(awk '{printf "%.0f", $1/1048576}' "$mem_total_file")
  else
    mem_total=""
  fi

  if [[ -z "$mem_total" || "$mem_total" == "0" ]]; then
    mem_used_str="--"
    mem_total_str="--"
  else
    if [[ -z "$mem_used" ]]; then
      mem_used_str="0"
    else
      mem_used_str="$mem_used"
    fi
    mem_total_str="$mem_total"
  fi

  temp_core="--"
  temp_hotspot="--"
  if [[ -n "$hwmon" ]]; then
    temp_core=$(read_hwmon_temp "$hwmon" edge 2>/dev/null || true)
    temp_hotspot=$(read_hwmon_temp "$hwmon" junction 2>/dev/null || true)
    if [[ -z "$temp_core" && -r "$hwmon/temp1_input" ]]; then
      temp_core=$(awk '{printf "%.0f", $1/1000}' "$hwmon/temp1_input")
    fi
    if [[ -z "$temp_hotspot" ]]; then
      local candidate label idx value_file
      for candidate in "$hwmon"/temp*_label; do
        [[ -e "$candidate" ]] || continue
        read -r label <"$candidate"
        label=${label,,}
        if [[ "$label" == *hotspot* || "$label" == *junction* ]]; then
          idx=${candidate##*/temp}
          idx=${idx%_label}
          value_file="$hwmon/temp${idx}_input"
          if [[ -r "$value_file" ]]; then
            temp_hotspot=$(awk '{printf "%.0f", $1/1000}' "$value_file")
          fi
          break
        fi
      done
    fi
  fi

  [[ -n "$temp_core" ]] || temp_core="--"
  [[ -n "$temp_hotspot" ]] || temp_hotspot="--"

  fan_percent="--"
  if [[ -n "$hwmon" ]]; then
    if [[ -r "$hwmon/fan1_input" ]]; then
      fan_percent=$(awk '{printf "%.0f", $1}' "$hwmon/fan1_input")
      [[ -n "$fan_percent" ]] && fan_percent+="rpm"
    elif [[ -r "$hwmon/pwm1" ]]; then
      local pwm pwm_max
      pwm=$(<"$hwmon/pwm1")
      pwm_max=255
      if [[ -r "$hwmon/pwm1_max" ]]; then
        pwm_max=$(<"$hwmon/pwm1_max")
      fi
      if [[ "$pwm" =~ ^[0-9]+$ && "$pwm_max" =~ ^[0-9]+$ ]]; then
        if (( pwm_max > 0 )); then
          fan_percent=$(awk -v pwm="$pwm" -v max="$pwm_max" 'BEGIN { if (max > 0) printf "%.0f", (pwm * 100)/max }')
        fi
      fi
    fi
  fi

  power_w="--"
  if [[ -n "$hwmon" && -r "$hwmon/power1_average" ]]; then
    power_w=$(awk '{printf "%.1f", $1/1000000}' "$hwmon/power1_average")
  fi

  clk_s="--"
  clk_m="--"
  if [[ -r "$card/device/pp_dpm_sclk" ]]; then
    clk_s=$(read_current_clock "$card/device/pp_dpm_sclk" 2>/dev/null || true)
  fi
  if [[ -r "$card/device/pp_dpm_mclk" ]]; then
    clk_m=$(read_current_clock "$card/device/pp_dpm_mclk" 2>/dev/null || true)
  fi

  [[ -n "$clk_s" ]] || clk_s="--"
  [[ -n "$clk_m" ]] || clk_m="--"

  local fan_display power_display clk_s_display clk_m_display
  if [[ -z "$fan_percent" ]]; then
    fan_percent="--"
  fi

  if [[ "$fan_percent" == "--" ]]; then
    fan_display="Fan: --"
  elif [[ "$fan_percent" =~ rpm$ ]]; then
    fan_display="Fan: ${fan_percent}"
  else
    fan_display="Fan: ${fan_percent}%"
  fi

  if [[ "$power_w" == "--" ]]; then
    power_display="Pw: --"
  else
    power_display="Pw: ${power_w} W"
  fi

  if [[ "$clk_s" == "--" ]]; then
    clk_s_display="SCLK --"
  else
    clk_s_display="SCLK ${clk_s} MHz"
  fi

  if [[ "$clk_m" == "--" ]]; then
    clk_m_display="MCLK --"
  else
    clk_m_display="MCLK ${clk_m} MHz"
  fi

  line1="\${font Ubuntu:bold:size=11}GPU\${font} ${util_str}"
  line1+="\${alignr}Temp: ${temp_core}°C  Hot: ${temp_hotspot}°C"

  line3="${clk_s_display}  ${clk_m_display}"
  line3+="\${alignr}${power_display}"

  line4="VRAM: ${mem_used_str}/${mem_total_str} MiB"
  line4+="\${alignr}${fan_display}"

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
}

vendor=$(detect_gpu_vendor)
case "$vendor" in
  nvidia)
    render_nvidia
    ;;
  amd)
    render_amd
    ;;
  *)
    if [[ "$mode" != "footer" ]]; then
      echo "GPU: устройство не обнаружено"
    fi
    ;;
esac
