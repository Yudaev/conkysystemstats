#!/usr/bin/env bash
# Показывает загрузку каждого CPU и помечает ядра с 3D-кэшем.
# Работает без сторонних утилит. Требуется доступ к /proc/stat и /sys/devices/system/cpu/*

set -euo pipefail
LC_ALL=C

# ---------- helpers ----------
read_stat() {
  # печатает строки вида: "cpuN total idle"
  awk '
    /^cpu[0-9]+ / {
      idle=$5+$6; total=0;
      for(i=2;i<=NF;i++) total+=$i;
      printf "%s %u %u\n",$1,total,idle
    }' /proc/stat
}

read_freq_ghz() {
  local cpu=${1:-}
  [[ -z "$cpu" ]] && { echo "-"; return; }
  local base="/sys/devices/system/cpu/$cpu" freq
  if [[ -r "$base/cpufreq/scaling_cur_freq" ]]; then
    freq=$(<"$base/cpufreq/scaling_cur_freq")
  elif [[ -r "$base/cpufreq/cpuinfo_cur_freq" ]]; then
    freq=$(<"$base/cpufreq/cpuinfo_cur_freq")
  else
    freq=""
  fi

  if [[ "$freq" =~ ^[0-9]+$ && $freq -gt 0 ]]; then
    awk -v f="$freq" 'BEGIN{printf "%.2f", f/1000000}'
  else
    echo "-"
  fi
}

collect_hwmon_temps() {
  declare -gA temps
  declare -gA ccd_temps
  temps=()
  ccd_temps=()

  for hw in /sys/class/hwmon/hwmon*; do
    [[ -d "$hw" ]] || continue
    [[ -r "$hw/name" ]] || continue
    name=$(<"$hw/name")
    case "$name" in
      k10temp*|zenpower*|coretemp*|it87*|nct*|asusec*|amd*|acpitz*) ;;
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
      value=$(( raw / 1000 ))
      temps["$label"]=$value
      if [[ "$label" =~ ^Tccd([0-9]+)$ ]]; then
        idx=${BASH_REMATCH[1]}
        ccd_temps["$idx"]=$value
      elif [[ "$label" =~ ^Core([0-9]+)$ ]]; then
        idx=${BASH_REMATCH[1]}
        temps["Core$idx"]=$value
      fi
    done
  done
}

temp_for_cpu() {
  local cpu="$1"
  local idx=${cpu#cpu}

  if [[ -n "${temps[Core$idx]:-}" ]]; then
    echo "${temps[Core$idx]}"
    return
  fi

  local die=${cpu_die[$cpu]:-}
  if [[ -n "$die" ]]; then
    local label=${die_to_ccd[$die]:-}
    if [[ -n "$label" && -n "${temps[$label]:-}" ]]; then
      echo "${temps[$label]}"
      return
    fi
  fi

  for fallback in Tctl Tdie Packageid0 temp1; do
    if [[ -n "${temps[$fallback]:-}" ]]; then
      echo "${temps[$fallback]}"
      return
    fi
  done

  echo "-"
}

# карта: cpuN -> 1 если 3D-кэш, иначе 0
declare -A is3d
while IFS= read -r cpuPath; do
  cpuN=$(basename "$cpuPath")
  # L3 обычно index3; бывает index2 — подстрахуемся, найдём «самый большой cache/index*/size»
  best=0
  while IFS= read -r f; do
    sz=$(cat "$f" 2>/dev/null | tr -d ' \t')
    # формат "32K/256K/2M/32M/96M" → в КБ
    if [[ "$sz" =~ ^([0-9]+)([KMG])$ ]]; then
      num=${BASH_REMATCH[1]}; unit=${BASH_REMATCH[2]}
      case "$unit" in
        K) kb=$num ;;
        M) kb=$(( num * 1024 )) ;;
        G) kb=$(( num * 1024 * 1024 )) ;;
      esac
      (( kb > best )) && best=$kb
    fi
  done < <(find "/sys/devices/system/cpu/$cpuN/cache" -maxdepth 2 -type f -name size 2>/dev/null | sort)
  # Порог для X3D-CCD: ≥ 64 МБ L3
  is3d["$cpuN"]=$(( best >= 64*1024 ? 1 : 0 ))
