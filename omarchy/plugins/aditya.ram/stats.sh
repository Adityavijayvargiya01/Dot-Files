#!/usr/bin/env bash
set -eu

mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
used=$((mem_total - mem_avail))
pct=$(awk -v u="$used" -v t="$mem_total" 'BEGIN {printf "%.2f", (u/t)*100}')

hwmon_celsius() {
  local dir="$1" f val best=""
  for f in "$dir"/temp*_input; do
    [ -r "$f" ] || continue
    val=$(cat "$f" 2>/dev/null) || continue
    case "$val" in ''|*[!0-9]*) continue;; esac
    if [ -z "$best" ] || [ "$val" -gt "$best" ]; then best="$val"; fi
  done
  if [ -z "$best" ]; then
    printf -- "-1"
  else
    awk -v v="$best" 'BEGIN { printf "%.0f", (v + 500) / 1000 }'
  fi
}

cpu_temp=-1
for d in /sys/class/hwmon/hwmon*; do
  name=$(cat "$d/name" 2>/dev/null) || continue
  case "$name" in
    k10temp|zenpower|cpu_thermal|coretemp|acpitz) ;;
    *) continue ;;
  esac
  cpu_temp=$(hwmon_celsius "$d")
  [ "$cpu_temp" != "-1" ] && break
done

igpu_temp=-1
dgpu_temp=-1
for c in /sys/class/drm/card[0-9]; do
  dev="$c/device"
  class=$(cat "$dev/class" 2>/dev/null) || continue
  case "$class" in
    0x030000|0x030200) ;;
    *) continue ;;
  esac
  boot=$(cat "$dev/boot_vga" 2>/dev/null || echo 0)
  temp=-1
  for h in "$dev"/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    temp=$(hwmon_celsius "$h")
    [ "$temp" != "-1" ] && break
  done
  if [ "$boot" = "1" ]; then
    igpu_temp="$temp"
  else
    dgpu_temp="$temp"
  fi
done

if [ "$dgpu_temp" = "-1" ] && command -v nvidia-smi >/dev/null 2>&1; then
  nv=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')
  case "$nv" in
    ''|*[!0-9]*) ;;
    *) dgpu_temp="$nv" ;;
  esac
fi

printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$pct" "$used" "$mem_total" "$cpu_temp" "$igpu_temp" "$dgpu_temp"
