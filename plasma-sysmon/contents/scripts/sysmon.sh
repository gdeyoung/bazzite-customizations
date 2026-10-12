#!/bin/bash
# SysMon probe for gdeyoung.sysmon.
# Forked from sysmem.sh in vm.sysmem by jhonoryza (MIT).
#
# Prints exactly one JSON line so the QML widget can JSON.parse it:
#   {"ram_used_mb":1234,"ram_total_mb":31319,
#    "cpu_total":123456,"cpu_idle":65432,"cpu_cores":[[total,idle],...],
#    "load1":0.58,"load5":0.71,"load15":0.64,
#    "net_rx":123456789,"net_tx":9876543,"net_if":{"wlan0":[rx,tx]},
#    "disk_used_b":47000000000,"disk_total_b":999000000000,
#    "disk_reads":1234,"disk_rsec":5678,"disk_writes":910,"disk_wsec":1121,
#    "mem_buffers_kb":896,"mem_cached_kb":15579104,
#    "swap_total_kb":63875060,"swap_used_kb":298912,"zswapped_kb":0,
#    "cpu_temp_mc":63000,"gpu_temp_mc":57000,"nvme_temp_mc":30000,
#    "gpu_busy_pct":12,"vram_used_b":506609664,"vram_total_b":536870912,
#    "gtt_used_b":2081701888,"gtt_total_b":16352243712,"gpu_power_mw":19789}
#
# cpu_*/net_*/disk_* counters are cumulative: the widget computes rates from
# deltas between ticks. Absent sensors/GPU emit -1 (widget treats <0 as n/a).
set -u

# --- RAM + detail ------------------------------------------------------------
mem_total=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)
ram_used=$((mem_total - mem_avail))
mem_buffers=$(awk '/^Buffers:/ { print $2 + 0 }' /proc/meminfo)
mem_cached=$(awk '/^Cached:/ { print $2 + 0 }' /proc/meminfo)
swap_total=$(awk '/^SwapTotal:/ { print $2 + 0 }' /proc/meminfo)
swap_free=$(awk '/^SwapFree:/ { print $2 + 0 }' /proc/meminfo)
swap_used=$((swap_total - swap_free))
zswapped=$(awk '/^Zswapped:/ { print $2 + 0 }' /proc/meminfo)

# --- CPU: aggregate + per-core jiffies, load ---------------------------------
read -r cpu_total cpu_idle < <(awk 'NR==1 { print $2+$3+$4+$5+$6+$7+$8+$9, $5+$6 }' /proc/stat)
cores_json=$(awk '/^cpu[0-9]/ { printf "%s[%d,%d]", (NR>2?",":""), $2+$3+$4+$5+$6+$7+$8+$9, $5+$6 }' /proc/stat)
read -r load1 load5 load15 _ < /proc/loadavg

