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
# keep the concise marketing name. Order matters:
#   1. drop the class prefix ("VGA compatible controller: ")
#   2. drop "(rev xx)" suffix
#   3. BRACKETED vendor forms ("Advanced Micro Devices, Inc. [AMD/ATI] Raphael")
#      — only stripped when the bracket follows a company marker (Inc./Ltd./
#      Corporation/...); a blind '^[^]]*] //' would eat NVIDIA marketing names
#      like "GB203 [GeForce RTX 5080]" down to "(rev a1)".
#   4. bracketless vendor prefixes (NVIDIA Corporation, ASPEED Technology, ...)
gpu=$(lspci 2>/dev/null | grep -iE "vga|3d controller|display controller" | head -1 | cut -d: -f3- \
  | sed -e 's/^ *//' -e 's/^[^:]*: //' -e 's/ (rev [0-9a-f]*)$//')
if printf '%s' "$gpu" | grep -qE '(Inc\.|Ltd\.|Corporation|Systems|Technology) \['; then
  gpu=$(printf '%s' "$gpu" | sed -e 's/^[^]]*\] //')
fi
gpu=$(printf '%s' "$gpu" | sed -e 's/^\(Intel Corporation\|NVIDIA Corporation\|Advanced Micro Devices, Inc\.\|ATI Technologies Inc\.\|Matrox Electronics Systems Ltd\.\|ASPEED Technology, Inc\.\|S3 Graphics Co\., Ltd\.\|Silicon Integrated Systems \[SiS\]\|Loongson Technology Co\., Ltd\.\|VMware SVGA II Adapter\|Red Hat, Inc\.\|Cirrus Logic\|Trident Microsystems\) //')

# --- GPU driver/module/vBIOS (nvidia procfs when present) --------------------
gpu_slot=$(lspci 2>/dev/null | grep -iE "vga|3d controller|display controller" | head -1 | awk '{print $1}')
gpu_driver=$(lspci -k -s "$gpu_slot" 2>/dev/null | sed -n 's/.*Kernel driver in use: //p')
gpu_module=""
case "$gpu_driver" in
  nvidia|nvidia_drm) gpu_module=$(modinfo -F version nvidia 2>/dev/null) ;;
  amdgpu) gpu_module=$(modinfo -F version amdgpu 2>/dev/null) ;;
