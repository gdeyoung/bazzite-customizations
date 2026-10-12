#!/usr/bin/env bash
# sysinfo-probe.sh — static hardware inventory for gdeyoung.sysmon's Hardware tab.
# One JSON line, unprivileged, fastfetch-grade: DMI identity + BIOS, CPU, memory,
# GPU, displays, physical disks, network controllers (+drivers), audio, battery,
# Bluetooth, I/O counts, OS. Static — probed on panel open, not per tick.
set -u
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
qs() { printf '"%s"' "$(esc "$1")"; }
dmi() { qs "$(cat "/sys/class/dmi/id/$1" 2>/dev/null)"; }

# --- CPU --------------------------------------------------------------------
cpu_model=$(grep -m1 "^model name" /proc/cpuinfo | cut -f2- -d: | sed 's/^ //')
cpu_arch=$(uname -m)
cpu_threads=$(nproc)
sockets=$(lscpu 2>/dev/null | awk -F: '/^Socket\(s\)/ { gsub(/ /,"",$2); print $2 }' | head -1)
cps=$(lscpu 2>/dev/null | awk -F: '/^Core\(s\) per socket/ { gsub(/ /,"",$2); print $2 }')
if [ -n "$sockets" ] && [ -n "$cps" ] && [ "$sockets" -gt 0 ] 2>/dev/null; then
  cpu_cores=$((cps * sockets))
else
  cpu_cores=null
fi
cpu_mhz=$(lscpu 2>/dev/null | awk -F: '/^CPU max MHz/ { print int($2) }')
cpu_mhz=${cpu_mhz:-null}
l3_kb=$(lscpu 2>/dev/null | awk -F: '/^L3 cache:/ {
  v=$2 + 0; u=$2; sub(/^ +[0-9.]+ +/,"",u)
  if (u ~ /MiB/) print int(v * 1024); else if (u ~ /KiB/) print int(v); else if (u ~ /GiB/) print int(v * 1048576); else print int(v)
}')
l3_kb=${l3_kb:-null}

# --- GPU --------------------------------------------------------------------
# lspci prefixes the vendor ("Advanced Micro Devices, Inc. [AMD/ATI] " etc.) —
# keep the concise marketing name: drop bracketed vendor forms, then the
# common bracketless vendor prefixes, then the "(rev xx)" suffix.
gpu=$(lspci 2>/dev/null | grep -iE "vga|3d controller|display controller" | head -1 | cut -d: -f3- \
  | sed -e 's/^ *//' -e 's/^[^]]*\] //' \
        -e 's/^\(Intel Corporation\|NVIDIA Corporation\|Advanced Micro Devices, Inc\.\|ATI Technologies Inc\.\|Matrox Electronics Systems Ltd\.\|ASPEED Technology, Inc\.\|S3 Graphics Co\., Ltd\.\|Silicon Integrated Systems \[SiS\]\|Loongson Technology Co\., Ltd\.\|VMware SVGA II Adapter\|Red Hat, Inc\.\|Cirrus Logic\| Trident Microsystems\) //' \
        -e 's/ (rev [0-9a-f]*)$//')

# --- Memory -----------------------------------------------------------------
mem_total_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
dmi_mem=$(dmidecode -t memory 2>/dev/null)
if [ -n "$dmi_mem" ]; then
  mem_banks=$(printf '%s' "$dmi_mem" | awk '/Size:.*[GM]B/ { n++ } END { print n + 0 }')
  mem_type=$(printf '%s' "$dmi_mem" | awk -F: '/Type:/ { gsub(/^ +/,"",$2); print $2; exit }')
  mem_speed=$(printf '%s' "$dmi_mem" | awk -F: '/Configured Memory Speed:/ { gsub(/^ +/,"",$2); print $2; exit }')
else
  mem_banks=null; mem_type=""; mem_speed=""
fi