done < <(find /sys/devices/system/cpu -maxdepth 1 -type d -name 'cpu[0-9]*' | sort -V)

# ---------- usage per core ----------
declare -A t1 i1 t2 i2
while read -r id tot idle; do t1["$id"]=$tot; i1["$id"]=$idle; done < <(read_stat)
sleep 0.4
while read -r id tot idle; do t2["$id"]=$tot; i2["$id"]=$idle; done < <(read_stat)

# Формируем список cpuN по порядку
cpus=($(printf "%s\n" "${!t1[@]}" | sort -V))

total=${#cpus[@]}
(( total == 0 )) && exit 0

# Настройки вывода
CELLW=${CELLW:-28}          # ширина ячейки (символов)

declare -A cell_map
declare -A freq_map
declare -A temp_map
declare -A cpu_die
declare -A die_to_ccd
declare -A die_seen

for id in "${cpus[@]}"; do
  freq_map["$id"]=$(read_freq_ghz "$id")
  base="/sys/devices/system/cpu/$id/topology"
  die=""
  if [[ -r "$base/die_id" ]]; then
    die=$(<"$base/die_id")
  elif [[ -r "$base/core_id" ]]; then
    die="core$(<"$base/core_id")"
  elif [[ -r "$base/physical_package_id" ]]; then
    die="pkg$(<"$base/physical_package_id")"
  fi
  cpu_die["$id"]="$die"
  [[ -n "$die" ]] && die_seen["$die"]=1
done

collect_hwmon_temps

if (( ${#die_seen[@]} > 0 && ${#ccd_temps[@]} > 0 )); then
  mapfile -t die_ids < <(printf "%s\n" "${!die_seen[@]}" | sort)
  mapfile -t ccd_ids < <(printf "%s\n" "${!ccd_temps[@]}" | sort -n)
  limit=${#die_ids[@]}
  (( limit > ${#ccd_ids[@]} )) && limit=${#ccd_ids[@]}
  for (( i=0; i<limit; i++ )); do
    die=${die_ids[$i]}
    ccd_idx=${ccd_ids[$i]}
    die_to_ccd["$die"]="Tccd$ccd_idx"
  done
fi

for id in "${cpus[@]}"; do
  temp_map["$id"]=$(temp_for_cpu "$id")
done

for id in "${cpus[@]}"; do
  dt=$(( ${t2[$id]} - ${t1[$id]} ))
  di=$(( ${i2[$id]} - ${i1[$id]} ))
  use=0
  (( dt > 0 )) && use=$(( (100*(dt-di)) / dt ))
  idx=${id#cpu}
  mark=$([ "${is3d[$id]}" -eq 1 ] && echo "3D" || echo "  ")

  freq=${freq_map[$id]}
  if [[ "$freq" == "-" ]]; then
    freq_disp="  -  "
  else
    freq_disp=$(awk -v f="$freq" 'BEGIN{printf "%4.2fG", f+0}')
  fi

  temp=${temp_map[$id]}
  if [[ "$temp" == "-" ]]; then
    temp_disp=" --°C"
  else
    temp_disp=$(printf "%3d°C" "$temp")
  fi

  cell=$(printf "C%-2s:%3d%% %2s %s %s" "$idx" "$use" "$mark" "$freq_disp" "$temp_disp")
  printf -v cell_pad "%-*s" "$CELLW" "$cell"
  cell_map["$id"]="$cell_pad"
done

cpus3d=()
cpus_other=()
for id in "${cpus[@]}"; do
  if [ "${is3d[$id]}" -eq 1 ]; then
    cpus3d+=("$id")
  else
    cpus_other+=("$id")
  fi
done

rows=${#cpus3d[@]}
(( ${#cpus_other[@]} > rows )) && rows=${#cpus_other[@]}
(( rows == 0 )) && exit 0

for (( r=0; r<rows; r++ )); do
  line=""
  if (( r < ${#cpus3d[@]} )); then
    line+="${cell_map[${cpus3d[$r]}]}"
  else
    printf -v blank "%-*s" "$CELLW" ""
    line+="$blank"
  fi

  if (( r < ${#cpus_other[@]} )); then
    line+="${cell_map[${cpus_other[$r]}]}"
  else
    printf -v blank "%-*s" "$CELLW" ""
    line+="$blank"
  fi

  echo "$line"
done