# --- Net: cumulative rx/tx per interface (except lo) --------------------------
net_rx=0
net_tx=0
if_json=""
for iface in /sys/class/net/*; do
  name=$(basename "$iface")
  [[ $name == "lo" ]] && continue
  rx=$(cat "$iface/statistics/rx_bytes" 2>/dev/null) || continue
  [[ $rx =~ ^[0-9]+$ ]] || continue
  tx=$(cat "$iface/statistics/tx_bytes" 2>/dev/null) || continue
  [[ $tx =~ ^[0-9]+$ ]] || continue
  net_rx=$((net_rx + rx))
  net_tx=$((net_tx + tx))
  if_json="${if_json}${if_json:+,}\"${name}\":[${rx},${tx}]"
done

# --- Disk: mounted volumes + whole-disk size + fs used + IO counters -------
# vols: real local filesystems only (tmpfs/devtmpfs/efivarfs/overlay excluded
# via df -x), deduped by source device — btrfs subvolume mounts (/home,
# /var/log, ...) share one device and must show as one gauge. Format:
#   "vols":[["/",usedB,sizeB],["/boot",usedB,sizeB],...]
disk_used=0
disk_total=0
disk_dev=""
vols_json=""
resolve_disk() {  # $1 = device name; echoes whole-disk name (e.g. nvme0n1)
  local cur="/dev/$1" parent
  case "$1" in
    /dev/*) cur="$1" ;;
  esac
  [ -e "$cur" ] || return 1
  while :; do
    parent=$(lsblk -dno PKNAME "$cur" 2>/dev/null) || break
    [ -n "$parent" ] || break
    cur="/dev/$parent"
  done
  basename "$cur"
}
vols_json=$(df -B1 --local \
    -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs \
    --output=source,fstype,used,size,target 2>/dev/null | awk '
    NR > 1 { tgt = $5; for (i = 6; i <= NF; i++) tgt = tgt " " $i }
    NR > 1 && !seen[$1]++ { printf "%s[\"%s\",%s,%s]", (n++ ? "," : ""), tgt, $3, $4 }')
if src=$(findmnt -no SOURCE /home 2>/dev/null); then
  src="${src%%\[*}"                      # strip btrfs subvol: /dev/mapper/root[/@home]
  if read -r u _ < <(df -B1 --output=used,size "$src" 2>/dev/null | tail -n 1); then
    [[ $u =~ ^[0-9]+$ ]] && disk_used=$u
  fi
  if disk_dev=$(resolve_disk "$(basename "$src")" 2>/dev/null) && [ -e "/dev/$disk_dev" ]; then
    t=$(lsblk -bno SIZE "/dev/$disk_dev" 2>/dev/null)
    [[ $t =~ ^[0-9]+$ ]] && disk_total=$t
  fi
fi
if [ "$disk_total" -eq 0 ]; then
  # fallback: plain filesystem numbers for /home
  if read -r u t < <(df -B1 --output=used,size /home 2>/dev/null | tail -n 1); then
    [[ $u =~ ^[0-9]+$ ]] && disk_used=$u
    [[ $t =~ ^[0-9]+$ ]] && disk_total=$t
  fi
fi
disk_reads=0; disk_rsec=0; disk_writes=0; disk_wsec=0
if [ -n "$disk_dev" ] && [ -e /proc/diskstats ]; then
  stats=$(awk -v dev="$disk_dev" '$3==dev { print $4+0, $6+0, $8+0, $10+0; exit }' /proc/diskstats)
  [ -n "$stats" ] && read -r disk_reads disk_rsec disk_writes disk_wsec <<< "$stats"
fi

# --- Temps (millidegrees, by hwmon name) --------------------------------------
cpu_temp=-1; gpu_temp=-1; nvme_temp=-1
for d in /sys/class/hwmon/hwmon*; do
  case $(cat "$d/name" 2>/dev/null) in
    k10temp|coretemp|zenpower) [ "$cpu_temp" -lt 0 ] && cpu_temp=$(cat "$d/temp1_input" 2>/dev/null || echo -1) ;;
    amdgpu)                    gpu_temp=$(cat "$d/temp1_input" 2>/dev/null || echo -1) ;;
    nvme)                      nvme_temp=$(cat "$d/temp1_input" 2>/dev/null || cat "$d/temp" 2>/dev/null || echo -1) ;;
  esac
done

# --- GPU (amdgpu DRM device) ---------------------------------------------------
gpu_busy=-1; vram_used=-1; vram_total=-1; gtt_used=-1; gtt_total=-1; gpu_power=-1
for d in /sys/class/drm/card*/device; do
  [ -f "$d/gpu_busy_percent" ] || continue
  gpu_busy=$(cat "$d/gpu_busy_percent" 2>/dev/null || echo -1)
  vram_used=$(cat "$d/mem_info_vram_used" 2>/dev/null || echo -1)
  vram_total=$(cat "$d/mem_info_vram_total" 2>/dev/null || echo -1)
  gtt_used=$(cat "$d/mem_info_gtt_used" 2>/dev/null || echo -1)
  gtt_total=$(cat "$d/mem_info_gtt_total" 2>/dev/null || echo -1)
  break
done
for d in /sys/class/hwmon/hwmon*; do
  if [ "$(cat "$d/name" 2>/dev/null)" = "amdgpu" ] && [ -f "$d/power1_average" ]; then
    p=$(cat "$d/power1_average" 2>/dev/null) || p=""
    [[ $p =~ ^[0-9]+$ ]] && gpu_power=$((p / 1000))   # µW -> mW
  fi
done

printf '{"ram_used_mb":%d,"ram_total_mb":%d,"mem_buffers_kb":%s,"mem_cached_kb":%s,"swap_total_kb":%s,"swap_used_kb":%s,"zswapped_kb":%s,"cpu_total":%s,"cpu_idle":%s,"cpu_cores":[%s],"load1":%s,"load5":%s,"load15":%s,"net_rx":%s,"net_tx":%s,"net_if":{%s},"disk_used_b":%s,"disk_total_b":%s,"vols":[%s],"disk_reads":%s,"disk_rsec":%s,"disk_writes":%s,"disk_wsec":%s,"cpu_temp_mc":%s,"gpu_temp_mc":%s,"nvme_temp_mc":%s,"gpu_busy_pct":%s,"vram_used_b":%s,"vram_total_b":%s,"gtt_used_b":%s,"gtt_total_b":%s,"gpu_power_mw":%s}\n' \
  "$ram_used" "$mem_total" "$mem_buffers" "$mem_cached" "$swap_total" "$swap_used" "$zswapped" \
  "$cpu_total" "$cpu_idle" "$cores_json" "$load1" "$load5" "$load15" \
  "$net_rx" "$net_tx" "$if_json" \
  "$disk_used" "$disk_total" "$vols_json" "$disk_reads" "$disk_rsec" "$disk_writes" "$disk_wsec" \
  "$cpu_temp" "$gpu_temp" "$nvme_temp" \
  "$gpu_busy" "$vram_used" "$vram_total" "$gtt_used" "$gtt_total" "$gpu_power"