# --- Displays (connected DRM connectors + preferred mode) --------------------
displays=""
for c in /sys/class/drm/card*-*; do
  [ -f "$c/status" ] || continue
  [ "$(cat "$c/status" 2>/dev/null)" = "connected" ] || continue
  conn=$(basename "$c"); conn=${conn#card*-}
  mode=$(head -1 "$c/modes" 2>/dev/null)
  [ -n "$displays" ] && displays="$displays,"
  displays="$displays{\"connector\":\"$(esc "$conn")\",\"mode\":\"$(esc "$mode")\"}"
done
[ -n "$displays" ] || displays=''

# --- Storage (physical disks only; zram/loop are virtual) --------------------
disks=""
while read -r name bytes _type model; do
  [ "$_type" = "disk" ] || continue
  case "$name" in zram*|loop*) continue ;; esac
  size=$(numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B")
  label="${model:-/dev/$name}"
  [ -n "$disks" ] && disks="$disks,"
  disks="$disks{\"name\":\"$(esc "$label")\",\"size\":\"$(esc "$size")\"}"
done < <(lsblk -dnb -o NAME,SIZE,TYPE,MODEL 2>/dev/null)
[ -n "$disks" ] || disks=''

# --- Network controllers (+ kernel driver), line-based parse -----------------
nets=""
pcilspci=$(lspci -k 2>/dev/null)
while IFS=$'\t' read -r name drv; do
  [ -n "$name" ] || continue
  [ -n "$nets" ] && nets="$nets,"
  nets="$nets{\"name\":\"$(esc "$name")\",\"driver\":\"$(esc "$drv")\"}"
done < <(printf '%s\n' "$pcilspci" | awk '
  /(Ethernet|Network) controller/ { name=$0; sub(/^[0-9][0-9:.]* +/,"",name); sub(/^(Ethernet|Network) controller: /,"",name); sub(/ (PCI Express )?(Wireless )?Network Adapter$/,"",name); sub(/ Ethernet Controller$/,"",name); drv="" }
  name != "" && /Kernel driver in use:/ { drv=$0; sub(/.*Kernel driver in use: */,"",drv); printf "%s\t%s\n", name, drv; name="" }
  END { if (name != "") printf "%s\t%s\n", name, "" }')
[ -n "$nets" ] || nets=''

# --- Audio (dedupe identical card names: "name ×N") ---------------------------
audios=""
while read -r card; do
  [ -n "$card" ] || continue
  [ -n "$audios" ] && audios="$audios,"
  audios="$audios$(qs "$card")"
done < <(awk '/^ [0-9]+ \[/ { sub(/^.*\]: /,""); print }' /proc/asound/cards 2>/dev/null | sort | uniq -c | awk '{ n=$1; $1=""; sub(/^ +/,""); if (n > 1) print $0 " ×" n; else print $0 }')

# --- Battery -----------------------------------------------------------------
BAT=""
for d in /sys/class/power_supply/BAT*; do
  [ -d "$d" ] && BAT="$d" && break
done
if [ -n "$BAT" ]; then
  bat_manu=$(cat "$BAT/manufacturer" 2>/dev/null)
  bat_model=$(cat "$BAT/model_name" 2>/dev/null)
  bat_tech=$(cat "$BAT/technology" 2>/dev/null)
  bf=$(cat "$BAT/charge_full" 2>/dev/null || cat "$BAT/energy_full" 2>/dev/null)
  bd=$(cat "$BAT/charge_full_design" 2>/dev/null || cat "$BAT/energy_full_design" 2>/dev/null)
  bat_health=null
  if [ -n "$bf" ] && [ -n "$bd" ] && [ "$bd" -gt 0 ] 2>/dev/null; then
    bat_health=$(awk -v f="$bf" -v d="$bd" 'BEGIN { printf "%.1f", f / d * 100 }')
  fi
  bsn=$(cat "$BAT/serial_number" 2>/dev/null)
  battery_json="{\"manufacturer\":$(qs "$bat_manu"),\"model\":$(qs "$bat_model"),\"tech\":$(qs "$bat_tech"),\"health_pct\":$bat_health,\"serial_tail\":\"$(printf '%s' "$bsn" | tail -c 5)\"}"
else
  battery_json=null
fi

# --- Bluetooth / I/O counts ---------------------------------------------------
has_bt=false; [ -d /sys/class/bluetooth ] && has_bt=true
usb_count=$(lsusb 2>/dev/null | wc -l)
pci_count=$(lspci 2>/dev/null | wc -l)

# --- OS ----------------------------------------------------------------------
kernel=$(uname -r)
os=$(grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
uptime_s=$(cut -d. -f1 /proc/uptime)

printf '{"identity":{"vendor":%s,"product":%s,"board":%s,"bios_version":%s,"bios_date":%s},"cpu":{"model":"%s","arch":"%s","cores":%s,"threads":%d,"max_mhz":%s,"l3_kb":%s},"gpu":"%s","mem":{"total_mb":%d,"banks":%s,"type":"%s","speed":"%s"},"displays":[%s],"disks":[%s],"net":[%s],"audio":[%s],"battery":%s,"bluetooth":%s,"io":{"usb_devices":%d,"pci_devices":%d},"os":{"kernel":"%s","pretty":"%s","uptime_s":%d}}\n' \
  "$(dmi sys_vendor)" "$(dmi product_name)" "$(dmi board_name)" "$(dmi bios_version)" "$(dmi bios_date)" \
  "$(esc "$cpu_model")" "$(esc "$cpu_arch")" "$cpu_cores" "$cpu_threads" "$cpu_mhz" "$l3_kb" \
  "$(esc "$gpu")" $((mem_total_kb / 1024)) "$mem_banks" "$(esc "$mem_type")" "$(esc "$mem_speed")" \
  "$displays" "$disks" "$nets" "$audios" "$battery_json" "$has_bt" "$usb_count" "$pci_count" \
  "$(esc "$kernel")" "$(esc "$os")" "$uptime_s"
