#!/bin/bash
# Process probe for gdeyoung.sysmon (popup only).
# Prints one JSON line: top processes by CPU% —
#   {"procs":[[pid,user,comm,pcpu,pmem,state],...]}
# Run on the popup's own slower timer; not part of the bar tick.
set -u
ps -eo pid,user,comm,pcpu,pmem,state --no-headers --sort=-pcpu | head -14 | awk '{
  printf "%s[%d,\"%s\",\"%s\",%.1f,%.1f,\"%s\"]", (NR>1 ? "," : ""), $1, $2, $3, $4, $5, $6
}' | { printf "{\"procs\":["; cat; printf "]}\n"; }