esac
gpu_vbios=$(sed -n 's/^Video BIOS:[[:space:]]*//p' /proc/driver/nvidia/gpus/*/information 2>/dev/null | head -1)
gpu_name_proc=$(sed -n 's/^Model:[[:space:]]*//p' /proc/driver/nvidia/gpus/*/information 2>/dev/null | head -1)
# nvidia's own Model string is cleaner than lspci's when available
[ -n "$gpu_name_proc" ] && gpu="$gpu_name_proc"

# --- Memory -----------------------------------------------------------------
mem_total_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
dmi_mem=$(dmidecode -t memory 2>/dev/null)
# non-root dmidecode still prints a 2-line preamble before failing — only
# trust it if actual Size records came back
printf '%s' "$dmi_mem" | grep -q "^\\s*Size:" || dmi_mem=""
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
# lsblk pads columns and MODEL contains spaces, so parse from the END:
# transport = last token, serial = next-to-last, model = the rest.
disks=""
while read -r name bytes _type rest; do
  [ "$_type" = "disk" ] || continue
  case "$name" in zram*|loop*) continue ;; esac
  tran=${rest##* }
  rest=$(printf '%s' "${rest%*"$tran"}" | tr -s ' ' | sed 's/^ //;s/ $//')
  serial=${rest##* }
  model=${rest%*"$serial"}
  [ -n "$serial" ] || { serial="$tran"; tran=""; model="$rest"; }
  size=$(numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B")
  label="${model:-/dev/$name}"
  [ -n "$disks" ] && disks="$disks,"
  disks="$disks{\"name\":\"$(esc "$label")\",\"size\":\"$(esc "$size")\",\"serial\":\"$(esc "$serial")\",\"transport\":\"$(esc "$tran")\",\"dev\":\"$(esc "$name")\"}"
done < <(lsblk -dnb -o NAME,SIZE,TYPE,MODEL,SERIAL,TRAN 2>/dev/null)
[ -n "$disks" ] || disks=''

# --- Network controllers (+ kernel driver), line-based parse -----------------
nets=""
pcilspci=$(lspci -k 2>/dev/null)
while IFS=$'\t' read -r name drv; do
  [ -n "$name" ] || continue
  [ -n "$nets" ] && nets="$nets,"
  nets="$nets{\"name\":\"$(esc "$name")\",\"driver\":\"$(esc "$drv")\"}"
done < <(printf '%s\n' "$pcilspci" | awk '
  /(Ethernet|Network) controller/ { name=$0; sub(/^[0-9][0-9:.]* +/,"",name); sub(/^(Ethernet|Network) controller: /,"",name); sub(/ (PCI Express )?(Wireless )?Network Adapter$/,"",name); sub(/ Ethernet Controller$/,"",name); sub(/^(Intel Corporation|Realtek Semiconductor|Realtek|Broadcom Inc\. and subsidiaries|Broadcom|Qualcomm Atheros|MediaTek|ASUSTek Computer Inc\.|Aquantia Corp\.|Marvell Technology Group Ltd\.) /,"",name); drv="" }
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

# --- OS / platform ------------------------------------------------------------
kernel=$(uname -r)
os=$(grep -m1 PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
uptime_s=$(cut -d. -f1 /proc/uptime)
hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null)
[ -d /sys/firmware/efi ] && boot_mode="UEFI" || boot_mode="BIOS"
virt=$(systemd-detect-virt 2>/dev/null); [ -n "$virt" ] || virt="none"
plasma_ver=$(timeout 3 plasmashell --version 2>/dev/null | awk '{print $2}')
qt_ver=$(qmake6 --query QT_VERSION 2>/dev/null || /usr/lib64/qt6/bin/qtpaths6 --qt-version 2>/dev/null)
kf6_ver=$(rpm -q --qf '%{version}\n' kf6-kcoreaddons 2>/dev/null | head -1)
cpu_vendor=$(grep -m1 "^vendor_id" /proc/cpuinfo | awk '{print $3}')
serial_readable() {  # DMI serials are often 0400 root-only
  local v; v=$(cat "/sys/class/dmi/id/$1" 2>/dev/null)
  case "$v" in ""|"System Serial Number"|"Default string"|"To be filled by O.E.M.") printf '' ;;
    *) printf '%s' "$v" ;; esac
}

printf '{"identity":{"vendor":%s,"product":%s,"board":%s,"bios_version":%s,"bios_date":%s,"board_vendor":%s,"board_version":%s,"board_serial":%s,"product_version":%s,"product_serial":%s,"bios_vendor":%s},"cpu":{"model":"%s","arch":"%s","cores":%s,"threads":%d,"max_mhz":%s,"l3_kb":%s,"vendor":"%s"},"gpu":"%s","gpu_driver":"%s","gpu_module":"%s","gpu_vbios":"%s","mem":{"total_mb":%d,"banks":%s,"type":"%s","speed":"%s"},"displays":[%s],"disks":[%s],"net":[%s],"audio":[%s],"battery":%s,"bluetooth":%s,"io":{"usb_devices":%d,"pci_devices":%d},"os":{"kernel":"%s","pretty":"%s","uptime_s":%d,"hostname":"%s","boot":"%s","virt":"%s","plasma":"%s","qt":"%s","kf6":"%s"}}\n' \
  "$(dmi sys_vendor)" "$(dmi product_name)" "$(dmi board_name)" "$(dmi bios_version)" "$(dmi bios_date)" \
  "$(dmi board_vendor)" "$(dmi board_version)" "$(qs "$(serial_readable board_serial)")" "$(dmi product_version)" "$(qs "$(serial_readable product_serial)")" "$(dmi bios_vendor)" \
  "$(esc "$cpu_model")" "$(esc "$cpu_arch")" "$cpu_cores" "$cpu_threads" "$cpu_mhz" "$l3_kb" "$(esc "$cpu_vendor")" \
  "$(esc "$gpu")" "$(esc "$gpu_driver")" "$(esc "$gpu_module")" "$(esc "$gpu_vbios")" \
  $((mem_total_kb / 1024)) "$mem_banks" "$(esc "$mem_type")" "$(esc "$mem_speed")" \
  "$displays" "$disks" "$nets" "$audios" "$battery_json" "$has_bt" "$usb_count" "$pci_count" \
  "$(esc "$kernel")" "$(esc "$os")" "$uptime_s" "$(esc "$hostname")" "$(esc "$boot_mode")" "$(esc "$virt")" "$(esc "$plasma_ver")" "$(esc "$qt_ver")" "$(esc "$kf6_ver")"
