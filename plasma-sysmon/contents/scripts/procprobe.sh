#!/bin/bash
# Process probe for com.gdeyoung.plasma.sysmon v0.7 (popup only).
#
# v2 — full list instead of top-14-by-CPU. The old shape made MEM-sort
# re-sort a CPU-biased subset and hid mem-hungry idle processes entirely.
# Row: [pid,user,name,pcpu,pmem,rss_kb,state,args]
#   rss_kb and args are new; user/state were captured since v0.1 but never
#   displayed. args truncated to 120 chars, JSON-escaped (args carry quotes).
#
# COLUMN RULE: ps `comm` can contain spaces ("tmux: server") which would
# shift every later column — so comm is NOT requested. All requested fields
# before `args` are guaranteed single-token; the display name is derived
# from basename(args[0]) (bracket-stripped for kernel threads/zombies).
#
# v2.1 — completeness fix: hosts can exceed any fixed cap (gdtower runs
# ~1000 procs), and a 0%-CPU target (the thing you most often want to find
# and kill) sorts LAST by CPU — a plain head cap makes search miss it.
# Rows kept = top-1500 by CPU UNION any row matching the filter substring
# (arg 1). Emitted when the Processes tab is visible, on a 2s tick.
set -u
FILTER="${1:-}"
ps -eo pid,user,pcpu,pmem,rss,state,args --no-headers --sort=-pcpu | awk -v F="$FILTER" -v CAP=1500 '
{
  keep = (NR <= CAP)
  if (!keep && F != "") keep = (index(tolower($0), tolower(F)) > 0)
  if (!keep) next
  u=$2; pcpu=$3; pmem=$4; rss=$5; st=$6
  a=""
  for (i=7; i<=NF; i++) a=a (i>7?" ":"") $i
  n=a; sub(/ .*/, "", n); gsub(/^\[|\]$/, "", n)
  if (match(n, /\/[^\/]+$/)) n=substr(n, RSTART+1)
  if (n=="") n="?"
  a=substr(a,1,120)
  gsub(/\\/,"\\\\",a); gsub(/"/,"\\\"",a); gsub(/[[:cntrl:]]/, " ",a)
  gsub(/\\/,"\\\\",u); gsub(/"/,"\\\"",u)
  gsub(/\\/,"\\\\",n); gsub(/"/,"\\\"",n)
  printf "%s[%d,\"%s\",\"%s\",%.1f,%.1f,%d,\"%s\",\"%s\"]", (emitted++ > 0 ? "," : ""), $1, u, n, pcpu, pmem, rss, st, a
}' | { printf "{\"procs\":["; cat; printf "]}\n"; }
